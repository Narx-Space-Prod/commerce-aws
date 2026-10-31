variable "name" {
  type        = string
  description = "Cluster and IAM role prefix; the current reviewed boundaries require commerce-aws."
  validation {
    condition     = var.name == "commerce-aws"
    error_message = "The reviewed IAM boundary policies require the commerce-aws prefix."
  }
}
variable "account_id" {
  type        = string
  description = "AWS account that owns the workload permission boundaries."
}
variable "region" {
  type        = string
  description = "AWS region used in workload trust policies and controller configuration."
}
variable "operator_cidrs" {
  type        = list(string)
  description = "Explicit operator IPv4 /32 addresses permitted to reach the public EKS API."
  validation {
    condition     = length(var.operator_cidrs) > 0 && alltrue([for cidr in var.operator_cidrs : can(cidrnetmask(cidr)) && endswith(cidr, "/32")])
    error_message = "Supply explicit operator IPv4 /32 addresses."
  }
}
variable "operator_role_arn" {
  type        = string
  description = "Human operator IAM role granted cluster administration; use an IAM ARN, not an STS session ARN."
}
variable "kubernetes_version" {
  type        = string
  description = "Reviewed Kubernetes version in EKS standard support."
}
variable "instance_type" {
  type        = string
  description = "x86 EC2 instance type used by the single-AZ managed worker group."
}
variable "public_subnet_ids" {
  type        = list(string)
  description = "Two public subnet IDs; the worker uses the first subnet and EKS uses both."
  validation {
    condition     = length(var.public_subnet_ids) == 2 && length(distinct(var.public_subnet_ids)) == 2
    error_message = "Supply two distinct public subnet IDs."
  }
}
variable "load_balancer_policy_json" {
  type        = string
  description = "Reviewed upstream Load Balancer Controller IAM policy document supplied by the caller."
}
