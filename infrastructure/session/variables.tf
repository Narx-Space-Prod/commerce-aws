variable "account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Supply the intended 12-digit AWS account ID."
  }
}
variable "region" {
  type    = string
  default = "ap-south-1"
}
variable "name" {
  type    = string
  default = "commerce-aws"
  validation {
    condition     = var.name == "commerce-aws"
    error_message = "This environment's reviewed IAM boundaries require the commerce-aws resource prefix."
  }
}
variable "availability_zones" {
  type = list(string)
  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "EKS requires two different AZs. Workers and the database use the first AZ."
  }
}
variable "operator_cidrs" {
  description = "Public IPv4 /32 addresses allowed to reach the EKS API. No SSH access is opened."
  type        = list(string)
  validation {
    condition     = length(var.operator_cidrs) > 0 && alltrue([for cidr in var.operator_cidrs : can(cidrnetmask(cidr)) && endswith(cidr, "/32")])
    error_message = "Provide explicit operator IPv4 /32 addresses; never 0.0.0.0/0."
  }
}
variable "operator_role_arn" {
  description = "Existing IAM role used by the human operator, not an STS session ARN."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.operator_role_arn))
    error_message = "Use a real IAM role ARN."
  }
}
variable "kubernetes_version" {
  type    = string
  default = "1.35"
}
variable "instance_type" {
  type    = string
  default = "m7i-flex.large"
}
variable "existing_backup_snapshot" {
  description = "Optional manual RDS snapshot identifier for a restore exercise or a new session."
  type        = string
  default     = null
}
variable "budget_email" {
  type = string
  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.budget_email))
    error_message = "Supply the email to receive AWS budget and infrastructure alarm notifications."
  }
}
