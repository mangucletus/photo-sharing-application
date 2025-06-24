# Project configuration variables

# The name of the project, used for naming AWS resources (e.g., buckets, roles, functions)
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "photo-sharing-app"
}

# Deployment environment name, used to distinguish between different stages like development, staging, or production
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

# AWS region where all resources will be provisioned
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "eu-west-1"
}

# Optional custom domain name for accessing the application (e.g., www.example.com); can be empty if not used
variable "domain_name" {
  description = "Custom domain name (optional)"
  type        = string
  default     = ""
}

# Lambda configuration

# Maximum execution time for the Lambda function, in seconds (after which it will timeout if not completed)
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

# Memory allocated to the Lambda function in megabytes (affects performance and billing)
variable "lambda_memory" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 512
}

# Image processing configuration

# The maximum dimension (width or height) of the generated thumbnail in pixels
variable "thumbnail_size" {
  description = "Thumbnail size in pixels"
  type        = number
  default     = 150
}
