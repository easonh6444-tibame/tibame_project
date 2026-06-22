variable "app_image_tag" {
  description = "The tag of the image to deploy"
  type        = string
  default     = "latest"
}

variable "enable_compute" {
  description = "Whether to create compute resources (ECS/Cloud Run)"
  type        = bool
  default     = false
}

variable "app_domain" {
  description = "Custom domain fronted by the GCP HTTPS load balancer"
  type        = string
  default     = "buy0050.xyz"
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for app_domain (not secret)"
  type        = string
  default     = "2b5f3803c6e3e11d3cf6e6a908a7a0cd"
}

variable "stock_bucket" {
  description = "GCS bucket for persisting stock price history"
  type        = string
  default     = "ckc101-13-stock-data"
}
