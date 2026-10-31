# Optional, root-created identity foundation. Import these four IAM objects before
# using this role to apply the bootstrap stack. The role cannot rewrite its own
# permissions or the publisher boundary, and cannot provision EC2/EKS/RDS.
variable "bootstrap_user_arn" {
  description = "Existing non-root IAM user allowed to assume the scoped bootstrap role with MFA."
  type        = string
  default     = null
  validation {
    condition     = var.bootstrap_user_arn == null ? true : can(regex("^arn:aws:iam::${var.account_id}:user/[A-Za-z0-9+=,.@_/-]+$", var.bootstrap_user_arn))
    error_message = "Use one concrete IAM user ARN in the selected account, never root or a wildcard."
  }
}
locals {
  bootstrap_role_name = "commerce-aws-bootstrap"
  boundary_arn        = "arn:aws:iam::${var.account_id}:policy/commerce-aws-publisher-boundary"
  publisher_arn       = "arn:aws:iam::${var.account_id}:role/commerce-aws-publisher"
  bootstrap_trust = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { AWS = var.bootstrap_user_arn }, Action = "sts:AssumeRole",
    Condition = { Bool = { "aws:MultiFactorAuthPresent" = "true" } }
  }] })
  bootstrap_writes = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "StateStorage", Effect = "Allow", Resource = ["arn:aws:s3:::${var.state_bucket_name}", "arn:aws:s3:::${var.state_bucket_name}/*"], Action = [
      "s3:CreateBucket", "s3:PutBucketVersioning", "s3:PutBucketOwnershipControls", "s3:PutBucketPublicAccessBlock",
      "s3:PutEncryptionConfiguration", "s3:PutBucketPolicy", "s3:PutLifecycleConfiguration", "s3:PutBucketTagging",
      "s3:PutObject", "s3:DeleteObject", "s3:DeleteObjectVersion"
    ] },
    { Sid = "ProjectRegistry", Effect = "Allow", Resource = local.ecr_arns, Action = [
      "ecr:CreateRepository", "ecr:PutImageScanningConfiguration", "ecr:PutImageTagMutability",
      "ecr:TagResource", "ecr:UntagResource", "ecr:PutLifecyclePolicy", "ecr:DeleteLifecyclePolicy"
    ] },
    { Sid    = "ProjectBudget", Effect = "Allow", Resource = ["arn:aws:budgets::${var.account_id}:budget/commerce-aws"],
      Action = ["budgets:ModifyBudget", "budgets:TagResource", "budgets:UntagResource"]
    },
    # Route 53 does not support resource-level authorization for CreateHostedZone.
    # Keep this single operation separate; the role cannot delete zones or change
    # DNS records. Terraform's prevent_destroy retains the one reviewed public zone.
    { Sid = "CreateReviewedPublicZone", Effect = "Allow", Resource = ["*"], Action = ["route53:CreateHostedZone"] },
    { Sid = "TagHostedZones", Effect = "Allow", Resource = ["arn:aws:route53:::hostedzone/*"], Action = ["route53:ChangeTagsForResource"] },
    { Sid = "GitHubIdentityProvider", Effect = "Allow", Resource = ["arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"], Action = [
      "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider", "iam:TagOpenIDConnectProvider", "iam:UntagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint", "iam:AddClientIDToOpenIDConnectProvider", "iam:RemoveClientIDFromOpenIDConnectProvider"
    ] },
    { Sid       = "CreateBoundedPublisher", Effect = "Allow", Resource = [local.publisher_arn],
      Action    = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"],
      Condition = { StringEquals = { "iam:PermissionsBoundary" = local.boundary_arn } }
    },
    { Sid = "ManageBoundedPublisher", Effect = "Allow", Resource = [local.publisher_arn], Action = [
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:UpdateAssumeRolePolicy", "iam:UpdateRole", "iam:DeleteRole",
      "iam:TagRole", "iam:UntagRole"
    ] }
  ] })
}
resource "aws_iam_policy" "publisher_boundary" {
  count       = var.bootstrap_user_arn == null ? 0 : 1
  name        = "commerce-aws-publisher-boundary"
  description = "Maximum ECR permissions for the Commerce publisher"
  policy      = jsonencode({ Version = "2012-10-17", Statement = local.publisher_statements })
}
resource "aws_iam_role" "bootstrap" {
  count                = var.bootstrap_user_arn == null ? 0 : 1
  name                 = local.bootstrap_role_name
  description          = "MFA-protected Commerce foundation setup only"
  max_session_duration = 3600
  assume_role_policy   = local.bootstrap_trust
}
resource "aws_iam_role_policy_attachment" "bootstrap_read" {
  count      = var.bootstrap_user_arn == null ? 0 : 1
  role       = aws_iam_role.bootstrap[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
resource "aws_iam_role_policy" "bootstrap_write" {
  count  = var.bootstrap_user_arn == null ? 0 : 1
  name   = "bootstrap-resources"
  role   = aws_iam_role.bootstrap[0].id
  policy = local.bootstrap_writes
}
output "bootstrap_access_documents" {
  description = "Non-secret JSON for one-time root-console setup, followed by Terraform import."
  value = var.bootstrap_user_arn == null ? null : {
    role_name                      = local.bootstrap_role_name
    role_description               = aws_iam_role.bootstrap[0].description
    trust                          = jsondecode(local.bootstrap_trust)
    write_policy                   = jsondecode(local.bootstrap_writes)
    publisher_boundary             = jsondecode(aws_iam_policy.publisher_boundary[0].policy)
    publisher_boundary_name        = aws_iam_policy.publisher_boundary[0].name
    publisher_boundary_description = aws_iam_policy.publisher_boundary[0].description
    tags                           = { Project = "commerce-aws", Environment = "bootstrap", Owner = "platform-engineering", ManagedBy = "terraform" }
  }
}
