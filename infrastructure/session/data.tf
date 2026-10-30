resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = aws_subnet.database[*].id
}
data "aws_rds_engine_version" "postgres" {
  engine                 = "postgres"
  parameter_group_family = "postgres17"
  latest                 = true
}
resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-"
  family      = "postgres17"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_db_instance" "this" {
  identifier                   = var.name
  engine                       = "postgres"
  engine_version               = data.aws_rds_engine_version.postgres.version
  parameter_group_name         = aws_db_parameter_group.this.name
  instance_class               = "db.t4g.micro"
  allocated_storage            = 20
  max_allocated_storage        = 25
  storage_type                 = "gp3"
  storage_encrypted            = true
  db_name                      = "commerce"
  username                     = "commerce"
  manage_master_user_password  = true
  snapshot_identifier          = var.existing_backup_snapshot
  db_subnet_group_name         = aws_db_subnet_group.this.name
  vpc_security_group_ids       = [aws_security_group.database.id]
  availability_zone            = var.availability_zones[0]
  multi_az                     = false
  publicly_accessible          = false
  backup_retention_period      = 1
  auto_minor_version_upgrade   = true
  deletion_protection          = false
  skip_final_snapshot          = true
  delete_automated_backups     = true
  apply_immediately            = true
  performance_insights_enabled = false
  # Session teardown is intentionally destructive. Make and verify a MANUAL snapshot first.
}
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dead-letter"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}
resource "aws_sqs_queue" "paid" {
  name                       = "${var.name}-order-paid"
  visibility_timeout_seconds = 60
  receive_wait_time_seconds  = 10
  sqs_managed_sse_enabled    = true
  redrive_policy             = jsonencode({ deadLetterTargetArn = aws_sqs_queue.dlq.arn, maxReceiveCount = 5 })
}
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url            = aws_sqs_queue.dlq.url
  redrive_allow_policy = jsonencode({ redrivePermission = "byQueue", sourceQueueArns = [aws_sqs_queue.paid.arn] })
}
resource "random_password" "session" {
  length  = 64
  special = false
}
resource "random_password" "database" {
  length  = 48
  special = false
}
resource "aws_secretsmanager_secret" "runtime" {
  name_prefix             = "${var.name}-runtime-"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "runtime" {
  secret_id = aws_secretsmanager_secret.runtime.id
  secret_string = jsonencode({
    DATABASE_URL  = "jdbc:postgresql://${aws_db_instance.this.address}:5432/commerce?sslmode=verify-full&sslrootcert=/app/certs/global-bundle.pem"
    DATABASE_USER = "commerce_app", DATABASE_PASSWORD = random_password.database.result,
    DATABASE_HOST = aws_db_instance.this.address, SESSION_SECRET = random_password.session.result,
    REDIS_URL     = "redis://commerce-redis:6379", DELIVERY_QUEUE_URL = aws_sqs_queue.paid.url
  })
}
locals {
  pod_trust = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "pods.eks.amazonaws.com" }, Action = ["sts:AssumeRole", "sts:TagSession"],
    Condition = { StringEquals = { "aws:RequestTag/eks-cluster-arn" = "arn:aws:eks:${var.region}:${var.account_id}:cluster/${var.name}" } }
  }] })
}
resource "aws_iam_role" "delivery" {
  for_each           = toset(["publisher", "worker"])
  name               = "${var.name}-${each.key}"
  assume_role_policy = local.pod_trust
}
resource "aws_iam_role_policy" "delivery" {
  for_each = aws_iam_role.delivery
  role     = each.value.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Resource = aws_sqs_queue.paid.arn,
    Action = each.key == "publisher" ? ["sqs:SendMessage"] : ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility"]
  }] })
}
resource "aws_eks_pod_identity_association" "delivery" {
  for_each        = aws_iam_role.delivery
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "commerce"
  service_account = "commerce-${each.key}"
  role_arn        = each.value.arn
}
resource "aws_iam_role" "secrets" {
  name               = "${var.name}-secrets"
  assume_role_policy = local.pod_trust
}
resource "aws_iam_role_policy" "secrets" {
  role = aws_iam_role.secrets.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect   = "Allow", Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
    Resource = [aws_secretsmanager_secret.runtime.arn, aws_db_instance.this.master_user_secret[0].secret_arn]
  }] })
}
resource "aws_eks_pod_identity_association" "secrets" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.secrets.arn
}
