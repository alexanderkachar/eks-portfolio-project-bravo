output "domain_name" {
  description = "Route 53 domain name."
  value       = local.domain_name
}

output "hosted_zone_id" {
  description = "Existing public hosted zone ID."
  value       = data.aws_route53_zone.this.zone_id
}

output "hosted_zone_arn" {
  description = "Existing public hosted zone ARN."
  value       = "arn:aws:route53:::hostedzone/${data.aws_route53_zone.this.zone_id}"
}

output "certificate_arn" {
  description = "Existing ACM certificate ARN for the app hostname."
  value       = data.aws_acm_certificate.app.arn
}

output "app_hostname" {
  description = "Public hostname for the Express app."
  value       = local.app_hostname
}

output "grafana_hostname" {
  description = "Public hostname for Grafana."
  value       = local.grafana_hostname
}
