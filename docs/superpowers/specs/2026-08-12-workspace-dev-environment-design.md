# WorkSpace Development Environment — Design

**Date:** 2026-08-12
**Status:** Approved (pending user review of this document)
**Scope:** Phase 1 of the AWS contract-development environment: the AWS WorkSpace virtual desktop with a full development toolkit, plus the minimal foundation infrastructure it requires. The application platform (EC2 app host, Bedrock integration, OpenSearch Serverless) is a documented future phase and is explicitly out of scope here.

## 1. Context and goals

A solo contract software developer needs a cloud-hosted development desktop, reachable from a locked-down client-site workstation (outbound HTTPS only, no inbound VPN) and from personal laptops. Usage is intermittent (~20–100 active hours/month), so every component must idle cheaply. Client IP confidentiality applies; all volumes are encrypted.

The broader environment (Bedrock LLM inference, RAG services, OpenSearch vector store, EC2 app host) was designed through prior research and is deferred. This spec delivers the first working slice: a WorkSpace a developer can log into and immediately use for real work, provisioned by Terraform, with tooling installed by a versioned bootstrap script.

**Success criteria:**
1. `terraform apply` (foundation, then desktop) produces a running Ubuntu WorkSpace with no manual console steps.
2. The WorkSpace is reachable from a personal laptop and from the client-site workstation (native client or web client).
3. `setup.sh` installs the complete toolkit; `setup.sh --check` reports all tools green.
4. The WorkSpace auto-stops after 60 minutes idle, and billing reflects AutoStop behavior.
5. Monthly cost for this slice lands in the ~$89–142 range at 20–100 hrs/month.

## 2. Repository layout

Repo: `/Users/bossman/work/aws-dev` (GitHub-style layout, single repo).

```
aws-dev/
├── README.md
├── docs/superpowers/specs/          # design docs (this file)
├── foundation/                      # Terraform stack 1 (built now)
├── platform/                        # Terraform stack 2 (future phase, empty placeholder + README)
├── desktop/                         # Terraform stack 3 (built now)
└── workspace/
    └── setup.sh                     # idempotent dev-toolkit bootstrap script
```

Three-stack layering was chosen over a single root module (user decision) so the slow, stateful desktop resources (Simple AD: 20–40 minute create) and the future churny platform resources live in separate blast radii with separate state files. Stacks are wired with `terraform_remote_state` data sources against the shared S3 backend.

## 3. Terraform stacks

### 3.1 `foundation/` (built now)

| Resource | Detail |
|---|---|
| VPC | `10.0.0.0/16` |
| Subnets | Two public subnets in two AZs (WorkSpaces directory registration requires two subnets in distinct AZs) |
| Internet Gateway + routes | Standard |
| State backend bootstrap | S3 bucket (versioned, encrypted) + DynamoDB lock table |
| KMS key | Shared CMK for WorkSpace volumes and future EBS/S3/OpenSearch |
| Budget alarm | AWS Budgets, $400/month threshold, email notification |
| Cost anomaly monitor | Account-level, default sensitivity |
| Guardrail policies | IAM policy denying `bedrock:CreateProvisionedModelThroughput`; retained now (cheap) to protect future phases |
| AWS Config rules | `restricted-ssh`, `restricted-common-ports` (drift alarm for future public-subnet EC2 host, per approved network decision) |

### 3.2 `desktop/` (built now)

| Resource | Detail |
|---|---|
| Simple AD | Size Small, deployed across the two subnets. ~$0.036/domain-controller-hour ≈ $52/month for the 2 DCs, 24/7, cannot be stopped. **Rate is medium-confidence — verify against the AWS Directory Service pricing page at apply time.** |
| WorkSpaces directory registration | Registers the Simple AD directory with WorkSpaces |
| WorkSpace | One, Ubuntu **Power** bundle (4 vCPU / 16 GB, 175 GB root / 100 GB user), running mode `AUTO_STOP`, timeout 60 minutes, both volumes encrypted with the foundation KMS key |
| Directory user | One named user in Simple AD for the developer |

Verified pricing (AWS Price List API, us-east-1, pulled 2026-08-12): Ubuntu Power AutoStop = **$19/month base + $0.66/hour** → ~$32–85/month at 20–100 hrs. (Windows Power is price-equivalent at $19 + $0.64/hr; Ubuntu chosen for toolchain fit, not cost. License-included Windows would not remove the Simple AD requirement — only Windows 10/11 BYOL unlocks the Entra ID path, which is impractical for a solo operator.)

### 3.3 `platform/` (future phase — placeholder only)

Empty directory with a README pointing at the prior research conclusions: EC2 `m7g.large` app host (public subnet + hardening pack, per approved decision), Amazon Bedrock on-demand inference, OpenSearch Serverless NextGen collection, EventBridge + Lambda auto-stop scheduler, EBS/S3 storage. Not built in this phase.

## 4. Bootstrap script — `workspace/setup.sh`

Idempotent Bash script, run in a terminal on the WorkSpace after first login; safe to re-run at any time to upgrade. Each tool section is guarded: detect current version → install if absent → upgrade if outdated → skip if current. WorkSpaces provides no EC2-style user-data, so first run is manual by design.

**Flags:** `--check` = report-only (table of tool → installed version → status, no changes). Default run ends with the same version table.

**Version policy:** install latest available at run time. No pins except JDK, which tracks the latest LTS major (currently Temurin) to avoid surprise major-version breaks in client projects.

| # | Tool | Install method |
|---|---|---|
| 1 | git + build-essential + curl/unzip | apt |
| 2 | Brave browser | official Brave apt repository + signing key |
| 3 | Proton VPN | official Proton deb repository. **Caveat documented in-script:** a full-tunnel VPN captures the WorkSpaces streaming traffic and will drop the session. Use Proton's split-tunneling to exclude the WorkSpaces streaming gateway ranges, or accept disconnection while the VPN is up. |
| 4 | Python 3 | apt (system interpreter); project interpreters managed by uv |
| 5 | uv | official install script (astral.sh) |
| 6 | nvm | official install script; then `nvm install --lts` |
| 7 | Node.js (latest LTS) | via nvm |
| 8 | Claude Code | native installer script |
| 9 | JDK (latest LTS, Temurin) | Adoptium apt repository |
| 10 | Maven | apt |
| 11 | AWS CLI v2 | AWS official zip installer |
| 12 | Terraform | HashiCorp apt repository |

WorkSpaces Ubuntu bundles are x86_64; every listed tool has a first-party x86_64 Ubuntu distribution. No ARM concerns in this phase.

## 5. Access and data flow

- Developer → WorkSpaces native client (personal laptops) or **WorkSpaces web client** (fallback for the client site if the native client's streaming ports are blocked). All connections outbound from the user's network.
- Terraform for future phases runs *from* the WorkSpace against AWS APIs — no SSM, no inbound ports needed in this phase.
- **Untested assumption, carried from prior analysis:** client-site egress permits the WorkSpaces streaming protocol or, failing that, the web client over 443. First connection from the client site is the real test (success criterion 2). If both fail, the access design must be revisited before the platform phase builds on it.

## 6. Failure handling

| Failure | Response |
|---|---|
| Simple AD create fails or wedges | `terraform taint` + re-apply. 20–40 min operation, isolated in the `desktop` stack so nothing else re-plans. |
| WorkSpace unhealthy | Rebuild via CLI/console. Root volume is restored to bundle state; user volume persists through rebuild. Nothing irreplaceable lives on the root volume; the toolkit is one `setup.sh` re-run away. |
| `setup.sh` fails mid-run | Re-run; idempotent guards make partial installs safe. |
| Directory deregistered by AWS after 30 days with zero WorkSpaces | Not applicable while the WorkSpace exists; noted as a hazard if the WorkSpace is ever deleted but the directory kept. |
| Budget alarm fires | Investigate via Cost Explorer; the two 24/7 items (Simple AD, WorkSpace base fee) are fixed, so anomalies point at usage-hour overruns. |

## 7. Testing and verification

1. `terraform fmt -check`, `terraform validate`, and a clean `terraform plan` on both stacks.
2. Post-apply: WorkSpace status `AVAILABLE`; login succeeds from a personal laptop.
3. Login succeeds from the client-site workstation (native client, else web client). **This is the highest-value test in the phase.**
4. `setup.sh` full run completes; `setup.sh --check` reports all 12 tools green; spot-check `terraform version`, `aws --version`, `node --version`, `claude --version`.
5. AutoStop: leave idle >60 min, confirm state transitions to `STOPPED` and hourly metering ceases (billing console check next day).
6. Budget alarm: temporarily lower threshold to force a test notification, then restore.

## 8. Cost summary (this slice)

| Item | Monthly |
|---|---|
| Simple AD Small (24/7, unstoppable) | ~$52 *(verify at apply)* |
| WorkSpace Ubuntu Power AutoStop | $19 base + $0.66/hr → $32–85 |
| Foundation misc (state bucket, Config rules, KMS) | ~$5 |
| **Total** | **~$89–142** |

Future phases add Bedrock usage, the EC2 app host, OpenSearch Serverless, and storage per the prior research (~$104–308/month full-environment estimate, revised upward by the Simple AD and corrected WorkSpace base-fee findings to ~$168–372).

## 9. Risks and open items

1. **Client-site connectivity untested** — success criterion 2; test immediately after first apply.
2. **Simple AD price is medium-confidence** (~$52/mo figure from secondary source; AWS's own pricing table did not render during research).
3. **Proton VPN vs. streaming session** — split-tunnel configuration is the developer's runtime responsibility; the script installs but does not configure the VPN.
4. **Simple AD is a hard 24/7 floor** — it roughly matches the WorkSpace itself in cost. If AWS ships directory-less Linux WorkSpaces or the user later moves to Windows BYOL + Entra ID, revisit.
5. **`setup.sh` trusts vendor install scripts** (uv, nvm, Claude Code) fetched over HTTPS at run time. Acceptable for a dev desktop; pin/checksum if client policy demands.

## 10. Future phases (documented, not designed here)

Platform stack (EC2 app host + Bedrock + OpenSearch Serverless NextGen + auto-stop scheduler), per the approved three-stack architecture and prior verified research. The platform design sections already approved in brainstorming (public subnet + hardening pack, EventBridge scheduler, data flow) carry forward as the starting point for that phase's spec.
