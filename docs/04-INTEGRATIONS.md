# 4. Integrations handbook: monitoring, messaging, secrets and operations

This chapter connects the services around the application. It teaches what each integration does, where its configuration lives, how data/credentials flow, and how to investigate failures without exposing secrets.

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

Grafana credentials are seeded from a local prompt by `scripts/seed_secret.py grafana`; the secret is not checked into Git. Avoid commands that print Secret YAML or values. If login fails, check the correct context/namespace/secret existence and pod events without displaying the password.

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
aws sqs get-queue-attributes --queue-url QUEUE_URL --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesVisible --region ap-south-1
aws cloudwatch describe-alarms --alarm-name-prefix commerce-aws --region ap-south-1
```

A controlled DLQ exercise should use a non-customer test order, record the message ID/count, identify the failure, fix the consumer, redrive under a reviewed runbook, and confirm idempotency. Do not purge queues as a generic troubleshooting step.

IAM is split: the `session-publisher` Pod Identity role can only `sqs:SendMessage` to the paid queue; `session-worker` can receive/delete/change visibility on that queue. Each role has a permissions boundary and trust scoped to the named EKS cluster. This is safer than giving every application pod broad AWS credentials.

## 4.4 Secrets Manager, Pod Identity and External Secrets

A secret is sensitive configuration such as a database password or API credential. Git stores the **reference/ARN**, not the secret value. Terraform creates the secret resource and runtime JSON; AWS Secrets Manager stores the values. EKS Pod Identity provides temporary AWS credentials to the External Secrets Operator service account. The operator uses `SecretStore`/`ExternalSecret` resources in the Helm chart to copy the permitted remote value into a Kubernetes Secret consumed by workloads.

The secrets role can read only the runtime secret and RDS-generated master secret ARNs. Database bootstrap uses the master credential briefly to create a restricted `commerce_app` account. The application should use the app credential, never the master credential. Runtime database connection requires TLS validation against the bundled RDS root CA. The Secret value is not accessible through Git; Kubernetes Secrets are still sensitive and must be protected through RBAC, encryption and controlled diagnostics.

`deploy/environment.yaml` contains region and secret ARNs but currently says `enabled:false`. Those ARN identifiers may become stale after Terraform replacement; `scripts/platform.sh configure` generates current values from session outputs for a reviewed repository change. Never paste `aws secretsmanager get-secret-value` output into chat, CI logs or docs.

Troubleshoot without disclosing values:

```bash
kubectl --context commerce-aws -n external-secrets get secretstore,externalsecret
kubectl --context commerce-aws -n external-secrets describe externalsecret NAME
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
