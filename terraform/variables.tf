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
