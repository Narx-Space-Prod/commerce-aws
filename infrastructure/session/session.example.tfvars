account_id         = "123456789012" # Replace; account allowlist prevents accidental cross-account operations.
region             = "ap-south-1"
availability_zones = ["ap-south-1a", "ap-south-1b"]
operator_cidrs     = ["203.0.113.10/32"] # Replace with your current public IP.
operator_role_arn  = "arn:aws:iam::123456789012:role/YourOperatorRole"
budget_email       = "you@example.com"
# Optional: use the delegated Route 53 production zone to provision and validate ACM.
# shop_hostname = "shop.prod.narx.space"
# route53_zone_id = "PRODUCTION_DNS_ZONE_ID_FROM_BOOTSTRAP_OUTPUT"
