mock_provider "aws" {
  mock_data "aws_rds_engine_version" {
    defaults = { version = "17.7" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test-role" }
  }
  mock_resource "aws_db_instance" {
    defaults = { master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:ap-south-1:123456789012:secret:rds-test", kms_key_id = "test", secret_status = "active" }] }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:ap-south-1:123456789012:operations" }
  }
  mock_resource "aws_sqs_queue" {
    defaults = { arn = "arn:aws:sqs:ap-south-1:123456789012:queue", url = "https://sqs.ap-south-1.amazonaws.com/123456789012/queue" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:ap-south-1:123456789012:key/01234567-89ab-cdef-0123-456789abcdef" }
  }
}
mock_provider "random" {}
variables {
  account_id         = "123456789012"
  availability_zones = ["ap-south-1a", "ap-south-1b"]
  operator_cidrs     = ["203.0.113.10/32"]
  operator_role_arn  = "arn:aws:iam::123456789012:role/Operator"
  budget_email       = "operator@example.com"
}
run "security_boundaries" {
  command = apply
  assert {
    condition = (
      aws_iam_role.cluster.permissions_boundary == "arn:aws:iam::123456789012:policy/commerce-aws-cluster-boundary" &&
      aws_iam_role.node.permissions_boundary == "arn:aws:iam::123456789012:policy/commerce-aws-node-boundary" &&
      aws_iam_role.cni.permissions_boundary == "arn:aws:iam::123456789012:policy/commerce-aws-cni-boundary" &&
      aws_iam_role.storage.permissions_boundary == "arn:aws:iam::123456789012:policy/commerce-aws-storage-boundary" &&
      aws_iam_role.ingress.permissions_boundary == "arn:aws:iam::123456789012:policy/commerce-aws-ingress-boundary" &&
      aws_iam_role.secrets.permissions_boundary == "arn:aws:iam::123456789012:policy/commerce-aws-secrets-boundary" &&
      alltrue([for key, role in aws_iam_role.delivery : role.permissions_boundary == "arn:aws:iam::123456789012:policy/commerce-aws-session-${key}-boundary"])
    )
    error_message = "Every workload role must retain its own reviewed boundary."
  }
  assert {
    condition = (
      toset([for specification in aws_launch_template.node.tag_specifications : specification.resource_type]) == toset(["instance", "volume", "network-interface"]) &&
      alltrue([for specification in aws_launch_template.node.tag_specifications : specification.tags["Project"] == "commerce-aws"])
    )
    error_message = "The managed node's instances, volumes and interfaces need project ownership tags at creation."
  }
  assert {
    condition     = aws_db_instance.this.storage_encrypted && !aws_db_instance.this.publicly_accessible && !aws_db_instance.this.multi_az
    error_message = "The learning DB must be encrypted, private and single-AZ."
  }
  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access && aws_eks_cluster.this.vpc_config[0].public_access_cidrs == toset(["203.0.113.10/32"])
    error_message = "The EKS API requires private node access and an operator-only public allowlist."
  }
  assert {
    condition     = aws_launch_template.node.metadata_options[0].http_tokens == "required" && aws_launch_template.node.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "Require IMDSv2 and prevent ordinary pods using node-role credentials."
  }
  assert {
    condition     = aws_iam_role.delivery["publisher"].name == "commerce-aws-session-publisher" && aws_iam_role.delivery["worker"].name == "commerce-aws-session-worker"
    error_message = "Session delivery roles must not collide with the retained ECR publisher role."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.delivery["publisher"].policy).Statement[0].Action == ["sqs:SendMessage"]
    error_message = "The publisher must not consume or delete messages."
  }
  assert {
    condition     = !contains(jsondecode(aws_iam_role_policy.delivery["worker"].policy).Statement[0].Action, "sqs:SendMessage")
    error_message = "The worker must not publish messages."
  }
  assert {
    condition     = aws_db_instance.this.backup_retention_period >= 1 && aws_eks_cluster.this.upgrade_policy[0].support_type == "STANDARD"
    error_message = "Keep database backups and avoid silently entering paid EKS extended support."
  }
}
run "reject_public_api" {
  command = plan
  variables { operator_cidrs = ["0.0.0.0/0"] }
  expect_failures = [var.operator_cidrs]
}
