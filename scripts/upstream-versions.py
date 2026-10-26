#!/usr/bin/env python3
"""Check the pins in config/versions.env against upstream; optionally bump them.

Usage:
  python3 scripts/upstream-versions.py                 report (table on stdout)
  python3 scripts/upstream-versions.py --apply         rewrite config/versions.env,
                                                       sbom.cdx.json and SBOM.md
  python3 scripts/upstream-versions.py --summary FILE  also write a Markdown
                                                       summary (the nightly PR body)
  python3 scripts/upstream-versions.py --github-output write changed=/manual=
                                                       lines to $GITHUB_OUTPUT
  python3 scripts/upstream-versions.py --selftest      parser checks against the
                                                       embedded samples, no network

The nightly upstream-versions workflow runs this and opens a pull request when
something moved. Each pin is resolved from the place its module actually
installs from, so a bump here is what the installer would fetch:

  MAVEN_VERSION        newest final 3.x in Maven Central's apache-maven metadata
  ELASTIC_VERSION      endoflife.date/api/elasticsearch.json (newest cycle's latest)
  OPENSEARCH_VERSION   endoflife.date/api/opensearch.json
  LLVM_VERSION         newest final LLVM major (GitHub releases) that already has
                       an apt.llvm.org suite for LLVM_APT_CODENAME
  K9S_VERSION          newest derailed/k9s GitHub release
  NVM_VERSION          newest nvm-sh/nvm GitHub release
  PROTON_VPN_RELEASE_DEB (+_SHA256)
                       newest protonvpn-stable-release .deb in Proton's repo
                       listing; the sha256 is computed from the download
  SEVENZIP_VERSION (+_SHA256)
                       newest ip7z/7zip GitHub release (Igor Pavlov's own
                       channel); the sha256 is computed from the download
  STRATA_VERSION (+ STRATA_INSTALL_SH_SHA256, STRATA_INSTALL_PS1_SHA256)
                       newest Niko1221/Strata GitHub release; both installer
                       scripts' sha256 computed from the downloads
  JDK_MAJOR            REPORT ONLY: Adoptium's most recent LTS (distro packaging
                       lags a new LTS; bump by hand once openjdk-N-jdk exists)
  GO_VERSION, LLAMA_CPP_VERSION, KOBOLDCPP_VERSION, IK_LLAMA_CPP_REF
                       "latest"/a branch resolve at install time; not checked

A resolver that fails (network, format change) is reported and skipped; it
never blocks the other pins. Exit status is 0 unless --strict is given and a
resolver failed.
"""
import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parent.parent
ENV = ROOT / "config" / "versions.env"
BOM = ROOT / "sbom.cdx.json"
SBOM_MD = ROOT / "scripts" / "sbom-md.py"

# Ubuntu codename the SBOM's LLVM entries describe (26.04). A new LLVM major
# is only proposed once apt.llvm.org publishes a suite for it there.
LLVM_APT_CODENAME = "resolute"
LLVM_PACKAGES = ("clang", "clangd", "clang-format", "clang-tidy", "lld", "lldb", "llvm")

USER_AGENT = "dev-setup upstream-versions (+https://github.com/asanderson/dev-setup)"
TIMEOUT = 30


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def fetch(url: str, binary: bool = False):
    headers = {"User-Agent": USER_AGENT, "Accept": "*/*"}
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        data = resp.read()
    return data if binary else data.decode("utf-8", "replace")


def vtuple(version: str):
    """Numeric sort key for dotted versions ('v' prefix and suffixes ignored)."""
    return tuple(int(x) for x in re.findall(r"\d+", version))


def newest(versions):
    versions = list(versions)
    return max(versions, key=vtuple) if versions else None


def read_env() -> dict:
    pins = {}
    for line in ENV.read_text().splitlines():
        m = re.match(r'^([A-Z0-9_]+)="([^"]*)"\s*$', line)
        if m:
            pins[m.group(1)] = m.group(2)
    return pins


def write_env(updates: dict) -> None:
    text = ENV.read_text()
    for key, value in updates.items():
        pattern = re.compile(rf'^({re.escape(key)}=")[^"]*(")', re.M)
        text, n = pattern.subn(rf"\g<1>{value}\g<2>", text, count=1)
        if n != 1:
            raise SystemExit(f"{ENV.name}: pin {key} not found")
    ENV.write_text(text)


def github_latest_tag(repo: str) -> str:
    data = json.loads(fetch(f"https://api.github.com/repos/{repo}/releases/latest"))
    return data["tag_name"]


# --------------------------------------------------------------------------- #
# parsers (pure; exercised by --selftest)
# --------------------------------------------------------------------------- #
def parse_maven_metadata(xml: str) -> str:
    finals = [v for v in re.findall(r"<version>([^<]+)</version>", xml)
              if re.fullmatch(r"3\.\d+\.\d+", v)]
    return newest(finals)


def parse_endoflife(payload: str) -> str:
    cycles = json.loads(payload)
    return newest(c["latest"] for c in cycles if c.get("latest"))


def parse_llvm_tag(tag: str) -> str:
    m = re.fullmatch(r"llvmorg-(\d+)\.\d+\.\d+", tag)
    if not m:
        raise ValueError(f"unexpected LLVM release tag {tag!r}")
    return m.group(1)


def parse_proton_listing(html: str) -> str:
    debs = set(re.findall(r"protonvpn-stable-release_\d+(?:\.\d+)+_all\.deb", html))
    return newest(debs)


def parse_adoptium_lts(payload: str) -> str:
    return str(json.loads(payload)["most_recent_lts"])


def parse_sevenzip_tag(tag: str) -> str:
    if not re.fullmatch(r"\d+\.\d+", tag):
        raise ValueError(f"unexpected 7-Zip release tag {tag!r}")
    return tag


def parse_strata_tag(tag: str) -> str:
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError(f"unexpected Strata release tag {tag!r}")
    return tag


def strata_url(tag: str, script: str) -> str:
    return f"https://github.com/Niko1221/Strata/releases/download/{tag}/{script}"


def sevenzip_url(version: str) -> str:
    return (f"https://github.com/ip7z/7zip/releases/download/{version}/"
            f"7z{version.replace('.', '')}-linux-x64.tar.xz")


# --------------------------------------------------------------------------- #
# resolvers: each returns (latest_value, extra_env_updates)
# --------------------------------------------------------------------------- #
def resolve_maven(pins):
    xml = fetch("https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/maven-metadata.xml")
    return parse_maven_metadata(xml), {}


def resolve_elastic(pins):
    return parse_endoflife(fetch("https://endoflife.date/api/elasticsearch.json")), {}


def resolve_opensearch(pins):
    return parse_endoflife(fetch("https://endoflife.date/api/opensearch.json")), {}


def resolve_llvm(pins):
    major = parse_llvm_tag(github_latest_tag("llvm/llvm-project"))
    if vtuple(major) <= vtuple(pins["LLVM_VERSION"]):
        return pins["LLVM_VERSION"], {}
    suite = f"https://apt.llvm.org/{LLVM_APT_CODENAME}/dists/llvm-toolchain-{LLVM_APT_CODENAME}-{major}/Release"
    try:
        fetch(suite)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            # Final upstream, but no apt suite for our codename yet: stay put.
            return pins["LLVM_VERSION"], {}
        raise
    return major, {}


def resolve_k9s(pins):
    return github_latest_tag("derailed/k9s"), {}


def resolve_nvm(pins):
    return github_latest_tag("nvm-sh/nvm"), {}


def resolve_proton_vpn(pins):
    base = "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/"
    deb = parse_proton_listing(fetch(base))
    url = base + deb
    if url == pins["PROTON_VPN_RELEASE_DEB"]:
        return url, {}
    sha = hashlib.sha256(fetch(url, binary=True)).hexdigest()
    return url, {"PROTON_VPN_RELEASE_DEB_SHA256": sha}


def resolve_sevenzip(pins):
    version = parse_sevenzip_tag(github_latest_tag("ip7z/7zip"))
    if version == pins["SEVENZIP_VERSION"]:
        return version, {}
    sha = hashlib.sha256(fetch(sevenzip_url(version), binary=True)).hexdigest()
    return version, {"SEVENZIP_SHA256": sha}


def resolve_strata(pins):
    tag = parse_strata_tag(github_latest_tag("Niko1221/Strata"))
    if tag == pins["STRATA_VERSION"]:
        return tag, {}
    return tag, {
        "STRATA_INSTALL_SH_SHA256": hashlib.sha256(fetch(strata_url(tag, "install.sh"), binary=True)).hexdigest(),
        "STRATA_INSTALL_PS1_SHA256": hashlib.sha256(fetch(strata_url(tag, "install.ps1"), binary=True)).hexdigest(),
    }


def resolve_jdk(pins):
    return parse_adoptium_lts(fetch("https://api.adoptium.net/v3/info/available_releases")), {}


# key, resolver, apply (False = report only), one-line source description
PINS = [
    ("MAVEN_VERSION", resolve_maven, True, "Maven Central apache-maven metadata (newest final 3.x)"),
    ("ELASTIC_VERSION", resolve_elastic, True, "endoflife.date elasticsearch"),
    ("OPENSEARCH_VERSION", resolve_opensearch, True, "endoflife.date opensearch"),
    ("LLVM_VERSION", resolve_llvm, True, f"LLVM GitHub releases + apt.llvm.org {LLVM_APT_CODENAME} suite"),
    ("K9S_VERSION", resolve_k9s, True, "derailed/k9s GitHub releases"),
    ("NVM_VERSION", resolve_nvm, True, "nvm-sh/nvm GitHub releases"),
    ("PROTON_VPN_RELEASE_DEB", resolve_proton_vpn, True, "repo.protonvpn.com stable listing (sha256 computed)"),
    ("SEVENZIP_VERSION", resolve_sevenzip, True, "ip7z/7zip GitHub releases (sha256 computed)"),
    ("STRATA_VERSION", resolve_strata, True, "Niko1221/Strata GitHub releases (installer sha256s computed)"),
    ("JDK_MAJOR", resolve_jdk, False, "Adoptium most_recent_lts (manual: archive packaging lags)"),
]


# --------------------------------------------------------------------------- #
# SBOM sync
# --------------------------------------------------------------------------- #
def bom_component(bom: dict, name: str) -> dict:
    for c in bom["components"]:
        if c["name"] == name:
            return c
    raise SystemExit(f"sbom.cdx.json: component {name!r} not found")


def bom_set_version(comp: dict, old: str, new: str) -> None:
    comp["version"] = new
    if "purl" in comp:
        comp["purl"] = comp["purl"].replace(f"@{old}", f"@{new}", 1)


def bom_rename_ref(bom: dict, old: str, new: str) -> None:
    """Rename a component (name, bom-ref, purl tail) and every dependency ref."""
    comp = bom_component(bom, old)
    comp["name"] = new
    comp["bom-ref"] = new
    if "purl" in comp:
        comp["purl"] = comp["purl"].replace(old, new, 1)
    for dep in bom.get("dependencies", []):
        if dep["ref"] == old:
            dep["ref"] = new
        dep["dependsOn"] = [new if r == old else r for r in dep.get("dependsOn", [])]


def bom_replace_in_properties(comp: dict, old: str, new: str) -> None:
    for p in comp.get("properties", []):
        p["value"] = p["value"].replace(old, new)


def sync_sbom(changes: dict, pins: dict) -> None:
    """Mirror the env bumps into sbom.cdx.json (the file is kept alongside versions.env)."""
    bom = json.loads(BOM.read_text())
    for key, (old, new) in changes.items():
        if key == "MAVEN_VERSION":
            bom_set_version(bom_component(bom, "Apache Maven"), old, new)
        elif key == "ELASTIC_VERSION":
            for name in ("elasticsearch", "kibana"):
                bom_set_version(bom_component(bom, name), old, new)
        elif key == "OPENSEARCH_VERSION":
            for name in ("opensearchproject/opensearch", "opensearchproject/opensearch-dashboards"):
                bom_set_version(bom_component(bom, name), old, new)
        elif key == "LLVM_VERSION":
            for pkg in LLVM_PACKAGES:
                comp = bom_component(bom, f"{pkg}-{old}")
                comp["version"] = new
                bom_replace_in_properties(comp, f"-{old}", f"-{new}")
                bom_replace_in_properties(comp, f"{old}.x", f"{new}.x")
                bom_rename_ref(bom, f"{pkg}-{old}", f"{pkg}-{new}")
        elif key == "K9S_VERSION":
            bom_replace_in_properties(bom_component(bom, "k9s"), f"K9S_VERSION={old}", f"K9S_VERSION={new}")
        elif key == "PROTON_VPN_RELEASE_DEB":
            m_old = re.search(r"_(\d+(?:\.\d+)+)_all\.deb", old)
            m_new = re.search(r"_(\d+(?:\.\d+)+)_all\.deb", new)
            if m_old and m_new:
                bom_component(bom, "protonvpn-stable-release (repo bootstrap)")["version"] = m_new.group(1)
        elif key == "SEVENZIP_VERSION":
            bom_set_version(bom_component(bom, "7-Zip"), old, new)
        elif key == "STRATA_VERSION":
            bom_set_version(bom_component(bom, "Strata"), old, new)
        # NVM_VERSION: the SBOM entry records the resolution text only.
    bom["version"] = int(bom.get("version", 1)) + 1
    bom["metadata"]["timestamp"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    BOM.write_text(json.dumps(bom, indent=2))
    subprocess.run([sys.executable, str(SBOM_MD)], check=True)


def stale_mentions(changes: dict) -> dict:
    """Files outside the pin files that still spell out an old value (docs to touch by hand)."""
    skip = {ENV, BOM, ROOT / "SBOM.md"}
    hits = {}
    for key, (old, _new) in changes.items():
        if len(old) < 5:  # bare majors ('22') would match everywhere
            continue
        needle = old.rsplit("/", 1)[-1] if key == "PROTON_VPN_RELEASE_DEB" else old
        files = []
        for path in list(ROOT.glob("*.md")) + list((ROOT / "docs").rglob("*.md")) + list((ROOT / "scripts").rglob("*.sh")):
            if path in skip:
                continue
            if needle in path.read_text(errors="replace"):
                files.append(str(path.relative_to(ROOT)))
        if files:
            hits[key] = sorted(files)
    return hits


# --------------------------------------------------------------------------- #
# reporting
# --------------------------------------------------------------------------- #
def markdown_summary(rows, changes, manual, failures, stale) -> str:
    out = ["## Upstream version check", "",
           "| Pin | Pinned | Upstream | Source | Result |", "|---|---|---|---|---|"]
    for key, current, latest, source, result in rows:
        out.append(f"| `{key}` | `{current}` | `{latest}` | {source} | {result} |")
    if changes:
        out += ["", "### Bumped in this change", ""]
        for key, (old, new) in changes.items():
            out.append(f"- `{key}`: `{old}` → `{new}`")
        out += ["", "`sbom.cdx.json` (document version +1) and `SBOM.md` were regenerated to match.",
                "The nightly job only runs the lint checks; the container suites run on this PR as usual."]
    if "STRATA_VERSION" in changes:
        out += ["", "> `STRATA_INSTALL_SH_SHA256`/`STRATA_INSTALL_PS1_SHA256` were computed from the downloads; review",
                "> the new installer scripts' diff on https://github.com/Niko1221/Strata/releases before merging."]
    if "SEVENZIP_VERSION" in changes:
        out += ["", "> `SEVENZIP_SHA256` was computed from the download. Cross-check it against the digest",
                "> listed on the https://github.com/ip7z/7zip/releases release page before merging."]
    if "PROTON_VPN_RELEASE_DEB" in changes:
        out += ["", "> `PROTON_VPN_RELEASE_DEB_SHA256` was computed from the download. Cross-check it against the",
                "> checksum on https://protonvpn.com/support/official-linux-vpn-ubuntu/ before merging."]
    if manual:
        out += ["", "### Needs a manual decision", ""]
        for key, current, latest, why in manual:
            out.append(f"- `{key}`: pinned `{current}`, upstream `{latest}` — {why}")
    if stale:
        out += ["", "### Old values still mentioned elsewhere", ""]
        for key, files in stale.items():
            out.append(f"- `{key}` ({changes[key][0]}): " + ", ".join(f"`{f}`" for f in files))
    if failures:
        out += ["", "### Could not resolve", ""]
        for key, err in failures:
            out.append(f"- `{key}`: {err}")
    return "\n".join(out) + "\n"


def selftest() -> int:
    maven_xml = "<versions><version>3.9.16</version><version>3.10.0</version><version>3.10.1-rc-1</version><version>4.0.0-rc-7</version></versions>"
    assert parse_maven_metadata(maven_xml) == "3.10.0"
    eol = json.dumps([{"cycle": "9.5", "latest": "9.5.1"}, {"cycle": "9.4", "latest": "9.4.3"}, {"cycle": "8.19", "latest": "8.19.2"}])
    assert parse_endoflife(eol) == "9.5.1"
    assert parse_llvm_tag("llvmorg-23.1.0") == "23"
    try:
        parse_llvm_tag("llvmorg-23.1.0-rc2")
        raise AssertionError("rc tag accepted")
    except ValueError:
        pass
    listing = '<a href="protonvpn-stable-release_1.0.8_all.deb">x</a> <a href="protonvpn-stable-release_1.0.10_all.deb">y</a> <a href="protonvpn-stable-release_1.0.9_all.deb">z</a>'
    assert parse_proton_listing(listing) == "protonvpn-stable-release_1.0.10_all.deb"
    assert parse_adoptium_lts('{"most_recent_lts": 25}') == "25"
    assert parse_sevenzip_tag("26.05") == "26.05"
    assert parse_strata_tag("v0.2.6") == "v0.2.6"
    assert strata_url("v0.2.6", "install.sh").endswith("/releases/download/v0.2.6/install.sh")
    try:
        parse_strata_tag("v0.3.0-rc1")
        raise AssertionError("pre-release Strata tag accepted")
    except ValueError:
        pass
    assert sevenzip_url("26.05").endswith("/26.05/7z2605-linux-x64.tar.xz")
    try:
        parse_sevenzip_tag("26.05-beta")
        raise AssertionError("pre-release 7-Zip tag accepted")
    except ValueError:
        pass
    assert newest(["v0.50.18", "v0.50.9", "v0.49.99"]) == "v0.50.18"
    # SBOM rename keeps dependency refs consistent.
    bom = {"components": [{"name": "clang-22", "bom-ref": "clang-22", "purl": "pkg:deb/llvm/clang-22",
                           "properties": [{"name": "resolution", "value": "newest 22.x in the llvm-toolchain-resolute-22 suite"}]}],
           "dependencies": [{"ref": "root", "dependsOn": ["clang-22"]}, {"ref": "clang-22", "dependsOn": []}]}
    comp = bom_component(bom, "clang-22")
    bom_replace_in_properties(comp, "-22", "-23")
    bom_replace_in_properties(comp, "22.x", "23.x")
    bom_rename_ref(bom, "clang-22", "clang-23")
    assert bom["components"][0] == {"name": "clang-23", "bom-ref": "clang-23", "purl": "pkg:deb/llvm/clang-23",
                                    "properties": [{"name": "resolution", "value": "newest 23.x in the llvm-toolchain-resolute-23 suite"}]}
    assert bom["dependencies"] == [{"ref": "root", "dependsOn": ["clang-23"]}, {"ref": "clang-23", "dependsOn": []}]
    # The live pin file parses and every PIN key exists in it.
    pins = read_env()
    missing = [k for k, *_ in PINS if k not in pins]
    assert not missing, f"pins missing from versions.env: {missing}"
    print("selftest: OK")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="rewrite the pin files when upstream moved")
    ap.add_argument("--summary", metavar="FILE", help="write a Markdown summary here")
    ap.add_argument("--github-output", action="store_true", help="append changed=/manual= to $GITHUB_OUTPUT")
    ap.add_argument("--strict", action="store_true", help="exit 1 if any resolver failed")
    ap.add_argument("--selftest", action="store_true", help="offline parser checks")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    pins = read_env()
    rows, changes, manual, failures, env_updates = [], {}, [], [], {}
    for key, resolver, apply, source in PINS:
        current = pins[key]
        try:
            latest, extra = resolver(pins)
        except Exception as exc:  # noqa: BLE001 - every resolver failure is reported, never fatal
            failures.append((key, f"{type(exc).__name__}: {exc}"))
            rows.append((key, current, "?", source, "unresolved"))
            continue
        if latest == current:
            rows.append((key, current, latest, source, "current"))
        elif vtuple(latest) < vtuple(current) and key != "PROTON_VPN_RELEASE_DEB":
            rows.append((key, current, latest, source, "pin is newer (kept)"))
        elif not apply:
            manual.append((key, current, latest, "report-only pin; bump by hand"))
            rows.append((key, current, latest, source, "manual"))
        else:
            changes[key] = (current, latest)
            env_updates[key] = latest
            env_updates.update(extra)
            rows.append((key, current, latest, source, "bump"))

    stale = stale_mentions(changes) if changes else {}
    if args.apply and changes:
        write_env(env_updates)
        sync_sbom(changes, pins)

    width = max(len(k) for k, *_ in PINS)
    for key, current, latest, _source, result in rows:
        print(f"{key:<{width}}  {current:<40} -> {latest:<40} {result}")
    for key, err in failures:
        print(f"!! {key}: {err}", file=sys.stderr)
    if args.summary:
        pathlib.Path(args.summary).write_text(markdown_summary(rows, changes, manual, failures, stale))
    if args.github_output and os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as fh:
            fh.write(f"changed={'true' if changes else 'false'}\n")
            fh.write(f"manual={'true' if manual else 'false'}\n")
    return 1 if (args.strict and failures) else 0


if __name__ == "__main__":
    sys.exit(main())
