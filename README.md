# 📸 Serverless Photo Sharing Application

[![Deploy Photo Sharing App](https://github.com/your-username/photo-sharing-app/actions/workflows/deploy.yml/badge.svg)](https://github.com/your-username/photo-sharing-app/actions/workflows/deploy.yml)
[![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=flat&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=flat&logo=terraform&logoColor=white)](https://terraform.io/)

A complete serverless photo sharing application built with AWS services, managed through Infrastructure as Code (Terraform), and deployed via GitHub Actions CI/CD pipeline. Upload images, get automatic thumbnail generation, and share photos through a modern web interface.

## 📋 Table of Contents

- [Architecture Overview](#-architecture-overview)
- [System Flow](#-system-flow)
- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Quick Start Guide](#-quick-start-guide)
- [Detailed Setup](#-detailed-setup)
- [Project Structure](#-project-structure)
- [Configuration](#-configuration)
- [Deployment](#-deployment)
- [Monitoring & Troubleshooting](#-monitoring--troubleshooting)
- [Security](#-security)
- [Cost Analysis](#-cost-analysis)
- [Development](#-development)
- [Contributing](#-contributing)
- [FAQ](#-faq)

## 🏗️ Architecture Overview

### High-Level Architecture Diagram

```mermaid
graph TB
    subgraph "User Interface"
        UI[Web Browser]
    end
    
    subgraph "AWS Cloud"
        subgraph "Storage Layer"
            S3_IMG[S3 Bucket<br/>Original Images]
            S3_THUMB[S3 Bucket<br/>Thumbnails]
            S3_WEB[S3 Bucket<br/>Static Website]
        end
        
        subgraph "Compute Layer"
            LAMBDA[Lambda Function<br/>Image Resizer]
        end
        
        subgraph "API Layer"
            API[API Gateway<br/>REST API]
        end
        
        subgraph "Monitoring"
            CW[CloudWatch<br/>Logs & Metrics]
        end
        
        subgraph "Security"
            IAM[IAM Roles<br/>& Policies]
        end
    end
    
    subgraph "Infrastructure"
        TF[Terraform<br/>Infrastructure as Code]
        GHA[GitHub Actions<br/>CI/CD Pipeline]
    end
    
    UI --> S3_WEB
    UI --> S3_IMG
    UI --> API
    S3_IMG --> LAMBDA
    LAMBDA --> S3_THUMB
    API --> S3_THUMB
    LAMBDA --> CW
    IAM --> LAMBDA
    IAM --> API
    TF --> S3_IMG
    TF --> S3_THUMB
    TF --> S3_WEB
    TF --> LAMBDA
    TF --> API
    TF --> IAM
    GHA --> TF
```

### Component Breakdown

| Component | Service | Purpose | Region |
|-----------|---------|---------|---------|
| **Frontend** | S3 Static Website | Hosts the web application | eu-west-1 |
| **Image Storage** | S3 Bucket | Stores original uploaded images | eu-west-1 |
| **Thumbnail Storage** | S3 Bucket | Stores processed thumbnails | eu-west-1 |
| **Image Processing** | Lambda Function | Automatically resizes images | eu-west-1 |
| **API** | API Gateway | Serves images via REST API | eu-west-1 |
| **Monitoring** | CloudWatch | Logs and metrics collection | eu-west-1 |
| **Infrastructure** | Terraform | Infrastructure as Code | N/A |
| **CI/CD** | GitHub Actions | Automated deployment pipeline | N/A |

## 🔄 System Flow

### Image Upload & Processing Flow

```mermaid
sequenceDiagram
    participant User
    participant Frontend
    participant S3_Images
    participant Lambda
    participant S3_Thumbnails
    participant API_Gateway
    
    User->>Frontend: 1. Select/Drop Image
    Frontend->>Frontend: 2. Validate File Type
    Frontend->>S3_Images: 3. PUT /image.jpg
    S3_Images-->>Frontend: 4. Upload Success
    S3_Images->>Lambda: 5. S3 Event Trigger
    Lambda->>S3_Images: 6. Get Original Image
    Lambda->>Lambda: 7. Resize Image (PIL)
    Lambda->>S3_Thumbnails: 8. PUT /thumb-image.jpg
    Lambda-->>S3_Images: 9. Processing Complete
    Frontend->>API_Gateway: 10. GET /images/thumb-image.jpg
    API_Gateway->>S3_Thumbnails: 11. Fetch Thumbnail
    S3_Thumbnails-->>API_Gateway: 12. Return Image Data
    API_Gateway-->>Frontend: 13. Serve Image
    Frontend-->>User: 14. Display in Gallery
```

### Deployment Flow

```mermaid
flowchart TD
    A[Developer Push] --> B[GitHub Actions Triggered]
    B --> C{Branch Check}
    C -->|main| D[Terraform Plan]
    C -->|other| E[Security Scan Only]
    D --> F[Terraform Apply]
    F --> G[Deploy Lambda Code]
    G --> H[Update Frontend Config]
    H --> I[Upload to S3]
    I --> J[Deployment Complete]
    E --> K[Security Report]
    
    style A fill:#e1f5fe
    style J fill:#c8e6c9
    style K fill:#fff3e0
```

## ✨ Features

### Core Functionality
- **🖼️ Image Upload**: Drag & drop or click to upload multiple images
- **⚡ Auto-Resize**: Automatic thumbnail generation using AWS Lambda
- **📱 Responsive Gallery**: Modern, mobile-friendly photo gallery
- **🔍 Image Preview**: Full-size image modal preview
- **📊 Progress Tracking**: Real-time upload progress indicators
- **🚨 Error Handling**: Comprehensive error messages and recovery

### Technical Features
- **🏗️ Infrastructure as Code**: Complete Terraform configuration
- **🚀 CI/CD Pipeline**: Automated deployment with GitHub Actions
- **🔐 Security First**: IAM roles with least privilege access
- **📈 Monitoring**: CloudWatch integration for logs and metrics
- **💰 Cost Optimized**: Serverless architecture for minimal costs
- **🌍 Multi-Environment**: Support for dev/staging/prod environments

### Supported Formats
- **Images**: JPG, JPEG, PNG, GIF, BMP, TIFF, WebP
- **Max File Size**: 10MB per image
- **Batch Upload**: Up to 10 images simultaneously
- **Thumbnail Size**: 150x150 pixels (configurable)

## 📋 Prerequisites

### Required Accounts & Access
- [ ] **AWS Account** with programmatic access
- [ ] **GitHub Account** with repository access
- [ ] **Domain** (optional, for custom domain setup)

### Required Permissions
Your AWS user/role needs the following permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:*",
                "lambda:*",
                "iam:*",
                "apigateway:*",
                "logs:*",
                "cloudformation:*"
            ],
            "Resource": "*"
        }
    ]
}
```

### Local Development Tools (Optional)
- **Terraform** >= 1.5.0 ([Download](https://terraform.io/downloads))
- **AWS CLI** >= 2.0 ([Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
- **Node.js** >= 16.0 (for local testing)
- **Python** >= 3.9 (for Lambda development)

## 🚀 Quick Start Guide

### Option 1: Automated Setup (Recommended)

1. **Fork this repository** to your GitHub account

2. **Create Terraform State Bucket** (one-time setup):
   ```bash
   # Create a unique bucket name
   BUCKET_NAME="your-tf-state-$(date +%s)"
   
   # Create bucket
   aws s3 mb s3://$BUCKET_NAME --region eu-west-1
   
   # Enable versioning
   aws s3api put-bucket-versioning \
     --bucket $BUCKET_NAME \
     --versioning-configuration Status=Enabled
   
   # Enable server-side encryption
   aws s3api put-bucket-encryption \
     --bucket $BUCKET_NAME \
     --server-side-encryption-configuration '{
       "Rules": [{
         "ApplyServerSideEncryptionByDefault": {
           "SSEAlgorithm": "AES256"
         }
       }]
     }'
   ```

3. **Configure GitHub Secrets**:
   
   Go to your forked repository → Settings → Secrets and variables → Actions
   
   Add these secrets:
   ```
   AWS_ACCESS_KEY_ID=your_aws_access_key
   AWS_SECRET_ACCESS_KEY=your_aws_secret_key
   TF_STATE_BUCKET=your-tf-state-bucket-name
   ```

4. **Update Configuration**:
   
   Edit `terraform/main.tf`:
   ```hcl
   backend "s3" {
     bucket = "your-actual-bucket-name"  # Replace this line
     key    = "photo-sharing-app/terraform.tfstate"
     region = "eu-west-1"
     encrypt = true
   }
   ```

5. **Deploy**:
   ```bash
   git add .
   git commit -m "Initial deployment setup"
   git push origin main
   ```

6. **Access Your App**:
   
   After deployment completes (~5 minutes), check the GitHub Actions output for your app URL.

### Option 2: Manual Setup

<details>
<summary>Click to expand manual setup instructions</summary>

1. **Clone Repository**:
   ```bash
   git clone https://github.com/your-username/photo-sharing-app.git
   cd photo-sharing-app
   ```

2. **Configure AWS CLI**:
   ```bash
   aws configure
   # Enter your AWS Access Key ID, Secret Access Key, and region (eu-west-1)
   ```

3. **Initialize Terraform**:
   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

4. **Deploy Lambda**:
   ```bash
   cd ../lambda
   pip install -r requirements.txt -t .
   zip -r lambda_function.zip .
   
   # Get function name from Terraform output
   FUNCTION_NAME=$(cd ../terraform && terraform output -raw lambda_function_name)
   
   aws lambda update-function-code \
     --function-name $FUNCTION_NAME \
     --zip-file fileb://lambda_function.zip
   ```

5. **Deploy Frontend**:
   ```bash
   cd ../frontend
   
   # Get bucket names from Terraform
   IMAGES_BUCKET=$(cd ../terraform && terraform output -raw images_bucket_name)
   THUMBNAILS_BUCKET=$(cd ../terraform && terraform output -raw thumbnails_bucket_name)
   FRONTEND_BUCKET=$(cd ../terraform && terraform output -raw frontend_bucket_name)
   API_URL=$(cd ../terraform && terraform output -raw api_gateway_url)
   
   # Update configuration
   sed -i "s/{{IMAGES_BUCKET}}/${IMAGES_BUCKET}/g" index.html
   sed -i "s/{{THUMBNAILS_BUCKET}}/${THUMBNAILS_BUCKET}/g" index.html
   sed -i "s|{{API_GATEWAY_URL}}|${API_URL}|g" index.html
   
   # Upload to S3
   aws s3 sync . s3://${FRONTEND_BUCKET}/
   ```

</details>

## 📁 Project Structure

```
photo-sharing-app/
├── 📁 .github/
│   └── 📁 workflows/
│       └── 📄 deploy.yml              # GitHub Actions CI/CD pipeline
├── 📁 terraform/                      # Infrastructure as Code
│   ├── 📄 main.tf                     # Main Terraform configuration
│   ├── 📄 variables.tf                # Input variables
│   ├── 📄 outputs.tf                  # Output values
│   ├── 📄 s3.tf                       # S3 bucket configurations
│   ├── 📄 lambda.tf                   # Lambda function setup
│   ├── 📄 iam.tf                      # IAM roles and policies
│   ├── 📄 api_gateway.tf              # API Gateway configuration
│   └── 📄 terraform.tfvars            # Variable values
├── 📁 lambda/                         # AWS Lambda function
│   ├── 📄 image_resizer.py            # Main Lambda code
│   └── 📄 requirements.txt            # Python dependencies
├── 📁 frontend/                       # Web application
│   └── 📄 index.html                  # Single-page application
├── 📁 scripts/                        # Utility scripts
│   └── 📄 deploy-frontend.sh          # Frontend deployment script
├── 📁 docs/                           # Documentation
│   ├── 📄 ARCHITECTURE.md             # Detailed architecture docs
│   ├── 📄 API.md                      # API documentation
│   └── 📄 TROUBLESHOOTING.md          # Common issues and solutions
├── 📄 README.md                       # This file
├── 📄 LICENSE                         # MIT license
└── 📄 .gitignore                      # Git ignore rules
```

### Key Files Explained

| File | Purpose | Who Modifies |
|------|---------|--------------|
| `terraform/main.tf` | Core infrastructure definition | DevOps/Developers |
| `terraform/variables.tf` | Configurable parameters | DevOps/Developers |
| `lambda/image_resizer.py` | Image processing logic | Developers |
| `frontend/index.html` | User interface | Frontend Developers |
| `.github/workflows/deploy.yml` | CI/CD pipeline | DevOps |
| `terraform.tfvars` | Environment-specific config | DevOps |

## ⚙️ Configuration

### Environment Variables

#### Terraform Variables (`terraform/terraform.tfvars`)

```hcl
# Project Configuration
project_name = "photo-sharing-app"     # Change this to your project name
environment  = "prod"                  # Environment: dev, staging, prod
aws_region   = "eu-west-1"             # AWS region

# Lambda Configuration
lambda_timeout = 30                    # Timeout in seconds (max 900)
lambda_memory  = 512                   # Memory in MB (128-10240)

# Image Processing
thumbnail_size = 150                   # Thumbnail dimensions in pixels

# Optional Features
domain_name = ""                       # Custom domain (leave empty if not using)
enable_cloudfront = false              # CDN for better performance
enable_monitoring = true               # CloudWatch detailed monitoring
```

#### GitHub Secrets

Required secrets for GitHub Actions:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | AWS access key | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TF_STATE_BUCKET` | Terraform state bucket | `my-terraform-state-bucket` |

Optional secrets:

| Secret Name | Description | Default |
|-------------|-------------|---------|
| `SLACK_WEBHOOK` | Slack notifications | Not set |
| `CUSTOM_DOMAIN` | Custom domain name | Not set |

### Lambda Environment Variables

The Lambda function uses these environment variables (set automatically by Terraform):

| Variable | Description | Example |
|----------|-------------|---------|
| `THUMBNAIL_BUCKET` | S3 bucket for thumbnails | `photo-app-thumbnails-abc123` |
| `THUMBNAIL_SIZE` | Thumbnail size in pixels | `150` |

### Frontend Configuration

The frontend is configured during deployment by replacing placeholders:

| Placeholder | Replaced With | Description |
|-------------|---------------|-------------|
| `{{IMAGES_BUCKET}}` | Actual bucket name | Original images bucket |
| `{{THUMBNAILS_BUCKET}}` | Actual bucket name | Thumbnails bucket |
| `{{API_GATEWAY_URL}}` | API Gateway URL | REST API endpoint |

## 🚀 Deployment

### Automated Deployment (GitHub Actions)

The GitHub Actions workflow automatically:

1. **Validates** Terraform configuration
2. **Plans** infrastructure changes
3. **Applies** changes (on main branch only)
4. **Deploys** Lambda function code
5. **Updates** frontend configuration
6. **Uploads** frontend to S3
7. **Runs** security scans

#### Deployment Triggers

| Trigger | Action |
|---------|--------|
| Push to `main` | Full deployment |
| Push to other branches | Plan only |
| Pull Request | Security scan + Plan |

#### Deployment Stages

```mermaid
graph LR
    A[Code Push] --> B[Checkout Code]
    B --> C[Configure AWS]
    C --> D[Setup Terraform]
    D --> E[Terraform Init]
    E --> F[Terraform Plan]
    F --> G{Main Branch?}
    G -->|Yes| H[Terraform Apply]
    G -->|No| I[Plan Only]
    H --> J[Deploy Lambda]
    J --> K[Deploy Frontend]
    K --> L[Success ✅]
    I --> M[Plan Complete]
    
    style A fill:#e3f2fd
    style L fill:#c8e6c9
    style M fill:#fff3e0
```

### Manual Deployment

<details>
<summary>Manual deployment steps</summary>

#### 1. Infrastructure Deployment

```bash
cd terraform

# Initialize Terraform (first time only)
terraform init

# Review planned changes
terraform plan -var-file="terraform.tfvars"

# Apply changes
terraform apply -var-file="terraform.tfvars"

# Get outputs
terraform output
```

#### 2. Lambda Deployment

```bash
cd lambda

# Install dependencies
pip install -r requirements.txt -t .

# Create deployment package
zip -r ../lambda_function.zip . -x "*.pyc" "__pycache__/*"

# Deploy to Lambda
aws lambda update-function-code \
  --function-name $(cd ../terraform && terraform output -raw lambda_function_name) \
  --zip-file fileb://../lambda_function.zip \
  --region eu-west-1
```

#### 3. Frontend Deployment

```bash
cd frontend

# Get Terraform outputs
IMAGES_BUCKET=$(cd ../terraform && terraform output -raw images_bucket_name)
THUMBNAILS_BUCKET=$(cd ../terraform && terraform output -raw thumbnails_bucket_name)
FRONTEND_BUCKET=$(cd ../terraform && terraform output -raw frontend_bucket_name)
API_GATEWAY_URL=$(cd ../terraform && terraform output -raw api_gateway_url)

# Update configuration
sed -i "s/{{IMAGES_BUCKET}}/${IMAGES_BUCKET}/g" index.html
sed -i "s/{{THUMBNAILS_BUCKET}}/${THUMBNAILS_BUCKET}/g" index.html
sed -i "s|{{API_GATEWAY_URL}}|${API_GATEWAY_URL}|g" index.html

# Deploy to S3
aws s3 sync . s3://${FRONTEND_BUCKET}/ --delete
```

</details>

### Environment Management

#### Multiple Environments

To deploy multiple environments (dev, staging, prod):

1. **Create separate tfvars files**:
   ```bash
   cp terraform.tfvars terraform-dev.tfvars
   cp terraform.tfvars terraform-prod.tfvars
   ```

2. **Modify environment-specific values**:
   ```hcl
   # terraform-dev.tfvars
   environment = "dev"
   lambda_memory = 256
   thumbnail_size = 100
   
   # terraform-prod.tfvars
   environment = "prod"
   lambda_memory = 512
   thumbnail_size = 150
   ```

3. **Deploy with specific configuration**:
   ```bash
   terraform apply -var-file="terraform-dev.tfvars"
   ```

## 📊 Monitoring & Troubleshooting

### CloudWatch Dashboards

The application automatically creates CloudWatch logs for:

- **Lambda Function**: `/aws/lambda/photo-sharing-app-prod-image-resizer`
- **API Gateway**: API Gateway execution logs
- **S3 Access**: S3 server access logs (optional)

### Key Metrics to Monitor

| Metric | Normal Range | Alert Threshold |
|--------|--------------|-----------------|
| Lambda Duration | < 5 seconds | > 25 seconds |
| Lambda Errors | 0% | > 1% |
| Lambda Memory Usage | < 80% | > 90% |
| S3 4xx Errors | < 1% | > 5% |
| API Gateway Latency | < 500ms | > 2s |

### Common Issues & Solutions

#### 1. Lambda Timeout Errors

**Symptoms**: Images not appearing in thumbnails bucket
**Causes**: Large images, insufficient memory
**Solutions**:
- Increase `lambda_timeout` in `terraform.tfvars`
- Increase `lambda_memory` for faster processing
- Check image size limits

```bash
# Check Lambda logs
aws logs tail /aws/lambda/photo-sharing-app-prod-image-resizer --follow

# Update Lambda configuration
terraform apply -var="lambda_timeout=60" -var="lambda_memory=1024"
```

#### 2. S3 Access Denied

**Symptoms**: Upload failures, "Access Denied" errors
**Causes**: Incorrect bucket policies, IAM permissions
**Solutions**:
- Verify bucket policies in `terraform/s3.tf`
- Check IAM role permissions
- Ensure bucket names are unique

```bash
# Check bucket policy
aws s3api get-bucket-policy --bucket your-bucket-name

# Test S3 access
aws s3 ls s3://your-bucket-name/
```

#### 3. Frontend Not Loading

**Symptoms**: Blank page, configuration errors
**Causes**: Incorrect bucket configuration, missing placeholders
**Solutions**:
- Check S3 website configuration
- Verify placeholder replacement
- Enable S3 static website hosting

```bash
# Check website configuration
aws s3api get-bucket-website --bucket your-frontend-bucket

# Verify file content
aws s3 cp s3://your-frontend-bucket/index.html - | grep -E "{{|}}"
```

#### 4. API Gateway Errors

**Symptoms**: Images not loading from API
**Causes**: Incorrect API configuration, S3 integration issues
**Solutions**:
- Check API Gateway integration
- Verify S3 bucket permissions
- Test API endpoints directly

```bash
# Test API endpoint
curl -I https://your-api-id.execute-api.eu-west-1.amazonaws.com/prod/images/thumb-test.jpg

# Check API Gateway logs
aws logs describe-log-groups --log-group-name-prefix "/aws/apigateway/"
```

### Debugging Tools

#### Terraform State Inspection

```bash
# List all resources
terraform state list

# Show specific resource
terraform state show aws_lambda_function.image_resizer

# Refresh state
terraform refresh
```

#### AWS CLI Debugging

```bash
# Enable debug mode
export AWS_CLI_DEBUG=1

# Test S3 access
aws s3 ls --debug

# Test Lambda invoke
aws lambda invoke \
  --function-name photo-sharing-app-prod-image-resizer \
  --payload '{"test": true}' \
  response.json
```

### Log Analysis

#### Lambda Logs

```bash
# Tail logs in real-time
aws logs tail /aws/lambda/photo-sharing-app-prod-image-resizer --follow

# Filter error logs
aws logs filter-events \
  --log-group-name /aws/lambda/photo-sharing-app-prod-image-resizer \
  --filter-pattern "ERROR"

# Get logs for specific time range
aws logs filter-events \
  --log-group-name /aws/lambda/photo-sharing-app-prod-image-resizer \
  --start-time $(date -d '1 hour ago' +%s)000
```

## 🔐 Security

### Security Best Practices Implemented

#### 1. **IAM Least Privilege**
- Lambda execution role has minimal required permissions
- API Gateway role limited to specific S3 bucket access
- No wildcard permissions in production

#### 2. **S3 Security**
- Public access blocked by default for source images
- Bucket policies restrict access to specific resources
- Server-side encryption enabled
- Versioning enabled for backup/recovery

#### 3. **API Security**
- CORS configured for secure cross-origin requests
- No authentication required for public image viewing
- Rate limiting through API Gateway

#### 4. **Network Security**
- All communication over HTTPS
- Lambda runs in AWS managed VPC
- No custom VPC required (serverless architecture)

### Security Scanning

The project includes automated security scanning:

#### GitHub Actions Security Scan

```yaml
# .github/workflows/deploy.yml
- name: Run Terraform Security Scan
  uses: aquasecurity/trivy-action@master
  with:
    scan-type: 'config'
    scan-ref: './terraform'
```

#### Manual Security Checks

```bash
# Scan Terraform configurations
docker run --rm -v $(pwd):/workspace \
  aquasec/trivy config /workspace/terraform

# Check for secrets in code
git secrets --scan

# Validate IAM policies
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::account:role/lambda-role \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::bucket/*
```

### Compliance Considerations

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| **Data Encryption** | S3 server-side encryption | ✅ Implemented |
| **Access Logging** | CloudWatch integration | ✅ Implemented |
| **Audit Trail** | CloudTrail (customer setup) | ⚠️ Optional |
| **Data Backup** | S3 versioning | ✅ Implemented |
| **Access Control** | IAM roles and policies | ✅ Implemented |

### Security Hardening Checklist

- [ ] Enable AWS CloudTrail for audit logging
- [ ] Set up AWS Config for compliance monitoring
- [ ] Implement AWS WAF for API Gateway (optional)
- [ ] Enable GuardDuty for threat detection
- [ ] Set up billing alerts for cost monitoring
- [ ] Review and rotate AWS access keys regularly
- [ ] Implement backup and disaster recovery plan

## 💰 Cost Analysis

### Cost Breakdown

#### Monthly Cost Estimation (Moderate Usage)

| Service | Usage | Cost per Month |
|---------|-------|----------------|
| **S3 Storage** | 10GB images + 1GB thumbnails | $0.25 |
| **S3 Requests** | 10K PUT, 50K GET | $0.05 |
| **Lambda** | 1K executions, 512MB, 3s avg | $0.01 |
| **API Gateway** | 50K requests | $0.18 |
| **CloudWatch** | Basic monitoring | $0.01 |
| **Data Transfer** | 5GB out | $0.45 |
| **Total** | | **~$0.95/month** |

#### Cost Optimization Tips

1. **Storage Optimization**:
   ```hcl
   # Enable S3 Intelligent Tiering
   lifecycle_configuration {
     rule {
       id     = "intelligent_tiering"
       status = "Enabled"
       
       transition {
         days          = 30
         storage_class = "INTELLIGENT_TIERING"
       }
     }
   }
   ```

2. **Lambda Optimization**:
   - Reduce memory if processing smaller images
   - Optimize image processing code
   - Use provisioned concurrency for high traffic

3. **API Gateway Optimization**:
   - Implement caching for frequently accessed images
   - Use CloudFront CDN for global distribution

#### Cost Monitoring

```bash
# Set up billing alerts
aws budgets create-budget \
  --account-id 123456789012 \
  --budget '{
    "BudgetName": "PhotoSharingApp",
    "BudgetLimit": {
      "Amount": "10",
      "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }'
```

### Scaling Costs

| Users | Images/Month | Storage | Requests | Est. Cost |
|-------|--------------|---------|----------|-----------|
| 10 | 100 | 1GB | 1K | $1 |
| 100 | 1,000 | 10GB | 10K | $3 |
| 1,000 | 10,000 | 100GB | 100K | $25 |
| 10,000 | 100,000 | 1TB | 1M | $200 |

## 🛠️ Development

### Local Development Setup

#### Prerequisites

```bash
# Install Python dependencies
pip install -r lambda/requirements.txt

# Install Node.js for frontend testing
npm install -g http-server

# Install development tools
pip install pytest black flake8
```

#### Testing Lambda Locally

```python
# test_lambda.py
import json
import boto3
from moto import mock_s3
from lambda.image_resizer import lambda_handler

@mock_s3
def test_lambda_handler():
    # Setup mock S3
    s3 = boto3.client('s3', region_name='eu-west-1')
    s3.create_bucket(
        Bucket='test-bucket',
        CreateBucketConfiguration={'LocationConstraint': 'eu-west-1'}
    )
    
    # Test event
    event = {
        'Records': [{
            's3': {
                'bucket': {'name': 'test-bucket'},
                'object': {'key': 'test-image.jpg'}
            }
        }]
    }
    
    # Test lambda function
    result = lambda_handler(event, {})
    assert result['statusCode'] == 200
```

#### Running Tests

```bash
# Run Lambda tests
cd lambda
python -m pytest test_lambda.py -v

# Code formatting
black image_resizer.py

# Linting
flake8 image_resizer.py
```

#### Frontend Development

```bash
# Serve frontend locally
cd frontend
python -m http.server 8000

# Open in browser
open http://localhost:8000
```

### Contributing Guidelines

#### Code Style

- **Python**: Follow PEP 8, use Black formatter
- **JavaScript**: Use ES6+, semicolons required
- **Terraform**: Use consistent naming, add comments
- **Documentation**: Update README for any changes

#### Pull Request Process

1. **Fork** the repository
2. **Create** feature branch: `git checkout -b feature/new-feature`
3. **Commit** changes: `git commit -m 'Add new feature'`
4. **Test** thoroughly (automated tests will run)
5. **Submit** pull request with detailed description

#### Testing Requirements

- [ ] Lambda function tests pass
- [ ] Terraform validates successfully
- [ ] Security scan passes
- [ ] Documentation updated
- [ ] Manual testing completed

### Customization Examples

#### Adding Image Filters

```python
# lambda/image_resizer.py
from PIL import ImageFilter, ImageEnhance

def apply_filters(image):
    """Apply filters to image"""
    # Add blur effect
    if os.environ.get('ENABLE_BLUR', 'false').lower() == 'true':
        image = image.filter(ImageFilter.GaussianBlur(radius=1))
    
    # Enhance contrast
    if os.environ.get('ENHANCE_CONTRAST', 'false').lower() == 'true':
        enhancer = ImageEnhance.Contrast(image)
        image = enhancer.enhance(1.2)
    
    return image

# In lambda_handler, before thumbnail creation:
image = apply_filters(image)
```

#### Adding Multiple Thumbnail Sizes

```python
# lambda/image_resizer.py
def create_multiple_thumbnails(image, source_key, target_bucket):
    """Create thumbnails in multiple sizes"""
    sizes = [
        (150, 150, 'thumb'),
        (300, 300, 'medium'),
        (600, 600, 'large')
    ]
    
    for width, height, prefix in sizes:
        # Create copy of original image
        thumb = image.copy()
        thumb.thumbnail((width, height), Image.Resampling.LANCZOS)
        
        # Save to buffer
        buffer = io.BytesIO()
        thumb.save(buffer, "JPEG", quality=85, optimize=True)
        buffer.seek(0)
        
        # Upload to S3
        target_key = f"{prefix}-{source_key}"
        s3.put_object(
            Bucket=target_bucket,
            Key=target_key,
            Body=buffer.getvalue(),
            ContentType="image/jpeg"
        )
```

#### Adding User Authentication

```hcl
# terraform/cognito.tf
resource "aws_cognito_user_pool" "photo_users" {
  name = "${local.resource_prefix}-users"
  
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  
  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "photo_client" {
  name         = "${local.resource_prefix}-client"
  user_pool_id = aws_cognito_user_pool.photo_users.id
  
  generate_secret                      = false
  prevent_user_existence_errors       = "ENABLED"
  explicit_auth_flows                 = ["ADMIN_NO_SRP_AUTH"]
  supported_identity_providers        = ["COGNITO"]
}
```

#### Adding DynamoDB for Metadata

```hcl
# terraform/dynamodb.tf
resource "aws_dynamodb_table" "photo_metadata" {
  name           = "${local.resource_prefix}-metadata"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "photo_id"
  
  attribute {
    name = "photo_id"
    type = "S"
  }
  
  attribute {
    name = "user_id"
    type = "S"
  }
  
  global_secondary_index {
    name     = "user-index"
    hash_key = "user_id"
  }
  
  tags = {
    Name = "${local.resource_prefix}-metadata"
  }
}
```

## 🤖 Advanced Features

### CloudFront CDN Integration

```hcl
# terraform/cloudfront.tf
resource "aws_cloudfront_distribution" "photo_cdn" {
  origin {
    domain_name = aws_s3_bucket.thumbnails.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.thumbnails.bucket}"
    
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }
  
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.thumbnails.bucket}"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    
    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for ${local.resource_prefix}"
}
```

### Auto-Scaling with SQS

```hcl
# terraform/sqs.tf
resource "aws_sqs_queue" "image_processing" {
  name                      = "${local.resource_prefix}-processing"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 1209600
  receive_wait_time_seconds = 10
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "dlq" {
  name = "${local.resource_prefix}-dlq"
}

# Lambda event source mapping
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.image_processing.arn
  function_name    = aws_lambda_function.image_resizer.arn
  batch_size       = 10
}
```

### Monitoring & Alerting

```hcl
# terraform/monitoring.tf
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.resource_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  
  dimensions = {
    FunctionName = aws_lambda_function.image_resizer.function_name
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_sns_topic" "alerts" {
  name = "${local.resource_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
```

## 📚 API Documentation

### REST API Endpoints

#### GET /images/{image}

Retrieve a thumbnail image.

**Parameters:**
- `image` (path): Image filename (e.g., `thumb-photo.jpg`)

**Response:**
- `200 OK`: Returns image binary data
- `404 Not Found`: Image doesn't exist
- `403 Forbidden`: Access denied

**Example:**
```bash
curl https://api-id.execute-api.eu-west-1.amazonaws.com/prod/images/thumb-sunset.jpg
```

#### S3 Direct Upload

Upload images directly to S3 bucket.

**Endpoint:** `https://bucket-name.s3.amazonaws.com/`

**Method:** `PUT`

**Headers:**
- `Content-Type`: Image MIME type

**Example:**
```javascript
const uploadToS3 = async (file) => {
  const url = `https://${IMAGES_BUCKET}.s3.amazonaws.com/${file.name}`;
  
  const response = await fetch(url, {
    method: 'PUT',
    body: file,
    headers: {
      'Content-Type': file.type
    }
  });
  
  return response.ok;
};
```

### Frontend API

#### JavaScript Functions

```javascript
// Upload single file
async function uploadSingleFile(file)

// Load gallery images
async function loadGallery()

// Display images in gallery
function displayImages(images)

// Show/hide progress
function showProgress(show)

// Show user messages
function showMessage(message, type)
```

### Lambda Function API

#### Environment Variables

| Variable | Type | Description |
|----------|------|-------------|
| `THUMBNAIL_BUCKET` | string | Target S3 bucket for thumbnails |
| `THUMBNAIL_SIZE` | number | Thumbnail size in pixels |

#### Event Structure

```json
{
  "Records": [{
    "s3": {
      "bucket": {
        "name": "source-bucket-name"
      },
      "object": {
        "key": "uploaded-image.jpg"
      }
    }
  }]
}
```

#### Response Structure

```json
{
  "statusCode": 200,
  "body": "{\"message\": \"Thumbnail created successfully\"}"
}
```

## 🚨 FAQ

### General Questions

**Q: How much does this application cost to run?**
A: For moderate usage (1000 images/month), expect $1-5/month. Costs scale with usage.

**Q: Can I use a custom domain?**
A: Yes, set the `domain_name` variable in `terraform.tfvars` and configure DNS.

**Q: Is this production-ready?**
A: Yes, with proper monitoring and backups. Consider adding authentication for production use.

**Q: What image formats are supported?**
A: JPG, PNG, GIF, BMP, TIFF, WebP. The Lambda function converts all to JPEG thumbnails.

### Technical Questions

**Q: Why does image processing take time?**
A: Lambda functions have cold start delays. Consider provisioned concurrency for faster response.

**Q: Can I process videos?**
A: Not with this setup. You'd need different tools like FFmpeg in a container.

**Q: How do I backup my images?**
A: S3 versioning is enabled. Consider cross-region replication for disaster recovery.

**Q: Can I run this in a different AWS region?**
A: Yes, update the `aws_region` variable in `terraform.tfvars`.

### Troubleshooting Questions

**Q: Images upload but thumbnails don't appear**
A: Check Lambda logs in CloudWatch. Common issues: timeout, memory limits, or PIL installation.

**Q: "Access Denied" errors during upload**
A: Verify S3 bucket policies and CORS configuration.

**Q: Terraform fails with "bucket already exists"**
A: S3 bucket names must be globally unique. The random suffix should prevent this.

**Q: GitHub Actions deployment fails**
A: Check that AWS credentials are correctly set in GitHub Secrets.

### Customization Questions

**Q: How do I change thumbnail size?**
A: Update `thumbnail_size` in `terraform.tfvars` and redeploy.

**Q: Can I add user authentication?**
A: Yes, implement AWS Cognito. See the customization examples above.

**Q: How do I add image filters?**
A: Modify the Lambda function to use PIL filters. See development examples.

**Q: Can I support multiple thumbnail sizes?**
A: Yes, modify the Lambda function to create multiple sizes. See customization examples.

## 📄 License

MIT License

Copyright (c) 2024 Your Name

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Contributors

- Your Name ([@yourusername](https://github.com/yourusername)) - Initial work

## 📞 Support

- **Documentation**: Check this README and the `docs/` folder
- **Issues**: Open a GitHub issue for bugs or feature requests
- **Discussions**: Use GitHub Discussions for questions
- **Email**: your-email@example.com (for private inquiries)

## 🔗 Links

- **🚀 Live Application**: [Photo Sharing App](http://photo-sharing-app-prod-frontend-1xbg8k73.s3-website.eu-west-1.amazonaws.com/)
- [AWS Documentation](https://docs.aws.amazon.com/)
- [Terraform Documentation](https://terraform.io/docs)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [PIL Documentation](https://pillow.readthedocs.io/)

---

**Made with ❤️ by [Cletus Nehinlalei Mangu](https://github.com/mangucletus)**

*Star ⭐ this repository if you found it helpful!*