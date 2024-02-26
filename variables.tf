variable "project_id" {
  description = "The project ID"
  type        = string
}

variable "region" {
  description = "The region"
  type        = string
}

variable "vpc_count" {
  description = "Number of VPCs to create"
  type        = number
  default     = 1
}

variable "image_name" {
  description = "Name of the custom image"
  type        = string
}

