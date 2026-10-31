# 4. Integrations handbook: monitoring, messaging, secrets and operations

## Contents

- [Start here: knowing whether a system works](#start-here-knowing-whether-a-system-works)
- [4.1 Monitoring: metrics, dashboards and alerts](#41-monitoring-metrics-dashboards-and-alerts)
- [4.2 AWS-side alerts are a separate route](#42-aws-side-alerts-are-a-separate-route)
- [4.3 Asynchronous order messaging: transactional outbox + SQS](#43-asynchronous-order-messaging-transactional-outbox--sqs)
- [4.4 Secrets Manager, Pod Identity and External Secrets](#44-secrets-manager-pod-identity-and-external-secrets)
- [4.5 DNS, TLS and ingress](#45-dns-tls-and-ingress)
- [4.6 Database recovery and safe diagnostics](#46-database-recovery-and-safe-diagnostics)
- [4.7 Runbook: diagnose a customer-impacting failure](#47-runbook-diagnose-a-customer-impacting-failure)
- [4.8 Learning exercises and interview explanations](#48-learning-exercises-and-interview-explanations)
- [4.9 Monitoring source walkthrough: from request to Slack](#49-monitoring-source-walkthrough-from-request-to-slack)
- [4.10 CloudWatch alarms: exact math and notification handshake](#410-cloudwatch-alarms-exact-math-and-notification-handshake)
- [4.11 Queue and application consistency concepts](#411-queue-and-application-consistency-concepts)
- [4.12 External Secrets data path, field by field](#412-external-secrets-data-path-field-by-field)
- [4.13 DNS, certificate and ALB handshake](#413-dns-certificate-and-alb-handshake)
- [4.14 Python helpers from an operator's point of view](#414-python-helpers-from-an-operators-point-of-view)
- [4.15 Learn operations through small failure drills](#415-learn-operations-through-small-failure-drills)
- [Guided simulation: alerts, messages and recovery evidence](#guided-simulation-alerts-messages-and-recovery-evidence)

This chapter connects the services around the application. It teaches what each integration does, where its configuration lives, how data/credentials flow, and how to investigate failures without exposing secrets.

## Start here: knowing whether a system works

A green deployment tells you that a controller reached a state. Customers care about outcomes: can they open the shop, complete a test checkout, and see the resulting order? Operations connects infrastructure signals to those outcomes.

**Metrics** summarize measurements over time. **Logs** describe discrete events. **Traces** follow an individual request across services. This repository provides metrics, local/container logs and selected AWS control-plane logs; it does not configure a distributed tracing platform or a central application-log archive. Understanding those gaps is part of understanding the architecture.

### Four useful service questions

- How many requests arrive? That is traffic or throughput.
- How long do they take? That is latency; examine slow percentiles, not just an average.
- How many fail? That is error rate, classified by symptom and service.
- How close are resources to exhaustion? That is saturation: CPU, memory, connections, queue backlog and disk space.

A counter only increases until a process restarts; use a rate over a time window to interpret requests per second. A gauge can increase or decrease, such as current queue depth. A histogram groups observations into buckets and can support latency percentile estimates. Labels split a metric into series; using order IDs or emails as labels can produce unbounded series and expose customer details. Prefer bounded labels such as component and status class.

### Worked example: a slow receipt worker

Checkout writes an order and outbox event. The publisher delivers the event to SQS. A slow worker lets queue age grow. The HTTP API might still be healthy, so an uptime-only check misses delayed receipts. Queue-age metrics expose the delay; CloudWatch routes an alarm to SNS. If the publisher instead fails before SQS, outbox age grows and Prometheus should detect it. These signals distinguish two different failure locations.

An alert needs an owner, a symptom, an actionable investigation path and a recovery signal. A dashboard does not page anyone. A rule that is loaded does not prove the notification reached a human. A successful notification does not prove every important failure has a rule. Test the full chain deliberately in a disposable environment.

### Reliability and recovery vocabulary

An **SLI** is a measurement such as successful checkout fraction. An **SLO** is an agreed target over a time window. An **error budget** is the tolerated amount of failure under that target. This repository does not define a complete business SLO/error-budget policy; the concepts help you judge whether infrastructure alerts reflect customer experience.

**RPO** describes how much data loss is acceptable; **RTO** describes how long recovery may take. A snapshot existing does not establish either. Measure a restore using known synthetic data, record the snapshot timestamp and recovery duration, then compare with the target. An infrastructure destroy followed by recreation cannot restore business data unless a usable backup exists.

Use section 4.9 for the metric-to-alert chain, 4.11 for message delivery semantics, 4.12 for secrets, and 4.15 for controlled drills. Record expected and observed outcomes separately so the documentation never presents an unperformed exercise as proven recovery.


## 4.1 Monitoring: metrics, dashboards and alerts

Monitoring answers three different questions:

- **Metrics:** numeric time series such as request rate, latency, error count, CPU, memory, queue depth and oldest-message age.
- **Dashboards:** selected charts that help an operator understand system health and trends.
- **Alerts:** rules that notify a human when a condition needs action. An alert is useful only if it is actionable, routed, owned and tested.

The platform Application `platform-monitoring` installs the pinned `kube-prometheus-stack` chart. It includes Prometheus, Grafana, Alertmanager, Prometheus Operator and Kubernetes exporters/rules. `deploy/platform/monitoring-values.yaml` sets small lab resource requests, six-hour/2GB Prometheus retention, 30-second scrape/evaluation intervals, 5Gi Prometheus PVC, 2Gi Grafana PVC and Slack delivery via a Kubernetes Secret. Monitoring PVCs are backed by encrypted gp3 EBS through the `gp3` StorageClass. These disks are billable and must be removed before EKS/CSI teardown.

A **ServiceMonitor** tells Prometheus Operator which Kubernetes Service endpoints to scrape. The commerce chart templates monitoring configuration for app metrics; inspect `deploy/chart/templates/monitoring.yaml` and service annotations/ports together. Kubernetes metrics and application metrics are distinct: `metrics-server` supplies resource metrics used by `kubectl top`/HPA; Prometheus scrapes time-series metrics for dashboards and alerts.

Access dashboards locally using port-forward after confirming the real Service name:

```bash
kubectl --context commerce-aws -n monitoring get svc
kubectl --context commerce-aws -n monitoring port-forward svc/PLATFORM_GRAFANA_SERVICE 3000:80
kubectl --context commerce-aws -n monitoring get pods
```

A random Grafana admin password is generated by `scripts/seed_secret.py grafana`; the secret is not checked into Git. Avoid commands that print Secret YAML or values. If login fails, check the correct context/namespace/secret existence and pod events without displaying the password.

### Alert routing

Alertmanager groups related alerts to avoid a Slack flood. In the values file, warnings and critical alerts route to Slack, `Watchdog` is intentionally suppressed, resolved events are sent, and a critical alert inhibits a warning with matching namespace/name. The Slack webhook is mounted from `slack-notifications` using `api_url_file`; never put a webhook URL in values or a Git commit. `scripts/seed_secret.py slack` prompts securely when bootstrapping.

Check these things in order when Slack notifications stop:

1. Alertmanager pod is ready and its configuration has loaded.
2. The Kubernetes secret exists in the expected namespace and has the `webhook` key.
3. Webhook has not been revoked/rotated in Slack; re-seed it privately if so.
4. Alertmanager logs show an outbound delivery failure or invalid configuration.
5. A real rule is firing and matches the configured route; a suppressed Watchdog is not evidence of broken notifications.

Do not send a test message to a real channel without coordinating with its users. No test alert is claimed to have been sent in this snapshot.

## 4.2 AWS-side alerts are a separate route

The data module defines CloudWatch alarms for SQS DLQ visible messages and oldest order-queue message age. An alarm publishes to an SNS topic encrypted by a customer-managed KMS key. SNS has an email subscription for the configured budget/operations email; the recipient must confirm the subscription link. Alarm `ok_actions` report recovery as well as firing. The topic policy restricts publishing to CloudWatch alarms in this account/region/project naming pattern.

EKS API, audit and authenticator logs are sent to CloudWatch with three-day retention. This is short lab retention; long-lived production audit evidence usually has centralized retention and access controls. AWS Budgets separately reports estimated/actual spend; it is delayed and cannot stop billing.

These are separate systems: **Prometheus Alertmanager → Slack** handles Kubernetes/app metrics; **CloudWatch Alarm → SNS email** handles selected AWS managed-service metrics. A working Slack connector does not prove SNS is configured, and vice versa.

## 4.3 Asynchronous order messaging: transactional outbox + SQS

The app handles order receipt work asynchronously:

1. Orders API writes the business order and an outbox event in the same PostgreSQL transaction. This avoids committing an order while losing the event between database and queue.
2. A publisher process reads unprocessed outbox rows and sends an event to `commerce-aws-order-paid` in SQS.
3. A worker receives the message, processes it, writes an inbox/idempotency record and receipt result, then deletes/acknowledges the message.
4. If processing repeatedly fails, SQS redrives it after five receives to the dead-letter queue (DLQ), retained for up to 14 days.
5. CloudWatch alerts if any DLQ message appears or if the order queue's oldest message exceeds five minutes for three evaluation periods.

**At-least-once delivery** means a message can be delivered more than once. Consumers must be idempotent: repeating a request should not create duplicate side effects. Visibility timeout hides a message while processing; it should exceed expected processing duration, and failed/slow work can become visible again. A DLQ preserves poison messages for diagnosis; it does not automatically fix/replay them.

Inspect queue metadata without reading message bodies:

```bash
aws sqs get-queue-attributes --queue-url QUEUE_URL --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed --region ap-south-1
aws cloudwatch describe-alarms --alarm-name-prefix commerce-aws --region ap-south-1
```

The SQS API calls available-message count `ApproximateNumberOfMessages`; CloudWatch uses `ApproximateNumberOfMessagesVisible`. Do not interchange API attribute names and CloudWatch metric names. See the [AWS CLI queue attribute reference](https://docs.aws.amazon.com/cli/latest/reference/sqs/get-queue-attributes.html).

A controlled DLQ exercise should use a non-customer test order, record the message ID/count, identify the failure, fix the consumer, redrive under a reviewed runbook, and confirm idempotency. Do not purge queues as a generic troubleshooting step.

IAM is split: the `session-publisher` Pod Identity role can only `sqs:SendMessage` to the paid queue; `session-worker` can receive/delete/change visibility on that queue. Each role has a permissions boundary and trust scoped to the named EKS cluster. This is safer than giving every application pod broad AWS credentials.

## 4.4 Secrets Manager, Pod Identity and External Secrets

A secret is sensitive configuration such as a database password or API credential. Git stores the **reference/ARN**, not the secret value. Terraform creates the secret resource and runtime JSON; AWS Secrets Manager stores the values. EKS Pod Identity provides temporary AWS credentials to the External Secrets Operator service account. The operator uses `SecretStore`/`ExternalSecret` resources in the Helm chart to copy the permitted remote value into a Kubernetes Secret consumed by workloads.

The secrets role can read only the runtime secret and RDS-generated master secret ARNs. Database bootstrap uses the master credential briefly to create a restricted `commerce_app` account. The application should use the app credential, never the master credential. Runtime database connection requires TLS validation against the bundled RDS root CA. The Secret value is not accessible through Git; Kubernetes Secrets are still sensitive and must be protected through RBAC, encryption and controlled diagnostics.

`deploy/environment.yaml` contains region and secret ARNs but currently says `enabled:false`. Those ARN identifiers may become stale after Terraform replacement; `scripts/platform.sh configure` generates current values from session outputs for a reviewed repository change. Never paste `aws secretsmanager get-secret-value` output into chat, CI logs or docs.

Troubleshoot without disclosing values:

```bash
kubectl --context commerce-aws -n commerce get secretstore,externalsecret
kubectl --context commerce-aws -n commerce describe externalsecret NAME
kubectl --context commerce-aws -n external-secrets logs deploy/external-secrets --tail=100
kubectl --context commerce-aws -n commerce get secret
kubectl --context commerce-aws -n commerce describe pod POD_NAME
```

If sync fails, check the ExternalSecret condition, AWS role association/service account, secret ARN/account/region, IAM boundary and Kubernetes namespace. Do not “fix” it by embedding the password in a values file.

## 4.5 DNS, TLS and ingress

DNS maps a hostname to a service endpoint. Cloudflare currently remains authoritative for `narx.space`; the design delegates `prod.narx.space` to Route 53. The delegated child zone is a bootstrap resource. DNS delegation is configured by NS records in the parent zone. Creating a second hosted zone does not itself delegate a name; parent NS records must point to the child nameservers.

For public HTTPS, an AWS Load Balancer Controller watches a Kubernetes Ingress and creates an ALB. ACM issues/manages the certificate; DNS validation proves domain control; Route 53 or the existing authoritative DNS publishes the validation and app records. TLS terminates at ALB, and ingress rules route to Kubernetes Services. Terraform configures ACM/DNS prerequisites and IAM; Argo installs the controller; the Kubernetes Ingress triggers controller-owned ALB resources. Ownership is intentionally split.

Current status: no active ALB, ACM certificate or shop record is claimed; ingress is disabled. The earlier certificate attempt failed because the apply IAM policy lacked `acm:RequestCertificate`. A permission change must be reviewed and merged before any cert plan/apply. DNS/TLS changes are external-facing and should be reviewed with domain ownership, zone, hostname, validation and cleanup impact understood.

## 4.6 Database recovery and safe diagnostics

RDS PostgreSQL stores durable users/orders. Redis stores cart/session state and is ephemeral relative to order records. RDS is private in database subnets and only allows PostgreSQL from the EKS cluster security group. The app uses a restricted DB user, SSL verification and a generated password in Secrets Manager.

The session resource has one-day automated backup retention but `skip_final_snapshot=true` on destroy. This is a deliberate learning-profile risk: an automated backup may expire and a destroy can remove the database without a final snapshot. Before data-bearing teardown, create a manual snapshot and verify it reaches `available`; record the ID privately. A recovery exercise restores to a new DB, updates generated secret references/config, verifies schema and app data, and only then routes traffic. Snapshot restores create billable resources.

This lab's last RDS was deleted without a final or manual snapshot. Its data is not recoverable from the described setup. Do not present it as a successful backup/restore test.

## 4.7 Runbook: diagnose a customer-impacting failure

Use a stable sequence:

1. **Scope:** Is this a deploy, one service, all services, AWS dependency or monitoring-only issue? Check current known environment and avoid assuming cluster exists.
2. **Desired state:** inspect merged release digest/config and Argo revision/status. Determine whether a bad release actually landed.
3. **Kubernetes:** inspect pods, events, readiness, restarts and recent logs. Avoid dumping environment variables or secret objects.
4. **Dependencies:** check RDS connectivity/SSL, Redis, SQS age/DLQ and ExternalSecret conditions.
5. **AWS:** verify caller/account/region; inspect EKS/RDS/ALB/volumes/alarms; check IAM CloudTrail event history for denied calls. Use read-only commands first.
6. **Mitigate:** use reviewed Git rollback to a known-good image digest/config. For infra incidents, do not apply speculative IAM wildcards.
7. **Communicate and learn:** record impact, timestamps, evidence, mitigation and follow-up. Add an alert only when it is actionable and has an owner/runbook.

Useful commands when the cluster exists:

```bash
kubectl --context commerce-aws get pods -A
kubectl --context commerce-aws get events -A --sort-by=.lastTimestamp
kubectl --context commerce-aws -n commerce get deploy,svc,hpa,ingress
kubectl --context commerce-aws -n commerce logs deploy/commerce-frontend --tail=200
kubectl --context commerce-aws -n commerce logs deploy/commerce-orders --all-containers --tail=200
kubectl --context commerce-aws -n argocd get applications
```

## 4.8 Learning exercises and interview explanations

1. **Metrics:** trace one ServiceMonitor to a target in Prometheus; explain scrape interval and retention.
2. **Alert:** explain why a warning is grouped, why Watchdog is suppressed, how a critical alert inhibits a warning, and where Slack credentials come from.
3. **Messaging:** force a test worker failure, observe retry and DLQ, fix it, then explain idempotent redrive. Never use real customer data.
4. **Identity:** draw the flow from GitHub OIDC to AWS role, and from Kubernetes service account to Pod Identity workload role. Explain why these are separate identities.
5. **Recovery:** plan and test a database snapshot restore, then document RPO (acceptable data loss window) and RTO (acceptable recovery time). No such test has been completed in this lab snapshot.
6. **Teardown:** explain why Kubernetes Ingress/PVC cleanup precedes EKS destroy and why retained ECR/state/DNS are reviewed separately.
7. **Interview statement:** “This lab demonstrates production patterns—PR gates, immutable signed images, least-privilege identities, Terraform state, GitOps, metrics and alerts—but it is deliberately single-AZ/single-node, uses short retention, and is not a highly available or production-ready service.”

## 4.9 Monitoring source walkthrough: from request to Slack

The application metric path is a chain of contracts:

1. A service exposes an HTTP metrics endpoint. Frontend/catalogue use `/metrics`; Java processes expose `/actuator/prometheus`.
2. A Kubernetes Service gives the pod endpoint a stable name/port and labels `app=commerce` plus `component=<name>`.
3. `deploy/chart/templates/monitoring.yaml` emits a `ServiceMonitor`. Its selector finds those Services; the `release: monitoring` label lets the Prometheus Operator's chart selector discover this monitor. `endpoints.port: http` must equal the Service's named port, not the numeric container port.
4. Prometheus scrapes every 30s. The relabeling changes metrics path only for components named orders/publisher/worker. Missing labels, wrong port name or path produces no target/metrics.
5. The `PrometheusRule` is selected by the operator and evaluates PromQL. A rule becomes pending while its `for` timer runs, then firing if the expression stays true.
6. Alertmanager groups by namespace and alert name, waits 30s to collect related alerts, then routes warning/critical to Slack. It sends resolved state too. A critical alert inhibits a warning with equal namespace/alertname, reducing duplicate notification. `Watchdog` goes to the `null` receiver.
7. Slack webhook is read from a mounted file sourced from the `slack-notifications` Secret. The URL never appears in Git values.

### What each alert expression means

| Rule | Condition and delay | Operator interpretation |
|---|---|---|
| `CommerceServiceDown` | `up{namespace="commerce"} == 0` continuously for 2m | A discovered scrape target is failing. If target is absent entirely, `up` series may disappear; inspect Prometheus Targets and discovery too. |
| `CommerceDeploymentUnavailable` | available replicas metric below 1 for 3m | A Deployment has no ready replica. On a small one-node cluster, resource exhaustion, image pull and dependency failures can cause this. |
| `CommerceHTTPErrorRate` | 5xx / total request rate > 5% for 5m, only when at least 20 requests occurred in 5m | Avoids firing on one isolated failure or a near-zero denominator. `clamp_min` prevents division by zero. Inspect latency, service and upstream dependency. |
| `CommerceOutboxStalled` | oldest outbox event age > 300s for 2m | API committed an event but publisher has not delivered it. Check publisher pods, DB, IAM and SQS errors. |
| `CommerceQueuePollingFailures` | more than five failed polls in five minutes for 2m | Worker repeatedly cannot poll; check Pod Identity, SQS role policy, network and queue URL. |

The values file configures retention and scrape cadence, not alert correctness. Six hours of retention helps a lab troubleshooting window but cannot support long-term trend analysis or compliance retention. Resource requests/limits protect the single node from unbounded monitoring memory, but alerts may be delayed if the node is under pressure.

### Metrics troubleshooting tree

- **No Prometheus target:** check ServiceMonitor selector/labels, namespace selector, Service labels, named port `http`, endpoint path, and operator logs.
- **Target is down:** check pod readiness, endpoint path/port, NetworkPolicy allowing monitoring ingress, TLS/auth settings if any, then pod logs.
- **No alert rule loaded:** check PrometheusRule label `release: monitoring`, rule namespace selection and Operator events.
- **Expression has no series:** check whether app is enabled, enough traffic exists, metric names/labels match source code, and PromQL labels (`namespace`, `status`, `result`) exist.
- **Alert fires but no Slack:** inspect Alertmanager route/config, secret key, webhook validity and delivery errors. Route matching uses alert labels; wrong severity can reach `null` receiver.
- **PVC pending:** check StorageClass `gp3`, EBS CSI controller health/role and AZ topology. EBS is AZ-bound; a pod cannot mount an EBS disk in a different AZ.

## 4.10 CloudWatch alarms: exact math and notification handshake

The DLQ alarm watches `AWS/SQS ApproximateNumberOfMessagesVisible` with queue-name dimension, maximum statistic over 60 seconds, one evaluation period, threshold greater than zero. One visible DLQ message triggers `ALARM`. The queue-age alarm watches `ApproximateAgeOfOldestMessage`, maximum over 60-second periods, three evaluation periods, threshold >300 seconds. It therefore needs persistent backlog age, rather than one brief spike.

For both alarms, missing metrics are treated as `notBreaching`, which avoids alerting just because a queue is idle/not yet publishing metrics. That also means a missing-data situation does not create an alarm; EKS/CloudWatch health must be monitored separately. `alarm_actions` publish state changes to SNS and `ok_actions` send recovery. `aws_sns_topic_policy` limits who may publish to the topic; KMS key policy allows CloudWatch to decrypt/generate data key only from this account. The email recipient must confirm SNS subscription once. An unconfirmed subscription does not receive notifications even if the alarm enters ALARM state.

To investigate, inspect alarm state/reason and queue attributes, then inspect worker logs and CloudTrail for denied API calls. Queue metric values are approximate and can lag. Do not use `ReceiveMessage` merely to check if a message exists: that changes its visibility/receipt behavior and can interfere with workers.

## 4.11 Queue and application consistency concepts

The database transaction and SQS publish are two different systems. A naïve implementation that writes the order, commits, then sends to SQS can crash between those operations. The transactional outbox writes both order and an outbox row in the same RDS transaction; a separate publisher retries delivery. After sending, a crash may cause the same event to be sent again, so the consumer must be idempotent.

An inbox/idempotency record stores the processed event key as part of the worker's database transaction. If SQS redelivers the same message, the worker sees the key and avoids repeating its side effect, then acknowledges the duplicate. The order is acknowledged only after database commit. This provides reliable at-least-once processing, not exactly-once delivery across independent systems.

The visibility timeout of 60s is longer than normal brief work; if processing exceeds it, another worker can receive the same message while the first still runs. `ChangeMessageVisibility` lets the consumer extend/release visibility, but the database idempotency guard remains necessary. `maxReceiveCount=5` is a poison-message limit, not a retry guarantee for every possible outage. DLQ message retention is 14 days; operators need a runbook to inspect/replay without losing causality.

## 4.12 External Secrets data path, field by field

1. `ExternalSecret` names `secretStoreRef: aws-runtime`; the `SecretStore` says use AWS Secrets Manager in `.Values.region`.
2. The `external-secrets` Kubernetes ServiceAccount is associated by Terraform with `commerce-aws-secrets` Pod Identity role.
3. Pod Identity agent obtains temporary credentials for the controller; AWS evaluates role trust, inline policy and boundary. Only specific secret ARN patterns are readable.
4. `dataFrom.extract` copies keys from the runtime JSON into Kubernetes Secret `commerce-runtime`; explicit `data.remoteRef.property=password` copies the master password into `commerce-db-admin` only.
5. Pods reference individual Secret keys using `secretKeyRef`. Environment values are injected when the container starts; updates to the Secret do not necessarily refresh already-running environment variables. Restart/rollout may be needed after rotation.
6. The bootstrap Job consumes both credentials to provision the restricted DB app user. Normal orders processes use only the app database credentials.

`refreshInterval: 5m` means ESO checks periodically. It is not an instantaneous push from Secrets Manager. `creationPolicy: Owner` means ESO manages the target Secret's lifecycle. When the ExternalSecret is removed, the owned Secret may also be removed; check resource ownership before manual cleanup.

## 4.13 DNS, certificate and ALB handshake

A hostname works only when each layer agrees:

1. The registered domain's authoritative DNS provider is Cloudflare today.
2. Cloudflare's parent zone has NS records for `prod.narx.space`, delegating that child to the four Route 53 nameservers. The child zone is a separate authority; parent records do not automatically copy into it.
3. ACM requests `shop.prod.narx.space` with DNS validation. Terraform creates a validation CNAME in the delegated zone and waits for ACM to issue the cert.
4. The Kubernetes Ingress includes the issued ACM ARN and hostname. The controller provisions an ALB with HTTPS listener and HTTP redirect.
5. A Route 53 A/AAAA alias in the delegated child zone points `shop.prod.narx.space` at the ALB DNS name/zone ID.
6. Browser sends TLS SNI/Host for that name, ACM cert matches it, ALB routes to healthy frontend pod targets, and application `publicOrigin`/secure cookie settings agree with the public URL.

Failure at any layer can look like “site is down”: NXDOMAIN is DNS/delegation; certificate pending is validation/permission; ALB exists with unhealthy targets is networking/readiness; redirect loop/mixed origin is app configuration. Check the layer-specific evidence before editing DNS. Current live status has no shop record/cert/ALB; ingress is disabled.

## 4.14 Python helpers from an operator's point of view

Python appears here because it is convenient for small, deterministic automation—not because the platform is secretly implemented in Python. You should understand the contract and side effects of each script, not memorize Python syntax.

- `changes.py`: maps file paths to build targets; a bad mapping could skip a necessary rebuild. Read its component dictionary and path-selection order.
- `release.py`: validates registry, component, digest, source and account/region; it is a gate against malformed promotion records.
- `check_chart.py`: performs render/schema assertions with temporary fixtures. It is part of CI and can download pinned schema files, but does not talk to AWS/Kubernetes.
- `inventory.py`: uses a constant list of read-only AWS CLI operations. It verifies account before queries, uses timeouts, records permission gaps and writes a private create-only report. Inspecting this is useful for understanding safe inventory design.
- `seed_secret.py`: accepts only two named secret types; asks for sensitive input with a hidden prompt and streams a manifest to `kubectl` stdin. Its process has real Kubernetes write authority, so context guard is essential.

A useful review checklist for any helper is: What inputs can a PR author control? Are they passed as data or executed as shell? Does the script have cloud credentials? What is the minimum permission? Where can secrets appear (argv, environment, logs, files, exceptions)? Does a timeout exist? What happens when a command fails halfway? What artifact is written and who owns its cleanup?

## 4.15 Learn operations through small failure drills

Run these only in a recreated disposable environment and use synthetic data:

1. **Scrape outage:** block one app endpoint in a temporary branch, observe target status and `CommerceServiceDown`, restore via Git, verify resolved notification.
2. **Queue backlog:** pause only the test worker, publish a test order, observe oldest-message age alarm, resume worker and observe recovery.
3. **DLQ:** in a test-only consumer path, cause repeated deterministic failure; inspect receive count and DLQ alarm. Fix and redrive a single test message; prove idempotency prevents duplicate receipt.
4. **Secret denial:** in a disposable role, remove a test-only permission and inspect ESO's condition/CloudTrail error. Restore the least-privilege action. Never broaden to `secretsmanager:*` on `*`.
5. **DNS/TLS:** in a non-public test domain, trace NS delegation, ACM validation and ALB target health separately. Do not experiment on the live `narx.space` parent records.
6. **Backup:** create a manual snapshot, wait for availability, restore into isolated capacity, verify a known synthetic order, and record elapsed recovery time and data-loss window.

Every drill has four parts: change one failure condition, identify which signal detects it, restore service through the owning control plane, then document the evidence. Do not claim a drill happened just because an alert or backup resource exists.

## Guided simulation: alerts, messages and recovery evidence

**These are fictional case studies. No message, alert or restore described here has been executed by writing this guide.** Pause at each decision and explain it before reading the answer.

### Case 1: order is saved but no receipt appears

Evidence:

```text
Orders API: requests succeed
Outbox oldest age: increasing
Paid SQS queue: no new messages
Publisher logs: AccessDenied on SendMessage
Worker: healthy
```

The event has not reached SQS. Restarting the worker or redriving the DLQ cannot recover an event that never entered the queue. Inspect publisher ServiceAccount, Pod Identity association, queue ARN/URL and the role's `sqs:SendMessage` permission/boundary. A healthy API does not imply the asynchronous path works.

After the scoped identity/configuration fix, the publisher should drain existing outbox work without requiring customers to place duplicate orders. Observe falling outbox age, messages reaching the queue, worker processing and the original order's receipt. A quiet alert alone is insufficient if metrics disappeared.

### Case 2: a message is delivered twice

The worker writes its receipt to the database, then crashes before acknowledging SQS. When visibility expires, the same event is delivered again.

**Predict the result:** an idempotent worker recognizes the event's stored processing key and avoids a second business side effect. It can acknowledge the duplicate after confirming the prior committed outcome. Without that check, a duplicate delivery could create duplicate receipts or other effects. SQS visibility timeout reduces simultaneous processing; it does not guarantee exactly-once execution.

The safe recovery question is “has this event's effect already committed?” Do not purge the queue to hide duplicates. Inspect event identifiers in appropriately restricted logs/data and preserve the relationship between source order, outbox event and receipt. Avoid publishing personal data to an alert channel.

### Case 3: the alert fires but Slack stays quiet

Evidence:

```text
Prometheus rule: firing
Alertmanager: receives alert
Alert labels: severity=info
Configured Slack route: severity warning or critical
Default receiver: null
```

The system is behaving according to its route. Rotating the webhook will not make `info` match a warning/critical route. Decide whether this condition deserves notification and adjust the rule/route under review. If severity already matched and delivery logs showed a webhook rejection, investigate the private webhook configuration instead.

Verify the whole chain: rule has data, expression becomes true for its configured duration, Alertmanager receives the alert, routing selects Slack, delivery succeeds, and a resolution notification arrives after recovery. Distinguish a silence, inhibition, grouping delay and delivery error; all can make a firing alert appear quiet for different reasons.

### Case 4: demonstrate a backup can restore useful data

Choose a synthetic order with a recorded timestamp and known expected status. Establish a backup time, restore into an isolated authorized target, connect the app/test client using that target's generated settings, and verify the record. Also verify a write/read operation and application schema compatibility; a DB status of `available` only establishes service readiness.

**Illustrative calculation:** a snapshot represents data at 14:00; failure occurs at 14:10; service is usable at 14:35 after restoration. Up to ten minutes of writes may be missing under this snapshot-only recovery, and measured recovery duration is 25 minutes from the declared incident start. These are illustrative observed outcomes, not agreed RPO/RTO targets. Compare them with requirements and record any missing data. A point-in-time restore capability can change the recovery choices, but it must be configured, retained and authorized.

Record snapshot identifier, source/target ownership, creation and recovery timestamps, verification queries without secret values, and cleanup decision for the temporary restore. A restore exercise can otherwise leave an expensive second database behind.

### Reader deliverable: explain a complete incident

Use this format with one of the cases:

```text
Impact: what could the customer not do?
Detection: which signal first showed it, and when?
Evidence: what observations support the suspected failing layer?
Alternative: what other explanation did you rule out, and how?
Mitigation: which reviewed change restored service?
Verification: which customer outcome and technical signals recovered?
Follow-up: what would prevent recurrence or shorten diagnosis?
```

Do not write “everything healthy” without naming the checks. Do not turn a plausible explanation into a confirmed cause without evidence. This discipline is as important as knowing the tools.
