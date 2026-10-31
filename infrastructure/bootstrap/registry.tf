variable "account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Supply the intended AWS account ID."
  }
}
variable "existing_github_oidc_provider_arn" {
  type    = string
  default = null
}
locals {
  repository         = "Narx-Space-Prod/commerce-aws"
  repository_subject = "Narx-Space-Prod@346206471/commerce-aws@1439227210"
  provider_arn       = coalesce(var.existing_github_oidc_provider_arn, try(aws_iam_openid_connect_provider.github[0].arn, null))
  ecr_names          = toset(["frontend", "catalogue", "orders", "cart"])
  ecr_arns           = [for name in sort(tolist(local.ecr_names)) : "arn:aws:ecr:${var.aws_region}:${var.account_id}:repository/commerce-aws/${name}"]
  publisher_statements = [
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = ["*"] },
    { Effect = "Allow", Resource = local.ecr_arns, Action = [
      "ecr:BatchGetImage", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"
    ] }
  ]
}
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.existing_github_oidc_provider_arn == null ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_ecr_repository" "component" {
  for_each             = local.ecr_names
  name                 = "commerce-aws/${each.key}"
  force_delete         = false
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  lifecycle { prevent_destroy = true }
}
resource "aws_iam_role" "publisher" {
  name                 = "commerce-aws-publisher"
  permissions_boundary = var.bootstrap_user_arn == null ? null : aws_iam_policy.publisher_boundary[0].arn
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRoleWithWebIdentity", Principal = { Federated = local.provider_arn },
    Condition = { StringEquals = {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub" = "repo:${local.repository_subject}:environment:registry-release"
    } }
  }] })
}
resource "aws_iam_role_policy" "publisher" {
  role   = aws_iam_role.publisher.id
  policy = jsonencode({ Version = "2012-10-17", Statement = local.publisher_statements })
}
resource "aws_s3_bucket_lifecycle_configuration" "plans" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-sensitive-infrastructure-plans"
    status = "Enabled"
    filter { prefix = "plans/" }
    expiration { days = 1 }
    noncurrent_version_expiration { noncurrent_days = 1 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}
output "release_role_arn" { value = aws_iam_role.publisher.arn }
output "ecr_repositories" { value = { for name, repo in aws_ecr_repository.component : name => repo.repository_url } }
