output "load_balancer_arn" {
  description = "Application load balancer ARN."
  value       = aws_lb.this.arn
}

output "load_balancer_dns_name" {
  description = "Application load balancer DNS name."
  value       = aws_lb.this.dns_name
}

output "security_group_id" {
  description = "Application load balancer security group ID."
  value       = aws_security_group.this.id
}

output "target_group_arn" {
  description = "Target group ARN for the app TargetGroupBinding."
  value       = aws_lb_target_group.this.arn
}

output "grafana_target_group_arn" {
  description = "Target group ARN for the Grafana TargetGroupBinding."
  value       = aws_lb_target_group.grafana.arn
}
