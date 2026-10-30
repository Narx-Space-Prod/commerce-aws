mock_provider "aws" {}
variables {
  account_id        = "123456789012"
  budget_email      = "operator@example.com"
  aws_region        = "ap-south-1"
  state_bucket_name = "commerce-aws-test-state"
}
run "retained_foundation" {
  command = apply
  assert {
    condition     = aws_budgets_budget.session.cost_types[0].include_tax && !aws_budgets_budget.session.cost_types[0].include_credit
    error_message = "Tax must count toward the budget; promotional credits must not mask gross resource usage."
  }
  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled" && !aws_s3_bucket.state.force_destroy
    error_message = "Retain versioned Terraform state across sessions."
  }
  assert {
    condition     = alltrue([for repo in aws_ecr_repository.component : repo.image_tag_mutability == "IMMUTABLE" && !repo.force_delete])
    error_message = "Release tags are immutable and repository destruction must fail when images remain."
  }
  assert {
    condition     = jsondecode(aws_iam_role.publisher.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:Narx-Space-Prod/commerce-aws:environment:registry-release"
    error_message = "Only the protected registry-release environment may publish."
  }
}
