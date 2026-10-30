variable "budget_email" {
  type = string
}
variable "budget_usd" {
  type    = number
  default = 8
  validation {
    condition     = var.budget_usd > 0
    error_message = "The warning threshold must be positive; it is not a spending cap."
  }
}
resource "aws_budgets_budget" "session" {
  name         = "commerce-aws"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  cost_types {
    include_tax    = true
    include_credit = false
    include_refund = false
  }
  # Account-wide budget so untagged costs are not silently excluded.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}
