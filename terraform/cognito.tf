# terraform/cognito.tf - Simplified for React + email/password only

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${local.resource_prefix}-user-pool"

  # Password policy
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  # Use email as username
  username_attributes = ["email"]

  # Auto verify email
  auto_verified_attributes = ["email"]

  # Account recovery setting
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # User attribute update settings
  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  # Verification message template
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Verify your email for Photo Sharing App"
    email_message        = "Your verification code is {####}"
  }

  # Admin create user config - allow self-registration
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  # Schema for email attribute
  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  tags = {
    Name        = "${local.resource_prefix}-user-pool"
    Environment = var.environment
  }
}

# Cognito User Pool Client - Ultra-simplified for React
resource "aws_cognito_user_pool_client" "main" {
  name         = "${local.resource_prefix}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # No OAuth - pure email/password authentication
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = false

  # Enable auth flows needed for React/Amplify
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  # Token validity
  access_token_validity  = 24
  id_token_validity      = 24
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Security settings
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  # Attributes
  read_attributes  = ["email", "email_verified"]
  write_attributes = ["email"]

  # Remove callback/logout URLs for non-OAuth setup
  # callback_urls = []
  # logout_urls = []
}

# Identity Pool for AWS service access
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${local.resource_prefix}-identity-pool"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.main.id
    provider_name           = aws_cognito_user_pool.main.endpoint
    server_side_token_check = false
  }

  tags = {
    Name        = "${local.resource_prefix}-identity-pool"
    Environment = var.environment
  }
}

# IAM role for authenticated users
resource "aws_iam_role" "authenticated" {
  name = "${local.resource_prefix}-cognito-authenticated"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${local.resource_prefix}-cognito-authenticated-role"
    Environment = var.environment
  }
}

# IAM policy for authenticated users to access S3
resource "aws_iam_role_policy" "authenticated" {
  name = "${local.resource_prefix}-cognito-authenticated-policy"
  role = aws_iam_role.authenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.images.arn}/*",
          "${aws_s3_bucket.thumbnails.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.images.arn,
          aws_s3_bucket.thumbnails.arn
        ]
      }
    ]
  })
}

# Attach identity pool roles
resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    "authenticated" = aws_iam_role.authenticated.arn
  }
}