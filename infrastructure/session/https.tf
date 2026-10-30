variable "shop_hostname" {
  description = "Optional real shop subdomain, such as shop.example.com. Uses an existing Route 53 public zone."
  type        = string
  default     = null
}
variable "route53_zone_id" {
  description = "Existing public hosted zone for ACM DNS validation. No domain is purchased."
  type        = string
  default     = null
  validation {
    condition     = var.shop_hostname == null || var.route53_zone_id != null
    error_message = "Provide the existing hosted-zone ID when enabling ACM certificate creation."
  }
}
resource "aws_acm_certificate" "shop" {
  count             = var.shop_hostname == null ? 0 : 1
  domain_name       = var.shop_hostname
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}
resource "aws_route53_record" "certificate" {
  count   = var.shop_hostname == null ? 0 : 1
  zone_id = var.route53_zone_id
  name    = tolist(aws_acm_certificate.shop[0].domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.shop[0].domain_validation_options)[0].resource_record_type
  records = [tolist(aws_acm_certificate.shop[0].domain_validation_options)[0].resource_record_value]
  ttl     = 60
}
resource "aws_acm_certificate_validation" "shop" {
  count                   = var.shop_hostname == null ? 0 : 1
  certificate_arn         = aws_acm_certificate.shop[0].arn
  validation_record_fqdns = [aws_route53_record.certificate[0].fqdn]
}
output "certificate_arn" {
  value = try(aws_acm_certificate_validation.shop[0].certificate_arn, null)
}
