locals {
  domain_name             = trimsuffix(var.domain_name, ".")
  certificate_domain_name = coalesce(var.certificate_domain_name, "*.${local.domain_name}")
  app_hostname            = "${var.app_subdomain}.${local.domain_name}"
}

data "aws_route53_zone" "this" {
  name         = "${local.domain_name}."
  private_zone = false
}

data "aws_acm_certificate" "app" {
  domain      = local.certificate_domain_name
  statuses    = ["ISSUED"]
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}
