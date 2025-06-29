#!/bin/bash
# scripts/import-existing-resources.sh
# Script to import existing AWS resources into Terraform state

set -e

echo "🔄 Importing existing AWS resources into Terraform state..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to safely import a resource
import_resource() {
    local resource_type=$1
    local resource_name=$2
    local aws_resource_id=$3
    
    echo -e "${YELLOW}Importing ${resource_type}.${resource_name}...${NC}"
    
    # Check if resource already exists in state
    if terraform state show "${resource_type}.${resource_name}" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ ${resource_type}.${resource_name} already in state${NC}"
        return 0
    fi
    
    # Try to import the resource
    if terraform import "${resource_type}.${resource_name}" "${aws_resource_id}" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Successfully imported ${resource_type}.${resource_name}${NC}"
    else
        echo -e "${RED}❌ Failed to import ${resource_type}.${resource_name} - might not exist${NC}"
    fi
}

# Get current environment and project prefix
ENVIRONMENT=$(terraform output -raw environment 2>/dev/null || echo "prod")
PROJECT_PREFIX="photo-sharing-app-${ENVIRONMENT}"

echo "Environment: ${ENVIRONMENT}"
echo "Project Prefix: ${PROJECT_PREFIX}"

# Import CloudWatch Log Group
echo -e "\n${YELLOW}📊 Importing CloudWatch Log Group...${NC}"
import_resource "aws_cloudwatch_log_group" "api_gateway_logs" "/aws/apigateway/${PROJECT_PREFIX}"

# Import IAM Role (API Gateway)
echo -e "\n${YELLOW}🔐 Importing IAM Roles...${NC}"
import_resource "aws_iam_role" "api_gateway_role" "${PROJECT_PREFIX}-api-gateway-role"

# Import IAM Policies
import_resource "aws_iam_role_policy" "api_gateway_policy" "${PROJECT_PREFIX}-api-gateway-role:${PROJECT_PREFIX}-api-gateway-policy"

# Import existing S3 buckets if they exist
echo -e "\n${YELLOW}🪣 Checking for existing S3 buckets...${NC}"

# Get bucket names from AWS
IMAGES_BUCKET=$(aws s3 ls | grep "${PROJECT_PREFIX}-images" | awk '{print $3}' | head -1)
THUMBNAILS_BUCKET=$(aws s3 ls | grep "${PROJECT_PREFIX}-thumbnails" | awk '{print $3}' | head -1)
FRONTEND_BUCKET=$(aws s3 ls | grep "${PROJECT_PREFIX}-frontend" | awk '{print $3}' | head -1)

if [ ! -z "$IMAGES_BUCKET" ]; then
    echo "Found images bucket: $IMAGES_BUCKET"
    import_resource "aws_s3_bucket" "images" "$IMAGES_BUCKET"
    import_resource "aws_s3_bucket_versioning" "images" "$IMAGES_BUCKET"
    import_resource "aws_s3_bucket_public_access_block" "images" "$IMAGES_BUCKET"
    import_resource "aws_s3_bucket_cors_configuration" "images" "$IMAGES_BUCKET"
fi

if [ ! -z "$THUMBNAILS_BUCKET" ]; then
    echo "Found thumbnails bucket: $THUMBNAILS_BUCKET"
    import_resource "aws_s3_bucket" "thumbnails" "$THUMBNAILS_BUCKET"
    import_resource "aws_s3_bucket_versioning" "thumbnails" "$THUMBNAILS_BUCKET"
    import_resource "aws_s3_bucket_public_access_block" "thumbnails" "$THUMBNAILS_BUCKET"
    import_resource "aws_s3_bucket_cors_configuration" "thumbnails" "$THUMBNAILS_BUCKET"
fi

if [ ! -z "$FRONTEND_BUCKET" ]; then
    echo "Found frontend bucket: $FRONTEND_BUCKET"
    import_resource "aws_s3_bucket" "frontend" "$FRONTEND_BUCKET"
    import_resource "aws_s3_bucket_public_access_block" "frontend" "$FRONTEND_BUCKET"
    import_resource "aws_s3_bucket_website_configuration" "frontend" "$FRONTEND_BUCKET"
    import_resource "aws_s3_bucket_cors_configuration" "frontend" "$FRONTEND_BUCKET"
fi

# Import Lambda functions if they exist
echo -e "\n${YELLOW}⚡ Checking for existing Lambda functions...${NC}"

LAMBDA_FUNCTIONS=(
    "image-resizer"
    "upload-handler" 
    "list-handler"
)

for func in "${LAMBDA_FUNCTIONS[@]}"; do
    FUNCTION_NAME="${PROJECT_PREFIX}-${func}"
    if aws lambda get-function --function-name "$FUNCTION_NAME" > /dev/null 2>&1; then
        echo "Found Lambda function: $FUNCTION_NAME"
        # Map function names to Terraform resource names
        case $func in
            "image-resizer")
                import_resource "aws_lambda_function" "image_resizer" "$FUNCTION_NAME"
                ;;
            "upload-handler")
                import_resource "aws_lambda_function" "upload_handler" "$FUNCTION_NAME"
                ;;
            "list-handler")
                import_resource "aws_lambda_function" "list_handler" "$FUNCTION_NAME"
                ;;
        esac
    fi
done

# Import API Gateway resources if they exist
echo -e "\n${YELLOW}🌐 Checking for existing API Gateway...${NC}"

# Find API Gateway by name
API_ID=$(aws apigateway get-rest-apis --query "items[?name=='${PROJECT_PREFIX}-api'].id" --output text)

if [ ! -z "$API_ID" ] && [ "$API_ID" != "None" ]; then
    echo "Found API Gateway: $API_ID"
    import_resource "aws_api_gateway_rest_api" "photo_api" "$API_ID"
    
    # Try to import deployment
    DEPLOYMENT_ID=$(aws apigateway get-deployments --rest-api-id "$API_ID" --query "items[0].id" --output text 2>/dev/null || echo "")
    if [ ! -z "$DEPLOYMENT_ID" ] && [ "$DEPLOYMENT_ID" != "None" ]; then
        import_resource "aws_api_gateway_deployment" "deployment" "$API_ID/$DEPLOYMENT_ID"
    fi
fi

# Import DynamoDB table if it exists
echo -e "\n${YELLOW}📊 Checking for existing DynamoDB table...${NC}"

TABLE_NAME="${PROJECT_PREFIX}-images-metadata"
if aws dynamodb describe-table --table-name "$TABLE_NAME" > /dev/null 2>&1; then
    echo "Found DynamoDB table: $TABLE_NAME"
    import_resource "aws_dynamodb_table" "images_metadata" "$TABLE_NAME"
fi

echo -e "\n${GREEN}🎉 Import process completed!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Run: terraform plan -var-file=\"terraform.tfvars\""
echo "2. Review the plan to ensure no unwanted changes"
echo "3. Run: terraform apply -var-file=\"terraform.tfvars\""