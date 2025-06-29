#!/bin/bash

# Debug script to check frontend configuration
# This script helps identify configuration issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Photo Sharing App Debug Script${NC}"
echo "=================================="

# Navigate to terraform directory
cd "$(dirname "$0")/../terraform"

echo -e "${YELLOW}📋 Checking Terraform outputs...${NC}"

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
    echo -e "${RED}❌ Terraform not initialized. Run 'terraform init' first.${NC}"
    exit 1
fi

# Get terraform outputs
echo -e "${YELLOW}📤 Extracting configuration values...${NC}"

IMAGES_BUCKET=$(terraform output -raw images_bucket_name 2>/dev/null || echo "NOT_SET")
THUMBNAILS_BUCKET=$(terraform output -raw thumbnails_bucket_name 2>/dev/null || echo "NOT_SET")
FRONTEND_BUCKET=$(terraform output -raw frontend_bucket_name 2>/dev/null || echo "NOT_SET")
API_GATEWAY_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "NOT_SET")
COGNITO_USER_POOL_ID=$(terraform output -raw cognito_user_pool_id 2>/dev/null || echo "NOT_SET")
COGNITO_USER_POOL_CLIENT_ID=$(terraform output -raw cognito_user_pool_client_id 2>/dev/null || echo "NOT_SET")
COGNITO_IDENTITY_POOL_ID=$(terraform output -raw cognito_identity_pool_id 2>/dev/null || echo "NOT_SET")
AWS_REGION=$(terraform output -raw cognito_region 2>/dev/null || echo "eu-west-1")

echo -e "${BLUE}📊 Configuration Values:${NC}"
echo "IMAGES_BUCKET: $IMAGES_BUCKET"
echo "THUMBNAILS_BUCKET: $THUMBNAILS_BUCKET"
echo "FRONTEND_BUCKET: $FRONTEND_BUCKET"
echo "API_GATEWAY_URL: $API_GATEWAY_URL"
echo "COGNITO_USER_POOL_ID: $COGNITO_USER_POOL_ID"
echo "COGNITO_USER_POOL_CLIENT_ID: $COGNITO_USER_POOL_CLIENT_ID"
echo "COGNITO_IDENTITY_POOL_ID: $COGNITO_IDENTITY_POOL_ID"
echo "AWS_REGION: $AWS_REGION"

# Check for missing values
MISSING_VALUES=()
if [ "$IMAGES_BUCKET" = "NOT_SET" ]; then MISSING_VALUES+=("IMAGES_BUCKET"); fi
if [ "$THUMBNAILS_BUCKET" = "NOT_SET" ]; then MISSING_VALUES+=("THUMBNAILS_BUCKET"); fi
if [ "$FRONTEND_BUCKET" = "NOT_SET" ]; then MISSING_VALUES+=("FRONTEND_BUCKET"); fi
if [ "$API_GATEWAY_URL" = "NOT_SET" ]; then MISSING_VALUES+=("API_GATEWAY_URL"); fi
if [ "$COGNITO_USER_POOL_ID" = "NOT_SET" ]; then MISSING_VALUES+=("COGNITO_USER_POOL_ID"); fi

if [ ${#MISSING_VALUES[@]} -gt 0 ]; then
    echo -e "${RED}❌ Missing configuration values: ${MISSING_VALUES[*]}${NC}"
    echo -e "${YELLOW}💡 Run 'terraform apply' to create missing resources${NC}"
    exit 1
else
    echo -e "${GREEN}✅ All configuration values are present${NC}"
fi

# Update frontend configuration
echo -e "${YELLOW}🔧 Updating frontend configuration...${NC}"
cd ../frontend

# Check if index.html exists
if [ ! -f "index.html" ]; then
    echo -e "${RED}❌ index.html not found in frontend directory${NC}"
    exit 1
fi

# Create backup
cp index.html index.html.debug.bak

# Replace placeholders
sed -i.tmp "s/{{IMAGES_BUCKET}}/$IMAGES_BUCKET/g" index.html
sed -i.tmp "s/{{THUMBNAILS_BUCKET}}/$THUMBNAILS_BUCKET/g" index.html
sed -i.tmp "s|{{API_GATEWAY_URL}}|$API_GATEWAY_URL|g" index.html
sed -i.tmp "s/{{AWS_REGION}}/$AWS_REGION/g" index.html
sed -i.tmp "s/{{COGNITO_USER_POOL_ID}}/$COGNITO_USER_POOL_ID/g" index.html
sed -i.tmp "s/{{COGNITO_USER_POOL_CLIENT_ID}}/$COGNITO_USER_POOL_CLIENT_ID/g" index.html
sed -i.tmp "s/{{COGNITO_IDENTITY_POOL_ID}}/$COGNITO_IDENTITY_POOL_ID/g" index.html

# Remove temp files
rm -f index.html.tmp

# Check if any placeholders remain
if grep -q "{{" index.html; then
    echo -e "${YELLOW}⚠️ Warning: Some placeholders were not replaced:${NC}"
    grep "{{" index.html || true
else
    echo -e "${GREEN}✅ All placeholders were successfully replaced${NC}"
fi

# Test AWS CLI connection
echo -e "${YELLOW}🔗 Testing AWS connection...${NC}"
if aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "${GREEN}✅ AWS CLI is properly configured${NC}"
    
    # Check S3 bucket access
    if [ "$FRONTEND_BUCKET" != "NOT_SET" ]; then
        if aws s3 ls s3://$FRONTEND_BUCKET > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Frontend bucket is accessible${NC}"
        else
            echo -e "${RED}❌ Cannot access frontend bucket: $FRONTEND_BUCKET${NC}"
        fi
    fi
else
    echo -e "${RED}❌ AWS CLI not configured or no access${NC}"
    echo -e "${YELLOW}💡 Run 'aws configure' to set up AWS credentials${NC}"
fi

# Test API Gateway endpoint
if [ "$API_GATEWAY_URL" != "NOT_SET" ]; then
    echo -e "${YELLOW}🔗 Testing API Gateway endpoint...${NC}"
    if curl -s "$API_GATEWAY_URL/images/list" -o /dev/null -w "%{http_code}" | grep -q "401\|403"; then
        echo -e "${GREEN}✅ API Gateway endpoint is responding (expecting auth error)${NC}"
    else
        echo -e "${YELLOW}⚠️ API Gateway endpoint test inconclusive${NC}"
    fi
fi

echo ""
echo -e "${BLUE}🚀 Next Steps:${NC}"
echo "1. If configuration looks correct, deploy frontend:"
echo "   aws s3 sync . s3://$FRONTEND_BUCKET/ --delete"
echo ""
echo "2. Access your app at:"
echo "   https://$FRONTEND_BUCKET.s3-website.$AWS_REGION.amazonaws.com/"
echo ""
echo "3. If you see issues, check browser console for errors"
echo ""
echo -e "${GREEN}✅ Debug script completed${NC}"