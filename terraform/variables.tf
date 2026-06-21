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
