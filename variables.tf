variable "region" {
  type    = string
  default = "ap-south-1" # Mumbai: closest region to Bangalore
}

variable "environment" {
  type        = string
  description = "staging or production"
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "image_uri" {
  type        = string
  description = "Bootstrap image; the pipeline replaces it on every deploy."
  default     = "public.ecr.aws/docker/library/python:3.12-slim"
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "alarm_email" {
  type        = string
  description = "Email subscribed to the SNS alerts topic."
}

variable "certificate_arn" {
  type        = string
  default     = ""
  description = "ACM cert for HTTPS. Empty = HTTP only (acceptable for a demo, not for prod)."
}

variable "single_nat_gateway" {
  type        = bool
  default     = true
  description = "One NAT saves cost; set false in production for AZ-resilient egress."
}

variable "github_repository" {
  type        = string
  description = "owner/repo allowed to assume the deploy roles via OIDC."
}
