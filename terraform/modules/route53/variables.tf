variable "domain_name" {
  description = "Existing public Route 53 domain name."
  type        = string
}

variable "app_subdomain" {
  description = "Subdomain used by the Express app."
  type        = string
  default     = "app"
}

variable "grafana_subdomain" {
  description = "Subdomain used by Grafana. Defaults to the requested graphana spelling."
  type        = string
  default     = "graphana"
}

variable "certificate_domain_name" {
  description = "Existing ACM certificate domain name to use for the app load balancer."
  type        = string
  default     = null
}
