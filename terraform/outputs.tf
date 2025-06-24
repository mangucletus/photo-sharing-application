# Output important resource information
output "images_bucket_name" {
  description = "Name of the S3 bucket for original images"
  value       = aws_s3_bucket.images.bucket
}

output "thumbnails_bucket_name" {
  description = "Name of the S3 bucket for thumbnails"
  value       = aws_s3_bucket.thumbnails.bucket
}

output "frontend_bucket_name" {
  description = "Name of the S3 bucket for frontend"
  value       = aws_s3_bucket.frontend.bucket
}

output "frontend_url" {
  description = "URL of the frontend website"
  value       = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}

output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.photo_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.environment}"
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.image_resizer.function_name
}

output "images_bucket_upload_url" {
  description = "Base URL for uploading images"
  value       = "https://${aws_s3_bucket.images.bucket}.s3.amazonaws.com"
}

output "thumbnails_bucket_url" {
  description = "Base URL for accessing thumbnails"
  value       = "https://${aws_s3_bucket.thumbnails.bucket}.s3.amazonaws.com"
}