variable "name" {
  type        = string
  description = "Database, queue and IAM role prefix; current workload boundaries require commerce-aws."
  validation {
    condition     = var.name == "commerce-aws"
    error_message = "The reviewed IAM boundary policies require the commerce-aws prefix."
  }
}
variable "account_id" {
  type        = string
  description = "AWS account used in Pod Identity trust and notification policies."
}
variable "region" {
  type        = string
  description = "AWS region used in policy resource ARNs."
}
variable "availability_zones" {
  type        = list(string)
  description = "Two AZs in network placement order; the database runs in the first."
  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "Supply exactly two distinct availability zones."
  }
}
variable "budget_email" {
  type        = string
  description = "Email recipient for SNS infrastructure alarms; the subscription must be confirmed."
}
variable "existing_backup_snapshot" {
  type        = string
  description = "Optional recovery snapshot identifier; null creates a fresh database. Restore authorization requires separate review."
}
variable "vpc_id" {
  type        = string
  description = "VPC in which to create the private database security group."
}
variable "database_subnet_ids" {
  type        = list(string)
  description = "Two isolated subnet IDs for the database subnet group."
  validation {
    condition     = length(var.database_subnet_ids) == 2 && length(distinct(var.database_subnet_ids)) == 2
    error_message = "Supply two distinct isolated database subnet IDs."
  }
}
variable "cluster_security_group_id" {
  type        = string
  description = "EKS security group allowed to connect to PostgreSQL on port 5432."
}
variable "cluster_name" {
  type        = string
  description = "Existing EKS cluster receiving the data workload Pod Identity associations."
}
