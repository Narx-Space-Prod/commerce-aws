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
  repository   = "Narx-Space-Prod/commerce-aws"
  provider_arn = coalesce(var.existing_github_oidc_provider_arn, try(aws_iam_openid_connect_provider.github[0].arn, null))
}
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.existing_github_oidc_provider_arn == null ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_ecr_repository" "component" {
  for_each             = toset(["frontend", "catalogue", "orders", "cart"])
  name                 = "commerce-aws/${each.key}"
  force_delete         = false
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  lifecycle { prevent_destroy = true }
}
resource "aws_iam_role" "publisher" {
  name = "commerce-aws-publisher"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRoleWithWebIdentity", Principal = { Federated = local.provider_arn },
    Condition = { StringEquals = {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub" = "repo:${local.repository}:environment:registry-release"
    } }
  }] })
}
resource "aws_iam_role_policy" "publisher" {
  role = aws_iam_role.publisher.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" },
    { Effect = "Allow", Resource = [for repo in aws_ecr_repository.component : repo.arn], Action = [
      "ecr:BatchGetImage", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"
    ] }
  ] })
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
