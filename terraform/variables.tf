# Project configuration variables
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "photo-sharing-app"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "eu-west-1"
}

variable "domain_name" {
  description = "Custom domain name (optional)"
  type        = string
  default     = ""
}

# Lambda configuration
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 512
}

# Image processing configuration
variable "thumbnail_size" {
  description = "Thumbnail size in pixels"
  type        = number
  default     = 150
}