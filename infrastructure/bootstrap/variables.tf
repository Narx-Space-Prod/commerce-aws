variable "aws_region" {
  description = "AWS region selected after reviewing the deployment cost estimate."
  type        = string
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name reserved for Terraform state."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "Use 3–63 lowercase letters, digits and hyphens, beginning and ending with a letter or digit."
  }
}
