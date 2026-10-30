# Commerce AWS — learn to build, deliver and operate an AWS application

This is one application in one AWS **learning** environment. It reuses the Commerce
app so that your work focuses on infrastructure and operations. It does not depend
on your laptop Kubernetes cluster or the previous six-repository delivery system.

**Status snapshot, 30 October 2026:** The retained foundation exists: the private
state bucket, four empty ECR repositories, budget, GitHub OIDC provider, publisher
and planning identities, and the MFA bootstrap identity. Their configuration is
tracked in Terraform. The release App's authentication test passed. A read-only
session plan was generated; **the EKS session, database, application and monitoring
have not been deployed**. The apply identity is not yet provisioned or verified.
GitHub variables `DELIVERY_ENABLED=false` and `INFRA_ENABLED=false` keep cloud jobs disabled.
`deploy/environment.yaml` also starts disabled. Do not claim the AWS end-to-end
deployment has passed until you have performed the activation exercises below.

Read this guide in order for the first build: architecture and costs; identity and
bootstrap; GitHub setup; session creation; platform and release; operations and
cleanup. The reference chapters after the runbook explain each code file and trace
requests, credentials, deployment, recovery and troubleshooting. Examples use
placeholders; replace them locally and never paste secrets or MFA codes into chat.
This status is a snapshot, not proof of the current AWS bill or resource inventory.

## What you will learn

| Service/tool | Its actual responsibility here |
|---|---|
| VPC, subnets, routing, security groups | Public worker/ALB subnets, isolated database subnets, PostgreSQL access from nodes only |
| IAM, STS, GitHub OIDC | Human operator identity and short-lived workflow credentials |
| EKS, EC2 managed node group | Kubernetes control plane and one replaceable worker |
| ECR | Private, immutable application images and signed release evidence |
| EBS | Encrypted gp3 volumes for Redis and monitoring |
| RDS PostgreSQL | Private encrypted database, automated backups and manual restore exercises |
| SQS and dead-letter queue | Asynchronous order receipts, retries, duplicate handling and failed-message recovery |
| Secrets Manager and EKS Pod Identity | Scoped AWS workload identities; secrets never committed to Git |
| S3 | Versioned encrypted Terraform state, state locks and private saved plans |
| ALB and ACM | Public HTTPS endpoint and HTTP-to-HTTPS redirect |
| DNS / Route 53 | Point a domain you own to the ALB; existing external DNS is also fine |
| CloudWatch, SNS, KMS, Budgets | EKS audit logs, encrypted queue-alarm notifications, key policy and spending visibility |
| GitHub Actions | PR checks, parallel affected-image builds, signed publication, infrastructure plan/apply |
| Helm and Argo CD | Reconcile the reviewed deployment manifest into EKS |
| Prometheus, Grafana, Alertmanager, Slack | Kubernetes/application metrics, dashboards, actionable alerts and resolutions |
| CloudTrail event history | Investigate who performed AWS management operations |

We intentionally leave out service mesh, multiple accounts/clusters, multi-region,
multi-AZ data availability, Karpenter, complex progressive delivery and additional
databases. Learn reliable deployment and recovery before introducing those tools.

## Understand the traffic

```mermaid
flowchart LR
    Customer --> DNS[DNS name]
    DNS --> ALB[ALB HTTPS / ACM]
    ALB --> Frontend[Node frontend]
    Frontend --> Catalogue[Go catalogue]
    Frontend --> Cart[Python cart]
    Frontend --> Orders[Java orders API]
    Catalogue --> Orders
    Cart --> Redis[Redis + EBS]
    Orders --> RDS[Private RDS PostgreSQL]
    Publisher[Java outbox publisher] --> RDS
    Publisher --> SQS[SQS order-paid]
    SQS --> Worker[Java receipt worker]
    Worker --> RDS
    SQS --> DLQ[Dead-letter queue]
```

Four application images run six processes. Orders, publisher and worker share the
same Java image with different `DELIVERY_ROLE` settings. The API writes an order
and outbox event in one database transaction. The publisher sends that event to
SQS; the worker records a receipt and acknowledges only after committing. The
inbox prevents a duplicate message from creating duplicate business effects.

The app contains accounts, administration, inventory, orders, refunds and an INR
storefront. Razorpay is **test mode only** and is not configured automatically in
AWS. Checkout needs test credentials before the payment exercise can pass. Do not
enable the local fake-payment mode on an internet-facing deployment.

## Repository map

```text
application/              Existing frontend, catalogue, orders and cart source/tests/Dockerfiles
infrastructure/bootstrap/ Retained S3 state bucket, ECR, publisher OIDC role and budget
infrastructure/session/   Destroyable VPC, EKS, RDS, queues, secrets and alarms
deploy/chart/             One small Helm application chart
deploy/platform/          Pinned platform versions, storage and Helm values
deploy/environment.yaml   Reviewed AWS environment settings; initially disabled
deploy/release.json       Four reviewed immutable image references
deploy/argocd.yaml        AppProject and the one application
.github/workflows/ci.yml  PR checks, required gate and release proposal
.github/workflows/image.yml Reusable affected-component build and publication
.github/workflows/infrastructure.yml Manual saved-plan apply/destroy
scripts/                  Small, documented automation helpers
tests/                    Delivery boundary tests
```

`application/SOURCES.md` records the reviewed source commits. Existing repositories
have not been deleted or replaced. Keep them until this project works independently.
Changes to the source repositories do **not** automatically appear in this snapshot.

## Cost choices and their tradeoffs

The default session uses one `t3.large` x86 worker and one `db.t4g.micro` RDS
instance. Check current regional prices before applying; these defaults are a
capacity starting point, not a cost estimate. The control plane, worker, public
IPv4, RDS, ALB/LCUs, EBS, logs, secrets, images, snapshots, DNS and data transfer can
all contribute to the bill. The alarm-notification KMS key and requests also have
charges. CPU credits can also matter for burstable instances.

* EKS requires two AZ subnets. Only the first AZ has a worker and database instance.
* The worker has a public IP but no SSH rule or internet-open application NodePort.
  ALB targets pod IPs. RDS is private. This avoids NAT Gateway charges; a hardened
  continuously running production system would normally use private workers.
* One worker is not highly available. Pod rescheduling does not survive an AZ loss.
  HPA can add frontend/catalogue pods but **does not add EC2 nodes**. The node group
  allows up to two nodes for manual scaling; no Cluster Autoscaler is installed.
* Monitoring keeps six hours of metrics and EKS audit logs keep three days. There
  is no central application-log archive in this first version; use `kubectl logs`.
* Redis uses encrypted EBS instead of a separate ElastiCache service. Cart data can
  be lost during session teardown. Orders and accounts belong in RDS.
* A single-replica deployment has no PDB: a `minAvailable: 1` PDB would prevent
  draining the only replica. Add replicas and a PDB during the availability exercise.
* Budgets send delayed notifications; they **do not stop charges**. Teardown is an
  explicit action. Closing the browser, stopping the laptop or scaling workers to
  zero does not delete the paid EKS control plane.
* Bootstrap resources are retained. Images, S3 state and retained RDS snapshots can
  cost money after a session is destroyed. Audit these at the end of each session.

A ₹1,000 target requires short, planned sessions and a current regional estimate.
This repository makes no guarantee that a fixed number of sessions fits that sum.

The agreed region is Mumbai (`ap-south-1`) and the monthly target is ₹1,000.
Before creating anything, inventory the selected account and review current Billing,
including existing resources in other regions. The default account-wide warning
threshold is a conservative USD 8, with alerts at 50%/80% actual and 100% forecast.
Taxes count; credits/refunds do not mask gross usage. Check the actual INR conversion
and invoice taxes before setting this threshold. No USD threshold guarantees an INR cap.

## Account inventory and ownership tracking

Terraform tracks directly managed resources. Kubernetes controllers own additional
resources: the managed node group creates EC2 instances, root disks and interfaces;
EBS CSI provisions PVC disks; the load-balancer controller creates ALBs, target
groups and security groups. Project tags are explicitly applied to these paths;
Terraform provider tags alone do not propagate to every child resource.

Take a baseline after secure login and another inventory after each session:

```bash
python3 scripts/inventory.py --profile commerce-learning --account YOUR_12_DIGIT_ACCOUNT_ID
```

This helper only lists/describes resources, verifies the expected account before
querying them, includes untagged/pre-existing resources and writes a private,
timestamped JSON report under gitignored `.work/inventory/`. A permission failure
makes the report incomplete and exits nonzero; it does not mean resources are absent.
It never retrieves secret values, creates resources or deletes resources. Keep the
baseline to distinguish this project from existing work; never delete unrelated
resources simply because they appear in the report. It covers the main Mumbai
services plus global S3 bucket and Route 53 zone names, not every AWS service/region or a billing audit.

Tagging is ownership evidence, not proof of zero charges. After teardown compare
inventories, inspect service-owned remnants and retained resources, then review
Billing after its reporting delay. A default VPC or unrelated existing resource
must not be destroyed as part of this project's cleanup.

## Security and review boundaries

Use a dedicated learning AWS account if available, MFA on the root account and an
SSO/assumable role for normal work. Never create root access keys. Do not put AWS
access keys, GitHub App private keys, Slack URLs or payment keys into this repo/chat.

Main requires a successful `Required checks` gate and a CODEOWNER review by
`Narx-Space-Prod/code-reviewers` (Code-S-12). Administrators are covered, stale
reviews are dismissed, last-push approval is required, and force pushes/deletions
are blocked. The developer cannot approve their own change. Initial repository
creation only seeds README on main; the implementation arrives by PR.

PR code gets a read-only GitHub token and no AWS credentials. Publication runs only
on main in `registry-release`, using an OIDC role trusted for that exact repository
and GitHub environment. Infrastructure uses separate plan and apply roles, and
`infrastructure-apply` requires a human reviewer. Protect all cloud environments
with main-only deployment branch policies before enabling the workflows.

Application workloads run as non-root, drop Linux capabilities, use read-only root
filesystems, resource requests/limits and startup/readiness/liveness probes. The
commerce namespace enforces restricted Pod Security. EKS VPC CNI network-policy
support is enabled. Policies isolate the namespace and limit external egress to
DNS, HTTPS, PostgreSQL and the Pod Identity endpoint. They are intentionally a
namespace boundary, not a separate least-privilege policy for every service pair.

Node IMDS requires v2 with hop limit one. Publisher can only send to its queue;
worker can only consume/delete/change visibility on that queue. External Secrets
can read only the two provisioned Secrets Manager ARNs. PostgreSQL connections
verify the RDS TLS certificate and hostname. A sync Job creates a limited login
for the application; regular workloads never receive the RDS master password.
The TLS CA bundle is public trust material, not a private key.

Pod Identity trust also requires the documented `eks-cluster-arn` request tag to
match this exact account/region/cluster. Keep session tags enabled on associations.

Terraform state contains generated secrets. S3 is private, encrypted, versioned and
TLS-only. Backend locks use S3 lockfiles. Saved infrastructure plans contain secrets
too: the workflow stores them privately in S3, passes their object version/checksum
between jobs and expires plan objects after one day. They are not GitHub artifacts.
Review/apply on the same day; an expired/stale plan must be regenerated.

The state backend uses SSE-S3; EKS 1.35 provides default API-data envelope encryption
with an AWS-owned key. Alarm notifications use a session KMS key with a specific
CloudWatch service grant. Four path-specific IaC scan exceptions in
`.trivyignore.yaml` document the learning networking choices and these encryption
decisions; they expire on 2027-01-30. Other HIGH/CRITICAL infrastructure findings
block CI. Exceptions must be reviewed rather than renewed automatically.

Images are signed, and SBOMs are attested. The initial chart does not install an
image-signature admission controller. Reviewers must verify candidate signatures
as described below. A digest-shaped reference alone does not prove a signature.
The first AWS exercise must validate actual IAM, CRD admission and network-policy
behaviour; offline renders are not proof that a cloud deployment works.

## 1. Validate without spending on AWS

Use a fresh clone or separate worktree for the following backend-disabled checks;
do not reinitialize an operational state-connected checkout with `-backend=false`.
Tools: Git, GitHub CLI, Docker/BuildKit, Python 3, Terraform 1.16.0, Helm 3.22.0,
kubectl compatible with Kubernetes 1.35, AWS CLI v2 and jq. On headless Linux use
SSH port forwarding for private administrative UIs. Tool downloads used in CI are
version-pinned and checksum checked by `scripts/tools.sh`.

```bash
git clone https://github.com/Narx-Space-Prod/commerce-aws.git
cd commerce-aws
python3 -m venv .venv
. .venv/bin/activate
pip install PyYAML==6.0.3
bash scripts/tools.sh helm kubeconform actionlint gitleaks
export PATH="$PWD/.work/bin:$PATH"
python3 -m unittest discover -s tests -v
python3 scripts/check_chart.py
actionlint
terraform fmt -check -recursive infrastructure
for root in bootstrap session; do
  terraform -chdir="infrastructure/$root" init -backend=false -lockfile=readonly
  terraform -chdir="infrastructure/$root" validate
  terraform -chdir="infrastructure/$root" test
done
```

Tests use mocked AWS providers, not your account. Helm renders validation-only dummy
digests in a temporary directory, never in `deploy/release.json`. Core Kubernetes
objects get strict schema checks. Operator custom resources are rendered and
structurally checked; real CRD admission still needs the EKS exercise.

Each Dockerfile runs its own component tests before producing a runtime image:

```bash
docker build -t commerce/frontend:check application/frontend
docker build -t commerce/catalogue:check application/catalogue
docker build -t commerce/orders:check application/orders
docker build -t commerce/cart:check application/orders/cart
```

Do not run all four builds simultaneously on a small laptop. GitHub-hosted runners
build affected components in parallel, with independent caches. A cart-only change
does not rebuild Java. Deployment/docs/inventory-only changes do not rebuild images.
Workflow changes and the shared build/release/tool scripts revalidate all images;
platform installation and inventory helpers do not invalidate application layers.

## 2. Review AWS access, budget and retained bootstrap

Before spending, verify the account, agreed Mumbai region (`ap-south-1`), session
duration and current cost estimate. If IAM Identity Center is already configured,
you can use the SSO commands below. For this project's standalone account, use the
non-root console-login path after the example; do not create an organization just
to follow an SSO example.

```bash
aws configure sso --profile commerce-sso-example
aws sso login --profile commerce-sso-example
export AWS_PROFILE=commerce-sso-example
aws sts get-caller-identity
aws ec2 describe-availability-zones --region ap-south-1
aws iam list-open-id-connect-providers
```

For this account, initial access uses the non-root `commerce-operator` IAM user with
MFA and `aws login --remote --profile commerce-learning --region ap-south-1`.
The user belongs to the read-only `commerce-observers` group with
`ReadOnlyAccess` and `SignInLocalDevelopmentAccess`; no permanent access keys are
needed. Use existing Identity Center if already available. Creating/joining an AWS
Organization can expire Free Tier credits; do not enable an organization as an
incidental login setup step. A direct paid-plan upgrade has different credit rules;
review that separately only if a required service actually needs it.

### Scoped access for the first foundation apply

Read-only access can inventory and plan; it cannot create the budget, state bucket,
registry or publisher role. `bootstrap/access.tf` defines an optional human setup
role named `commerce-aws-bootstrap`. It trusts one exact IAM user, requires MFA and
limits sessions to one hour. Its writes cover only the named state bucket, four
ECR repositories, the `commerce-aws` budget, GitHub OIDC and the bounded publisher
role. It cannot create EKS/EC2/RDS, modify its own access, or rewrite/remove the
publisher boundary. The observer group's permissions stay read-only.

There is a one-time identity bootstrap: root creates four **IAM-only** objects
from the reviewed definitions, which are then imported into Terraform. Root is
needed because the observer cannot grant itself permissions. These objects must
be tracked before applying the chargeable foundation; they are not an unrecorded
exception to infrastructure ownership. No `AdministratorAccess` policy is used.

1. Set `bootstrap_user_arn` in your private bootstrap variables to the exact
   non-root user ARN verified with STS. Generate a **plan**, not an apply. The
   `bootstrap_access_documents` planned output contains the trust JSON, write JSON,
   publisher boundary JSON and exact names/descriptions/tags. These documents have
   account identifiers but no credentials. Keep the full plan private: it also
   includes notification contact details.
2. In the root console, create customer-managed policy
   `commerce-aws-publisher-boundary` from the exported boundary JSON, using its
   exported description and tags. This caps the publisher at its four ECR repos.
3. Create role `commerce-aws-bootstrap` using **Custom trust policy** and the
   exported trust JSON. Attach AWS-managed `ReadOnlyAccess`; use the exported role
   description/tags and a maximum session of one hour.
4. On that role, create inline policy `bootstrap-resources` from the exported
   write JSON. Root owns these access controls; the scoped role cannot change them.
5. Sign back in as the IAM user. Configure profile `commerce-bootstrap` with
   `role_arn=arn:aws:iam::ACCOUNT:role/commerce-aws-bootstrap`,
   `source_profile=commerce-learning`, `mfa_serial=YOUR_MFA_DEVICE_ARN`,
   `duration_seconds=3600` and `region=ap-south-1`. In your own terminal, run
   `aws sts get-caller-identity --profile commerce-bootstrap` and enter the MFA code
   there. Never paste a code or exported credentials into chat.
6. For Terraform, use a separate `commerce-bootstrap-tf` process-credentials profile:
   `credential_process = /ABSOLUTE/PATH/TO/aws configure export-credentials --profile commerce-bootstrap --format process`.
   The CLI retrieves the cached role session for the SDK without printing secrets
   into a shell log. Authenticate the CLI interactively first; an expired role
   session needs a fresh MFA login. Do not run the export command directly in chat.

For a brand-new account, the S3 backend bucket does not exist yet. Temporarily move
the backend declaration aside and initialize local state before the imports. Restore
it after the first foundation apply, then migrate the state as described below.

```bash
mkdir -p .work
mv infrastructure/bootstrap/backend.tf .work/bootstrap-backend.tf
terraform -chdir=infrastructure/bootstrap init
```

With `AWS_PROFILE=commerce-bootstrap-tf`, import the four pre-created objects:

```bash
# Pass your private bootstrap -var-file to each import command if it isn't terraform.tfvars.
terraform -chdir=infrastructure/bootstrap import 'aws_iam_policy.publisher_boundary[0]' \
  'arn:aws:iam::ACCOUNT:policy/commerce-aws-publisher-boundary'
terraform -chdir=infrastructure/bootstrap import 'aws_iam_role.bootstrap[0]' commerce-aws-bootstrap
terraform -chdir=infrastructure/bootstrap import 'aws_iam_role_policy_attachment.bootstrap_read[0]' \
  'commerce-aws-bootstrap/arn:aws:iam::aws:policy/ReadOnlyAccess'
terraform -chdir=infrastructure/bootstrap import 'aws_iam_role_policy.bootstrap_write[0]' \
  'commerce-aws-bootstrap:bootstrap-resources'
```

Re-plan after import. Stop if Terraform proposes modifying the protected access
objects: root must reconcile the reviewed JSON, descriptions and tags first.
Only the expected foundation creations should remain. Keep this role restricted
to foundation maintenance; separate reviewed OIDC roles will provision the session.
Authentication/MFA and real IAM sufficiency must be checked in AWS before apply;
mocked policy tests cannot establish live permission behaviour.

Primary access references: [custom role creation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-custom.html),
[same-account trusted principals](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_principal.html),
[role profiles](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html),
[Free Tier upgrade and Organizations rules](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-FAQ.html).

Copy the bootstrap example, edit its account/region/email/bucket, and reuse any
existing GitHub OIDC provider in this account. The local file is gitignored.

```bash
cp infrastructure/bootstrap/bootstrap.example.tfvars infrastructure/bootstrap/terraform.tfvars
terraform -chdir=infrastructure/bootstrap plan -out=bootstrap.tfplan
terraform -chdir=infrastructure/bootstrap apply bootstrap.tfplan
terraform -chdir=infrastructure/bootstrap output
```

The bootstrap root starts with **local sensitive state**. Restore the reviewed
backend declaration moved aside above, then migrate state to the new bucket:

```bash
mv .work/bootstrap-backend.tf infrastructure/bootstrap/backend.tf
terraform -chdir=infrastructure/bootstrap init -migrate-state \
  -backend-config='bucket=YOUR_STATE_BUCKET' \
  -backend-config='key=bootstrap/terraform.tfstate' \
  -backend-config='region=ap-south-1' \
  -backend-config='encrypt=true' -backend-config='use_lockfile=true'
```

Keep an encrypted backup until migration is verified, then remove local state copies
securely. Backend details are supplied at initialization; do not commit credentials.
This one-time migration is deliberate; Terraform cannot create its own backend
before that bucket exists. Do not repeatedly create new state buckets.

Check the budget in AWS Billing before starting the session. Review its recipients.
The bucket and ECR repositories have `prevent_destroy`; session teardown does not
delete them. Do not disable those guards to fix an unrelated Terraform error.

## 3. Configure GitHub before enabling cloud workflows

Repository variables:

| Variable | Value |
|---|---|
| AWS_ACCOUNT_ID / AWS_REGION | Reviewed account and region |
| TF_STATE_BUCKET | Retained bucket name |
| AWS_RELEASE_ROLE_ARN | Bootstrap `release_role_arn` output |
| AWS_PLAN_ROLE_ARN / AWS_APPLY_ROLE_ARN | Dedicated infrastructure OIDC roles provisioned/reviewed for this account |
| RELEASE_APP_ID | Dedicated release GitHub App ID |
| DELIVERY_ENABLED / INFRA_ENABLED | Keep `false` until the respective activation checks pass |

Secrets:

* `RELEASE_APP_PRIVATE_KEY`: enter directly in the **release-proposal environment's
  Secrets**, not repository-wide secrets. Main-only environment protection prevents
  a developer's same-repository PR workflow from accessing the signing key. The App is installed
  only on this repository, with Contents read/write, Pull requests read/write,
  Metadata read. No Actions write, Administration, or bypass permission is needed.
  App-authored PRs trigger checks; PRs written with the ordinary `GITHUB_TOKEN`
  would not automatically trigger these workflows.
* `SESSION_TFVARS_JSON`: an **infrastructure-plan environment secret** containing
  JSON with the variables in
  `infrastructure/session/session.example.tfvars`. Match the account/region and
  replace the documentation-only IP with your current public `/32` address.

Create environments `registry-release`, `release-proposal`, `infrastructure-plan`
and `infrastructure-apply`, limited to main. Require Code-S-12 approval on
`infrastructure-apply` and prevent self-review. Source and release PRs provide the
application review gates; do not require four separate approvals for image publishers.

The infrastructure roles are **not** created with AdministratorAccess by this
repository. Provision them with an AWS administrator after selecting the account.
Both trust only `sts.amazonaws.com` and this repo's exact environment subject:
`repo:Narx-Space-Prod/commerce-aws:environment:infrastructure-plan` or
`...:environment:infrastructure-apply`. Use max session durations matching the
workflow (plan 30 minutes, apply one hour). The plan role needs discovery/read
permissions for session resources and runtime secret refresh, state GetObject,
plan PutObject, and state-lock Get/Put/Delete. The apply role additionally needs
session resource CRUD, scoped PassRole, IAM session-role management, plan-version
GetObjectVersion and state writes. Do not grant either role write access to its own
trust/policies, bootstrap publisher trust, or unrelated infrastructure. Review IAM
permissions against the actual plan before activation; Terraform validation cannot
prove that an IAM policy is sufficient or safely scoped.

These role policies and GitHub App credentials are an AWS activation prerequisite,
not something the unconfigured workflows can silently invent for your account.

The reviewed `infrastructure/bootstrap/plan-identity.tf` defines the plan role.
The existing MFA bootstrap role deliberately cannot create new IAM roles. Have an
AWS administrator create this role and its inline policy from the reviewed Terraform
documents, then import both resources into the existing bootstrap state before any
bootstrap apply. Use the same private variable file and MFA bootstrap profile used
for the original imports:

```bash
terraform -chdir=infrastructure/bootstrap import -var-file=../../.work/bootstrap-access.tfvars.json aws_iam_role.plan commerce-aws-plan
terraform -chdir=infrastructure/bootstrap import -var-file=../../.work/bootstrap-access.tfvars.json aws_iam_role_policy.plan commerce-aws-plan:commerce-aws-plan
terraform -chdir=infrastructure/bootstrap plan -var-file=../../.work/bootstrap-access.tfvars.json
```

Confirm the plan shows no changes to these imported resources. Set
`AWS_PLAN_ROLE_ARN` to the resulting role ARN. The role can read session state and
write its lock and saved plans, so treat it as sensitive; it cannot overwrite the
state or deploy the session. Its discovery permissions and access to the runtime
secret need review and verification against a real plan. Creating this identity alone
does not deploy an EKS cluster. Keep `INFRA_ENABLED=false` until the separate apply
identity and all activation checks are complete.

## 4. Create the session infrastructure

For the first session you can plan locally using the authenticated read-only profile;
the existing bootstrap role is not authorized to apply session infrastructure. An
actual apply requires the separately reviewed deployment role and approval.
Initialize the backend after replacing the example values below:

```bash
cp infrastructure/session/session.example.tfvars infrastructure/session/terraform.tfvars
terraform -chdir=infrastructure/session init -reconfigure \
  -backend-config='bucket=YOUR_STATE_BUCKET' \
  -backend-config='key=session/terraform.tfstate' \
  -backend-config='region=ap-south-1' \
  -backend-config='encrypt=true' -backend-config='use_lockfile=true'
terraform -chdir=infrastructure/session plan -out=session.tfplan
```

The saved plan is sensitive. Do not apply it with an unreviewed identity; use the
protected pipeline after the apply role is ready. Remove local plan files securely
when no longer needed.

Check the current EKS support calendar and regional add-on compatibility before
applying. Kubernetes starts at 1.35 with standard support only; add-on versions are
selected by EKS at initial creation and recorded in state. Review/pin the resulting
compatible versions for subsequent upgrade exercises. Update the PSA version and
schema validation together when deliberately changing Kubernetes versions.

For GitHub-operated sessions, set `INFRA_ENABLED=true`, dispatch **AWS infrastructure**,
choose apply and inspect the Plan job. Code-S-12 approves Apply, which downloads
the exact S3 object version and checks its SHA-256 before applying. Do not run a
local apply concurrently. State locking also prevents concurrent state changes.

Subscribe/confirm the SNS email: unconfirmed subscriptions do not deliver alarms.

## 5. Install the platform and private administration tools

The helper checks the AWS account, cluster name and actual API endpoint. It targets
the dedicated `commerce-aws` context, never your local kind cluster:

```bash
bash scripts/platform.sh install
kubectl --context commerce-aws get nodes
kubectl --context commerce-aws get pods -A
kubectl --context commerce-aws get storageclass
```

It installs pinned External Secrets, metrics-server, AWS Load Balancer Controller,
kube-prometheus-stack and Argo CD via Helm. This is a deliberate split: Terraform
owns AWS, Helm owns platform releases, Argo CD owns the application. Do not let a
second controller manage the same objects. Platform upgrades change versions/values
through a PR, then rerun this helper; Argo does not upgrade the platform tools.

The helper generates/preserves Grafana credentials and prompts for a **dedicated**
Slack incoming webhook with hidden input. It never copies credentials from the old
project or prints them. Installing the alert route can send real operational alerts
to that channel. Grafana/Prometheus/Argo are not exposed through the public ALB.

```bash
kubectl --context commerce-aws -n monitoring port-forward svc/monitoring-grafana 3000:80 --address 127.0.0.1
# In another terminal:
kubectl --context commerce-aws -n argocd port-forward svc/argocd-server 8443:443 --address 127.0.0.1
```

From your desktop use `ssh -L 3000:127.0.0.1:3000 -L 8443:127.0.0.1:8443 user@linux-host`.
Open Grafana at `http://localhost:3000` and Argo at `https://localhost:8443`.
Retrieve initial login credentials locally from the scoped Kubernetes secrets;
never paste them into a ticket/chat or commit them. Change initial admin passwords
before sharing access. Existing secrets are preserved rather than reset on each run.

Default Grafana dashboards cover Kubernetes/node/workload resources. The app's
ServiceMonitor scrapes all six processes; use Explore for request rates, latency,
errors and delivery metrics. Alertmanager routes warning/critical alerts to Slack,
with a 30-second grouping delay and resolved notifications. CloudWatch queue alarms
use SNS email. Per-stage GitHub/Argo Slack summaries are not implemented here yet;
Actions/Argo remain the delivery status source.

## 6. Configure HTTPS and the first signed release

For an existing Route 53 public hosted zone, set `shop_hostname` and
`route53_zone_id` in the session variables. Terraform provisions the regional ACM
certificate and its DNS validation record and waits for issuance. It does not buy a
domain or create a paid hosted zone. With external DNS instead, request/validate a
certificate manually **in the ALB region** and wait for ISSUED. Domain purchases
and hosted-zone charges are separate from this project's session resources.

Use the non-secret Terraform output ARNs in `deploy/config.example.yaml`, update
host/certificate/publicOrigin, then copy its reviewed contents to
`deploy/environment.yaml` on a feature branch. Keep it disabled until a complete
release exists. Never put secret values in Helm values.

Before setting `DELIVERY_ENABLED=true`, check ECR repositories, OIDC trust,
main-only environments, branch protection and release App permissions. Enable
publication and merge a small, real application change. To build all four images
for the first release, make the initial application import after enabling delivery,
or change the reviewed workflow/script configuration (which deliberately rebuilds
all components). There is no hidden force-build API or mutable `latest` release.

The main pipeline tests/scans each affected image, exports the exact runtime tar,
loads it in a separate publisher, publishes an immutable commit tag, signs its
digest and attests its SBOM. There is **no publication rebuild**. A release App
opens `release/<source-sha>` containing the four digest references. Later component
releases preserve previously reviewed digests for unchanged services.

Before approving a release, log in to ECR locally and verify **every** candidate
image using a pinned Cosign v3 client:

```bash
aws ecr get-login-password --region ap-south-1 | docker login \
  --username AWS --password-stdin ACCOUNT.dkr.ecr.ap-south-1.amazonaws.com
cosign verify \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity https://github.com/Narx-Space-Prod/commerce-aws/.github/workflows/ci.yml@refs/heads/main \
  'ACCOUNT.dkr.ecr.ap-south-1.amazonaws.com/commerce-aws/frontend@sha256:REAL_DIGEST'
```

Check the actual certificate identity produced by the reusable workflow in the
first activation run. If it names `image.yml` instead of `ci.yml`, narrow the exact
identity to the verified main workflow; do not replace it with an unrestricted
regex. Verify the CycloneDX attestation with `cosign verify-attestation --type
cyclonedx` using the same issuer/identity before relying on the SBOM evidence.

Merge the reviewed release/configuration PRs. Argo polls main and syncs the app.
External Secrets creates runtime secrets; the database-user Job completes before
application deployments. RDS's generated master password stays out of app pods.

```bash
kubectl --context commerce-aws -n commerce get externalsecret
kubectl --context commerce-aws -n commerce get pods,svc,hpa,ingress,pvc
kubectl --context commerce-aws -n commerce rollout status deploy/commerce-orders --timeout=10m
kubectl --context commerce-aws -n commerce rollout status deploy/commerce-frontend --timeout=10m
kubectl --context commerce-aws -n argocd get application commerce
```

Find the ALB DNS name from the Ingress, then add a Route 53 alias A record or an
external-provider CNAME for your shop subdomain. Test HTTP redirect, valid HTTPS,
registration/login, cart, test payment, order history and asynchronous receipt.
For Razorpay, put test keys into a dedicated secret and map to `commerce-payments`;
the current chart references that optional secret but does not provision keys.
Do not call the payment journey verified until the sandbox exercise passes.

## 7. Normal developer and delivery flow

```text
feature branch → PR → read-only checks + affected-image tests/scans
→ CODEOWNER review → merge main → exact tested images to ECR + signatures/SBOM
→ release PR → reviewer verifies evidence/digests → merge
→ Argo sync → database-user setup → rolling deployments → readiness → monitoring
```

Required checks summarise configuration plus all necessary image builds. HIGH or
CRITICAL image findings block delivery, including unfixed ones. Fix the dependency
or prepare a specifically justified security change; do not switch off scanning.
Source changes that arrive during an older build prevent that older release proposal
from replacing the newer source. Review outstanding release PRs before merging a
newer release; close superseded candidates rather than merging out of order.

The reusable Dockerfiles contain the test commands. Node tests protect session,
checkout and BFF behaviour; Go tests cover the catalogue facade; Java tests cover
commerce and delivery; Python tests cover cart behaviour. You should understand
what fails and what is released, even if application development is not your role.

## 8. Useful operations commands and exercises

Always specify `--context commerce-aws` to avoid changing the old local cluster.

```bash
kubectl --context commerce-aws -n commerce get events --sort-by=.lastTimestamp
kubectl --context commerce-aws -n commerce describe pod POD_NAME
kubectl --context commerce-aws -n commerce logs deploy/commerce-orders --tail=100
kubectl --context commerce-aws -n commerce logs deploy/commerce-worker --previous --tail=100
kubectl --context commerce-aws top pods -n commerce
kubectl --context commerce-aws get volumeattachments,pv
aws eks describe-cluster --name commerce-aws --region ap-south-1
aws cloudtrail lookup-events --max-results 10 --region ap-south-1
```

Practice these in order and record the result, cause and recovery:

1. **Deploy a small UI change.** Observe only frontend rebuilding, the release PR,
   digest change, Argo sync, readiness and the new UI. Avoid cached/mutable image tags.
2. **Break a readiness endpoint in a branch.** Confirm failed rollout diagnosis;
   recover via a reviewed Git revert. Readiness is a traffic gate, not a data rollback.
3. **Investigate ImagePullBackOff.** Check exact digest, ECR region/account and node
   pull policy. Never fix it by making the registry public.
4. **Exercise HPA.** Generate controlled traffic, watch CPU and desired replicas.
   Observe Pending pods if capacity runs out. Manually grow the node group through
   Terraform, and reduce it after the exercise. Do not confuse HPA with node scaling.
5. **Exercise network policy.** Confirm application paths and monitoring work;
   a temporary pod in another namespace must not reach the database/app directly.
   Inspect the CNI and security groups instead of disabling policies permanently.
6. **Exercise SQS.** Stop the worker through a reviewed replica change, create a
   test event and watch backlog/age. Restore it and confirm receipt processing.
   Test a poison event with dedicated test data, observe the DLQ, diagnose before
   redriving, and confirm duplicate delivery does not duplicate a receipt.
7. **Test an alert and its resolution.** Use a clearly labelled temporary rule in
   a reviewable change; verify Slack accepts both notifications and remove the rule.
   Do not send repeated production-looking test alerts to an unrelated channel.
8. **Inspect CloudTrail and audit logs.** Find an operator change, correlate identity,
   action and time. CloudTrail Event History is available for management events;
   no separate long-term trail/archive is provisioned in this first version.
9. **Recover an application release.** Revert the relevant release/config commit
   through a PR. Argo restores the reviewed old digests. `kubectl rollout undo`
   alone is temporary because GitOps will reconcile it away.
10. **Perform the database restore below**, then complete a full teardown and rebuild.

There is no unattended business-data rollback. Flyway schema changes must stay
compatible with the previous application release. A Git revert cannot undo an order,
refund, destructive SQL migration or external payment.

## 9. Database backup and restore

RDS keeps one day of automated backups while the session exists. Session deletion
removes automated backups and **skips the final snapshot** to make cost cleanup
predictable. Preserve data with a manual snapshot before approving destroy.

```bash
snapshot="commerce-aws-manual-$(date -u +%Y%m%d%H%M%S)"
aws rds create-db-snapshot --db-instance-identifier commerce-aws \
  --db-snapshot-identifier "$snapshot" --region ap-south-1 \
  --tags Key=Project,Value=commerce-aws Key=Environment,Value=learning Key=ManagedBy,Value=manual-backup
aws rds wait db-snapshot-available --db-snapshot-identifier "$snapshot" --region ap-south-1
aws rds describe-db-snapshots --db-snapshot-identifier "$snapshot" --region ap-south-1
```

To restore into a new session, set `existing_backup_snapshot` to the saved snapshot
identifier and review the replacement plan. Never replace an active database by
accident: restore into a separate temporary identifier first for a non-disruptive
exercise, or destroy the disposable session after verifying its backup.
The RDS master password is managed by Secrets Manager; the bootstrap Job establishes
the limited application login with the new runtime password. Test login, product,
order and receipt data after restoring. A snapshot marked Available proves snapshot
creation; successful application reads prove recovery. Snapshots continue costing
money until intentionally deleted after they are no longer needed.

## 10. End every AWS session deliberately

Check backups before using these commands. Teardown deletes commerce/monitoring
PVCs and their data. Retained manual RDS snapshots are the recovery path.

```bash
CONFIRM_DESTROY='destroy commerce-aws' bash scripts/platform.sh teardown
# Inspect controller-owned resources before destroying the cluster:
aws elbv2 describe-load-balancers --region ap-south-1
aws ec2 describe-volumes --region ap-south-1
terraform -chdir=infrastructure/session plan -destroy -out=destroy.tfplan
terraform -chdir=infrastructure/session apply destroy.tfplan
```

Alternatively dispatch the infrastructure workflow with operation `destroy` and
confirmation `destroy commerce-aws`, inspect the saved destroy plan and approve it.
Run Kubernetes cleanup first. Immediately before a workflow destroy, the apply job
also refuses to proceed if any load balancer remains in the session VPC or any
project-tagged CSI volume remains. The apply role needs read access to those AWS
APIs. This guard cannot identify untagged orphaned volumes, and local Terraform
commands do not run it; always perform the inventory and billing review below.
Removing EKS before the ALB controller processes its
Ingress finalizer can leave billable load balancers and network interfaces behind.
Deleting Helm releases does not reliably delete their retained PVCs; the helper
explicitly deletes monitoring PVCs while the EBS driver still exists.

Finally verify EKS cluster deletion and inspect EC2 instances, EBS, ALBs, RDS,
snapshots, public IPs, secrets and CloudWatch log groups for this project. Confirm
there is no NAT Gateway. Keep state/images only intentionally. Review AWS Billing
after its reporting delay; a successful Terraform command is not a billing audit.
Do not destroy the retained bootstrap root as part of normal session cleanup.

## Python scripts: what a DevOps engineer should understand

You do not need to memorise every line. You should be able to explain inputs,
outputs, permissions, side effects, failures and how to rerun safely.

| Script | What to understand |
|---|---|
| `changes.py` | Git diff selects components; workflows/build scripts invalidate all builds; inventory/platform changes do not; cart is independent of Java |
| `release.py` | Publisher records merge into one JSON manifest; exact component/account/region/digest validation |
| `check_chart.py` | Temporary enabled/disabled renders, core API schemas and container security checks; no cloud access |
| `secrets.py` | Hidden Slack input, generated Grafana password, fixed context/scope, preservation, stdin-only secret writes |
| `inventory.py` | Read-only before/after resource reports, account guard, untagged resources and explicit incomplete-result handling |

The shell helpers install checksum-verified tools and perform explicit EKS platform
installation/cleanup. CI YAML orchestrates steps; Terraform describes AWS resources;
Helm templates Kubernetes resources. Keeping these responsibilities separate avoids
one giant script that tries to build, provision, deploy and recover everything.

## What remains before calling the environment operational

The foundation and planning role are created and tracked, and release App
authentication has been verified. Still needed: design and provision a scoped apply
role; validate both OIDC roles and the GitHub infrastructure workflow against AWS;
review cost and the session plan; apply with approval; install the platform; configure
ACM/DNS/payment sandbox; verify signed releases; and perform real deployment, alert,
restore and teardown exercises. Record actual results rather than describing prepared
YAML as a completed production deployment.

## Reference: concepts before commands

**A Git commit** is a snapshot identified by a hash. A branch is a movable name
for a series of commits. A pull request (PR) asks a reviewer to merge a branch;
checks provide evidence but do not replace human review. GitHub environments
protect jobs and scope secrets. Their branch restrictions are part of the OIDC trust
boundary, so changing them can change who can access AWS.

**A container image** is a packaged filesystem and startup configuration. A tag
is a name; a digest identifies exact content. ECR stores images; EKS runs them. A
Dockerfile explains how to build an image; Kubernetes manifests explain how to run
it. Helm renders templates and values into manifests. A Deployment maintains pods,
a Service gives pods a stable internal address, and an Ingress describes external
HTTP routing. A controller observes desired objects and creates or adjusts actual
resources. Argo CD is a controller whose desired application state comes from Git.

**Terraform** compares configuration with state and AWS, builds a dependency graph
and presents a plan. State maps Terraform resource addresses to actual AWS IDs;
it is not the infrastructure itself. `init` downloads providers and connects the
backend; `validate` checks configuration; `plan` proposes changes; `apply` makes
changes; `destroy` proposes deletion of managed resources. A provider is the
plugin that talks to AWS; a module is a collection of configuration. These two
roots have independent state, so destroy of `session` must not delete `bootstrap`.
Terraform automatically orders references but cannot see every resource a
Kubernetes controller creates. Keep state and saved plans private: both may contain
secrets, even when CLI output hides them.

**One identity, different jobs.** A human signs in with MFA; GitHub Actions requests
a short-lived OIDC token; AWS validates its repository/environment claims and
returns temporary role credentials. An IAM role has a trust policy describing who
may assume it and permission policies describing what an assumed role may do. A
permissions boundary limits the maximum permissions that role can receive; it does
not grant permissions. Pod Identity maps a Kubernetes service account to an AWS
role for specific pods. None of these is a reason to put long-lived keys in Git.

## Reference: repository and Terraform code tour

This table describes the current source, including optional or disabled paths. An
entry describes intent; successful validation or a real deployment is separate.

| Path | Responsibility and important details |
|---|---|
| `infrastructure/bootstrap/versions.tf`, `variables.tf` | Provider/Terraform versions, region and state-bucket inputs; inspect constraints before upgrading. |
| `infrastructure/bootstrap/main.tf`, `backend.tf` | Retained S3 bucket, public-access block, encryption, ownership and versioning; S3 backend points at remote state after initial bootstrap. |
| `infrastructure/bootstrap/budget.tf` | Account-wide monthly USD budget and email warnings, not an automatic spending limit. |
| `infrastructure/bootstrap/registry.tf` | GitHub OIDC provider, four immutable ECR repos, bounded registry publisher and lifecycle expiration for private plan objects. |
| `infrastructure/bootstrap/access.tf` | The separately bootstrapped, MFA-required human role and publisher permission boundary; the role deliberately cannot grant itself more access. |
| `infrastructure/bootstrap/plan-identity.tf` | Plan role trust is restricted to the planning environment and main; it may read state/metadata and write locks/plans but not overwrite session state. |
| `infrastructure/bootstrap/outputs.tf`, `bootstrap.example.tfvars`, `.terraform.lock.hcl` | Non-secret outputs, example inputs and locked provider selections/checksums; real values belong in ignored private files. |
| `infrastructure/bootstrap/tests/` | Mocked AWS tests of trust, boundaries and retained resources. Mock tests do not prove live AWS access or eventual consistency. |
| `infrastructure/session/versions.tf`, `variables.tf` | Session providers, account allowlist and defaults/validation, including two AZs and explicit operator IPv4 `/32` addresses. |
| `infrastructure/session/network.tf` | `10.42.0.0/16` VPC, two public and two database subnets, internet gateway, public routes and database security group. No NAT or SSH is created. |
| `infrastructure/session/cluster.tf` | EKS control plane, managed nodes/launch template, API access, logging, add-ons, node/CNI/storage identities and pod-identity integrations. |
| `infrastructure/session/data.tf` | RDS, SQS + DLQ, generated passwords, runtime secret and separate publisher/worker/secrets identities. Session publisher name is distinct from retained ECR publisher. |
| `infrastructure/session/ingress.tf` and `policies/load-balancer.json` | Load Balancer Controller identity and its pinned upstream IAM policy; the controller, not Terraform, creates the ALB after an enabled ingress. |
| `infrastructure/session/https.tf` | Optional ACM certificate and DNS validation in an existing Route 53 zone; no domain is purchased. |
| `infrastructure/session/notifications.tf` | SNS email subscription and KMS policy/key for queue notifications. Email subscription must be confirmed. |
| `infrastructure/session/observability.tf` | Queue age and DLQ CloudWatch alarms. EKS log retention is configured in `cluster.tf`. |
| `infrastructure/session/outputs.tf`, `session.example.tfvars`, `.terraform.lock.hcl`, `tests/` | Useful references, example inputs, locked provider versions and mocked boundary checks. |
| `deploy/chart/templates/` | Workloads and services, Redis/storage, bootstrap job, External Secrets, network policies, monitoring resources and optional ingress. |
| `deploy/chart/values.yaml`, `deploy/environment.yaml`, `deploy/release.json` | Base defaults, reviewed environment settings and immutable release digests. Argo combines environment and release files; actual current settings start disabled. |
| `deploy/platform/` | Helm chart versions/values and storage class. Monitoring, secrets, Argo and controllers are installed by the platform helper, not by Terraform. |
| `deploy/argocd.yaml` | One AppProject and one Application, tracking `main`; automated sync, pruning, self-heal and selected HPA replica-difference handling. |
| `.github/CODEOWNERS`, `.github/PULL_REQUEST_TEMPLATE.md` | Review ownership and PR prompts. Effective branch protection/environment settings live in GitHub and must also be checked there. |
| `.github/workflows/` | CI orchestration, reusable image workflow, manual infrastructure workflow and manually dispatched release-App verification. |
| `.trivyignore.yaml` | Documented, expiring infrastructure scan exceptions. Review each exception and its expiry; it is not a blanket image-scan exception. |

### Dockerfiles: from source to runtime

Each component has its own build context and multi-stage Dockerfile. A stage is a
named intermediate image; the final `runtime` stage is the one CI tests and, after
merge, publishes. All base images are pinned by digest. `COPY` adds files, `RUN`
executes build steps, `USER` chooses the runtime user, and `ENTRYPOINT` or `CMD`
defines startup. `EXPOSE` documents a port; it does not publish it to the internet.

| Dockerfile | Build/test path | Runtime result |
|---|---|---|
| `application/frontend/Dockerfile` | Node dependencies installed with `npm ci --ignore-scripts`; source and tests copied; `npm test` runs. | Node runtime copies tested source and public files, removes package-management tools and runs as UID 10001 on port 8080. |
| `application/catalogue/Dockerfile` | Go format, vet and tests run before building a static binary. | Small Alpine runtime contains the binary and runs as UID 10001 on port 8081. |
| `application/orders/Dockerfile` | Maven dependencies are cached in an earlier stage; `mvn verify` runs and builds the JAR. | Java runtime copies the tested JAR and database CA certificates, runs as UID 10001 on port 8083. Orders, publisher and worker use this same image. |
| `application/orders/cart/Dockerfile` | Hash-pinned Python dependencies become wheels; pytest runs with development dependencies. | Runtime installs only production dependencies from wheels, copies tested app code and runs as UID 10001 on port 8082. |

Pinning a base image gives repeatable selection, not permanent safety: dependencies
and base images still require reviewed security updates. Cache speeds up builds;
it does not make an old cached result trustworthy by itself. Kubernetes adds
read-only root filesystems, capability restrictions, probes and resource settings
in the chart. CI additionally inspects the runtime image user and scans it.

## Reference: AWS service choices and prerequisites

| Service | Job in this project | Before use / important limitation |
|---|---|---|
| IAM and STS | Human role, GitHub OIDC roles and workload permissions. | Enable root MFA; use a non-root operator and short-lived credentials. The apply role is pending. Never create or paste root access keys. |
| VPC / EC2 networking | Network isolation, routes, security groups, and worker connectivity. | Confirm account, region, two available AZs, free address space and quotas. Public worker addresses save NAT cost but are not the usual hardened private-node production topology. |
| EKS and EC2 | Managed Kubernetes API and a managed worker node group. | Check service eligibility, quotas, version/add-on compatibility and current price. One worker is a single point of failure; EKS control-plane availability does not make the workload highly available. |
| ECR | Four immutable image repositories. | OIDC publisher, repository permissions, encryption and scan settings. The initial repositories exist; publishing is disabled. Image storage is retained and can cost money. |
| S3 | Separate bootstrap and session state keys plus encrypted, versioned saved plans and lock files. | Restrict bucket access; state and plans can contain passwords. Bucket versioning and plan expiry do not replace access review or backups. |
| RDS PostgreSQL | Private order/account database, encrypted storage and managed master secret. | Check engine availability and capacity; confirm backup/restore and compatible migrations. The disposable session deletes automated backups and skips a final snapshot. |
| EBS | Worker root disk and encrypted dynamically provisioned Kubernetes volumes. | CSI add-on and storage class must work. A PVC can create a billable disk outside Terraform's direct state. |
| SQS | Order-paid queue, retries and dead-letter queue. | Pod Identity permissions must be validated. Monitor oldest message age and DLQ depth; a redrive needs investigation and duplicate-safe consumers. |
| Secrets Manager | Runtime connection data and RDS-managed master credentials. | External Secrets and Pod Identity must work. State is also sensitive. Secret rotation and payment sandbox setup need their own exercises. |
| ACM / Route 53 / ALB | Optional validated HTTPS certificate, DNS and public ingress. | Existing domain and hosted zone or external DNS, issued regional ACM certificate, enabled ingress and controller. DNS/ALB can add costs and are not created by default. |
| CloudWatch / SNS / KMS | EKS log group and queue alarms delivered through an encrypted topic. | Confirm SNS email subscription; verify KMS/topic policies and alarms in a live session. Logs and key usage may cost money. |
| AWS Budgets / Billing | Account-wide email warnings and actual spend visibility. | Budget thresholds are delayed warnings, not a stop button. Check credits, currency, taxes, other regions and actual billing separately. |
| CloudTrail | Event history for investigating AWS management actions. | The project does not configure a durable, centralized multi-account audit archive. Do not assume event history replaces a long-term trail. |

### How the network fits together

The internet-facing ALB listens on 80 and 443, redirects HTTP to HTTPS and forwards
to frontend pod IPs when ingress is enabled. The frontend calls backend Services
inside the cluster. PostgreSQL sits in database subnets with no public IP and accepts
TCP 5432 from the referenced EKS cluster security group. The public subnets have
routes to an internet gateway; the database subnets have no NAT route. Node public
IPs support outbound access without a NAT gateway. Security groups are stateful;
Kubernetes NetworkPolicy provides additional pod traffic restrictions when its CNI
implementation is working. Neither layer replaces the other.

EKS requires subnets in two AZs, but this configuration places its worker and RDS
instance in the first AZ. An AZ label can map to different physical AZs in different
AWS accounts. This is a deliberately low-cost learning tradeoff, not multi-AZ
application resilience. The current operator IP is an explicit `/32`; laptop or
network changes can change it. Refresh the protected variable and review an
infrastructure plan before relying on API access. Do not open `0.0.0.0/0` to make a
failing connection disappear.

### Request and message journey

1. A browser resolves the shop hostname, reaches ALB HTTPS and receives a valid ACM
   certificate. The ingress controller routes the request to the frontend Service.
2. Frontend requests reach the catalogue, cart and orders Services as appropriate.
   Redis holds cart data; orders and accounts are stored in private RDS.
3. The order service records an order and outbox event together in the database.
   The publisher reads the outbox and sends a message to SQS with its own IAM role.
4. The worker receives the message with a different role, records its receipt and
   acknowledges it. Duplicate-delivery handling matters because SQS can redeliver.
5. Failed messages eventually reach the DLQ; CloudWatch alarm → SNS email and
   Prometheus alert → Alertmanager → Slack are separate notification paths.

Payment integration is a sandbox exercise: test credentials must be separately
configured, and a successful deployment does not itself prove a payment, refund,
order or notification has worked.

## Reference: pipeline, step by step

### PR and image checks

A developer creates a branch and opens a PR against `main`. The `CI` workflow starts
on the PR and on pushes to `main`. `Configuration checks` selects affected images,
validates workflow syntax, shell scripts, secrets, Terraform format/provider/mock
tests, Python tests and chart renders, and scans Terraform. `scripts/changes.py`
compares changed paths without executing code from those paths. Frontend-only
changes select frontend; a cart-only path selects cart without selecting Java orders;
workflow and shared build-script changes select all four. A docs-only change does
not build images. This optimization does not eliminate the configuration checks.

Each selected image runs the reusable `image.yml` workflow. Its Dockerfile builds
and runs that component's tests; the runtime image must declare a non-root user.
Trivy scans the image and produces a CycloneDX SBOM; HIGH/CRITICAL findings fail
the scan. Selected components run as a parallel matrix with independent BuildKit
caches. The single `Required checks` gate succeeds only when configuration passed
and selected image builds passed or were legitimately skipped. A successful gate
is evidence of those checks, not evidence of a real EKS deployment.

Code-S-12 reviews the source PR under the repository's branch protection. A
reviewer should inspect the diff and check results; a bot passing checks does not
act as an independent human reviewer. Merging then triggers the main workflow.

### Publish and propose a release

With `DELIVERY_ENABLED=true` and a qualifying main push, the workflow exports the
**same tested runtime image** as an artifact, then the publisher job loads it;
it does not rebuild the image. It assumes the registry role using GitHub OIDC,
pushes an immutable commit tag to the correct ECR repo, obtains its digest, signs
it with Cosign and attaches an SBOM attestation. The immutable-tag check refuses a
conflicting image under the same source tag. Security evidence and release records
are workflow artifacts with the retention specified in YAML; the ECR image is
separately retained. Signature generation does not install an admission policy.

The release-proposal job fetches current `main` and refuses to create a stale
proposal if relevant application, workflow or script code changed since the build.
`release.py` validates component, source SHA, ECR account/region and digest shape,
then merges new records with existing reviewed digests for unchanged components.
The dedicated GitHub App opens a PR updating `deploy/release.json`. Reviewers verify
the signature and SBOM for each candidate digest and review the deployment diff.
On the first release, the manifest needs all four images; an affected-only build
cannot invent missing prior digests. Merge the release PR when approved.

The App token is for a scoped GitHub installation; the AWS role is a different
identity. The App can open a PR, but its token must not bypass required checks or
human review. The App's manual verification workflow is an authentication check;
it is not an end-to-end release test.

### Infrastructure plan and approval

The manual `AWS infrastructure` workflow operates only on main when
`INFRA_ENABLED=true`. Its plan job assumes the plan role and loads session variables
from the protected environment secret. For destroy, it checks the exact confirmation
phrase. Terraform saves a binary plan privately to versioned S3; the job passes its
object version and SHA-256 to the next job. Plans may contain passwords and expire
according to the bucket lifecycle; do not publish them as build artifacts.

The apply job waits for the `infrastructure-apply` environment's independent
reviewer, assumes a separate apply identity, downloads that exact object version,
checks its hash and applies it. Approval is for the displayed plan and source
revision; a stale/expired/changed-state plan must be regenerated and reviewed.
For destroy, it first checks the session VPC for load balancers and checks for
project-tagged CSI volumes. A failure blocks that workflow apply. This is a partial
guard: it does not discover every untagged orphan or stop a local Terraform apply.
The apply role still needs to be designed, scoped, provisioned and live-tested.
Also review whether the configured one-hour AWS credentials cover the 90-minute
job; an expired session during a long apply needs a safe retry strategy.

### Argo CD and Kubernetes

The platform helper installs Argo CD; Argo watches the public repository's main
branch and the chart path. Its Application renders values in order from environment
and release files. When desired state changes, automated sync applies it; `selfHeal`
repairs supported drift and `prune` removes objects no longer in desired state.
A release PR merge can therefore change the running pods after Argo polls and syncs,
provided the app is enabled and the cluster is healthy. It is not a guarantee of
an instant successful rollout. Check Argo sync/health, pod events, readiness and
ALB targets. Readiness stops unready pods receiving Service traffic; liveness and
startup probes handle different failure conditions. HPA changes selected replica
counts based on CPU; it does not add nodes. Argo ignores those replica differences
for the selected deployments so it doesn't fight the autoscaler.

A reviewed Git revert points Argo back to a previous desired image/configuration;
it doesn't undo database changes, messages, refunds or payments. Keep migrations
backward-compatible and test recovery. This project does not currently implement
unattended application or database rollback.

## Reference: scripts and how to read them

You don't need to become a Python developer, but you should read code at the level
needed to identify **input → validation → action → output → failure**. Start with
`python3 -m unittest discover -s tests -v`, then read the code and test together.

* `scripts/changes.py`: takes GitHub event JSON and a Git diff, selects allowed
  components and emits a JSON matrix through `GITHUB_OUTPUT`. Understand the special
  cart path, the full-rebuild triggers and what happens when a base SHA is missing.
* `scripts/release.py`: reads publisher JSON records, validates source SHA and exact
  ECR digest/account/region/component, combines them with existing release values,
  then writes `deploy/release.json` only when records were supplied. It validates
  digest shape and location, not cryptographic signatures.
* `scripts/check_chart.py`: renders disabled and fully enabled profiles using dummy
  data, checks security properties and validates standard Kubernetes schemas. It
  uses temporary files and caches pinned schemas with bounded downloads. Operator
  CRDs are structurally checked here, not live-admitted by a cluster.
* `scripts/inventory.py`: checks the expected account, runs a fixed read-only list
  of AWS queries, records private timestamped JSON, and reports errors as incomplete.
  It does not delete anything or guarantee coverage of every region/service.
* `scripts/secrets.py`: requires the dedicated Kubernetes context, preserves an
  existing secret, generates a Grafana password or accepts a hidden Slack webhook,
  and passes the Kubernetes object over stdin. It does not create an AWS secret.
* `scripts/platform.sh`: verifies account, cluster and endpoint before installing
  pinned Helm releases or cleaning up. Teardown requires the exact confirmation
  phrase and must run while the cluster/controller still exists.
* `scripts/tools.sh`: downloads selected pinned CI tools and verifies checksums.
  Review the source, checksum and version before changing a pin. `.work` is local,
  ignored workspace material and must not be committed.

Useful read-only commands, run from the repository root with the correct context:

```bash
# Git and GitHub
 git status --short --branch
 git log --oneline -8
 gh pr list --repo Narx-Space-Prod/commerce-aws
 gh run list --repo Narx-Space-Prod/commerce-aws --limit 10
# AWS identity and infrastructure
 aws sts get-caller-identity --profile commerce-learning
 aws eks list-clusters --region ap-south-1 --profile commerce-learning
 aws ecr describe-repositories --region ap-south-1 --profile commerce-learning
# Kubernetes, after the cluster and dedicated context exist
 kubectl --context commerce-aws get nodes
 kubectl --context commerce-aws get pods -A
 kubectl --context commerce-aws -n commerce get deploy,svc,hpa,ingress,pvc
 kubectl --context commerce-aws -n argocd get applications
```

Commands that create infrastructure, change Git, post messages, access secrets or
delete data require the correct identity and an intentional reviewed operation.
A `describe` or `get` failure is not proof the resource is absent: check identity,
region, network, permissions and CLI error first.

## Reference: first session checklist and incident thinking

**Before applying:** confirm the exact AWS account/region, MFA and current login;
check the latest budget/credits and actual prices; check current operator public
IP; verify the state bucket and branch protections; make sure the apply role and
plan role are provisioned/tested; inspect the saved plan, session duration, quota,
image and DNS prerequisites; record baseline inventory and a stop time. Verify
backup requirements and whether the session is disposable. No budget alert makes
a hard cap. AWS Free plan/service eligibility must be checked for the account;
seeing an empty EKS console does not establish eligibility.

**After applying:** verify cluster and node readiness, install platform components,
confirm SNS email, configure only intended Slack routing, validate secret access,
review and merge the release, then check Argo, pods, ingress, health and a sandbox
transaction. Record what was actually exercised and any failures. Avoid assuming
that a successful Terraform apply proves the app or alerting works.

**When a release fails:** identify the layer before changing anything. A failed PR
check needs its Actions log; a failed publish needs ECR/OIDC/signature logs; an
absent release PR needs the `DELIVERY_ENABLED` flag, selected components and
proposal job; an OutOfSync Application needs Argo's diff/events; an unhealthy pod
needs describe/events/logs; an unreachable public URL needs DNS, ACM, ingress, ALB
listeners/targets and network checks. Never disable security controls simply to
make a check green. Preserve evidence, choose a reviewed revert if appropriate,
then verify recovery.

**When a destroy fails:** keep the cluster and controllers available until ingress
and PVC cleanup is finished; inspect ALB/VPC and tagged CSI volumes, retry the
reviewed plan, compare pre/post inventories, inspect untagged resources and review
Billing later. A manual RDS snapshot can be kept deliberately, but has ongoing
storage cost. A scheduled KMS deletion or retained logs/images/state can also remain
after the session; check their current lifecycle and charges. Do not delete
unrelated baseline resources. If state has no VPC output after a partial apply,
the workflow guard fails closed; investigate the partial state and resources before
choosing a documented recovery path.

### Practice path and interview questions

Work through a reviewed PR and affected build; inspect an image digest and SBOM;
explain OIDC and trust vs permission policies; trace traffic to a pod and DB;
observe Argo sync; diagnose a failing readiness probe; test SQS/DLQ and an alert;
restore a database snapshot and verify data; rehearse a Git revert; destroy the
session and compare inventory with baseline. For each exercise, record the trigger,
expected result, actual evidence, failure, fix, cost and cleanup.

Be able to answer: Why two state roots? Why is a digest safer than `latest`? Why
must apply use the reviewed plan version? Why can HPA leave pods Pending? Why isn't
an EKS control plane a guarantee of app availability? How do IAM trust and permission
policies differ? Why can an ALB survive a broken cluster teardown? Why doesn't a Git
revert undo a payment? Why is an AWS Budget not a spending cap? Explain the project's
actual tradeoffs rather than claiming multi-AZ availability or untested recovery.


## Primary references

* [EKS networking requirements](https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html)
* [EKS pricing](https://aws.amazon.com/eks/pricing/)
* [EKS supported Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html)
* [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
* [Pod Identity trust conditions](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-role.html)
* [EKS default envelope encryption](https://docs.aws.amazon.com/eks/latest/userguide/envelope-encryption.html)
* [CloudTrail event history](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/view-cloudtrail-events.html)
* [GitHub AWS OIDC](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
* [Terraform S3 backend and locking](https://developer.hashicorp.com/terraform/language/backend/s3)
* [AWS Load Balancer Controller v3.6.2 IAM policy](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.6.2/docs/install/iam_policy.json)

