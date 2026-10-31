variable "availability_zones" {
  type        = list(string)
  description = "Two distinct AZs for public and isolated database subnets; placement order is significant."
  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "Supply exactly two distinct availability zones."
  }
}
