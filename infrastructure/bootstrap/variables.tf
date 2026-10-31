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

variable "public_dns_zone_name" {
  description = "The public domain owned by this project. The Route 53 zone is retained in bootstrap state."
  type        = string
  default     = "narx.space"

  validation {
    condition     = var.public_dns_zone_name == "narx.space"
    error_message = "This bootstrap stack is authorized to manage only the narx.space public zone."
  }
}

variable "enable_production_subzone" {
  description = "Create and delegate prod.narx.space to Route 53 while Cloudflare remains authoritative for narx.space."
  type        = bool
  default     = false
}
