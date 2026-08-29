variable "project_name" {
  type = string
}

variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "digital-app"
}

variable "image_tag_mutability" {
  description = "MUTABLE or IMMUTABLE"
  default     = "IMMUTABLE"
}

variable "max_image_count" {
  description = "Keep only the N most recent images (lifecycle policy) to control storage cost"
  type        = number
  default     = 10
}