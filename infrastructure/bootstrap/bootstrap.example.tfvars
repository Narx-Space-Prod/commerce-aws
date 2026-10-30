account_id        = "123456789012"
aws_region        = "ap-south-1"
state_bucket_name = "replace-with-globally-unique-state-bucket"
# If this account already has GitHub OIDC, reuse it instead of creating a duplicate:
# existing_github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
budget_email = "you@example.com"
budget_usd   = 10 # Alert only, not a spend cap.
