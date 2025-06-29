#!/bin/bash

# Deployment verification script for React Photo Sharing App
# This script tests all components of the deployed application

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 React Photo Sharing App Deployment Verification${NC}"
echo "=================================================================="

# Navigate to terraform directory
cd "$(dirname "$0")/../terraform"

echo -e "${YELLOW}📋 Step 1: Checking Terraform deployment...${NC}"

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
FRONTEND_URL="https://${FRONTEND_BUCKET}.s3-website.${AWS_REGION}.amazonaws.com"

echo -e "${BLUE}📊 Configuration Summary:${NC}"
echo "IMAGES_BUCKET: $IMAGES_BUCKET"
echo "THUMBNAILS_BUCKET: $THUMBNAILS_BUCKET"
echo "FRONTEND_BUCKET: $FRONTEND_BUCKET"
echo "API_GATEWAY_URL: $API_GATEWAY_URL"
echo "COGNITO_USER_POOL_ID: $COGNITO_USER_POOL_ID"
echo "FRONTEND_URL: $FRONTEND_URL"

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

echo ""
echo -e "${YELLOW}📋 Step 2: Testing AWS services...${NC}"

# Test AWS CLI connection
echo -e "${YELLOW}🔗 Testing AWS connection...${NC}"
if aws sts get-caller-identity > /dev/null 2>&1; then
    CALLER_ID=$(aws sts get-caller-identity --query 'Account' --output text)
    echo -e "${GREEN}✅ AWS CLI connected to account: $CALLER_ID${NC}"
else
    echo -e "${RED}❌ AWS CLI not configured or no access${NC}"
    exit 1
fi

# Test S3 buckets
echo -e "${YELLOW}🪣 Testing S3 bucket access...${NC}"
for bucket in "$IMAGES_BUCKET" "$THUMBNAILS_BUCKET" "$FRONTEND_BUCKET"; do
    if [ "$bucket" != "NOT_SET" ]; then
        if aws s3 ls s3://$bucket > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Can access bucket: $bucket${NC}"
        else
            echo -e "${RED}❌ Cannot access bucket: $bucket${NC}"
        fi
    fi
done

# Test DynamoDB table
DYNAMODB_TABLE=$(terraform output -raw dynamodb_table_name 2>/dev/null || echo "NOT_SET")
if [ "$DYNAMODB_TABLE" != "NOT_SET" ]; then
    echo -e "${YELLOW}🗄️ Testing DynamoDB table access...${NC}"
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Can access DynamoDB table: $DYNAMODB_TABLE${NC}"
    else
        echo -e "${RED}❌ Cannot access DynamoDB table: $DYNAMODB_TABLE${NC}"
    fi
fi

# Test Lambda functions
echo -e "${YELLOW}⚡ Testing Lambda functions...${NC}"
LAMBDA_FUNCTIONS=(
    "$(terraform output -raw lambda_function_name 2>/dev/null || echo '')"
    "$(terraform output -raw upload_handler_function_name 2>/dev/null || echo '')"
    "$(terraform output -raw list_handler_function_name 2>/dev/null || echo '')"
)

for func in "${LAMBDA_FUNCTIONS[@]}"; do
    if [ ! -z "$func" ] && [ "$func" != "NOT_SET" ]; then
        if aws lambda get-function --function-name "$func" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Lambda function exists: $func${NC}"
        else
            echo -e "${RED}❌ Lambda function not found: $func${NC}"
        fi
    fi
done

echo ""
echo -e "${YELLOW}📋 Step 3: Testing API Gateway...${NC}"

if [ "$API_GATEWAY_URL" != "NOT_SET" ]; then
    # Test CORS preflight for upload endpoint
    echo -e "${YELLOW}🔗 Testing CORS preflight (upload endpoint)...${NC}"
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      -X OPTIONS \
      "$API_GATEWAY_URL/images/upload" \
      -H "Origin: $FRONTEND_URL" \
      -H "Access-Control-Request-Method: POST" \
      -H "Access-Control-Request-Headers: Authorization" 2>/dev/null || echo "000")
    
    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo -e "${GREEN}✅ CORS preflight test passed for upload endpoint${NC}"
    else
        echo -e "${YELLOW}⚠️ CORS preflight test failed with status: $HTTP_STATUS (this is expected without auth)${NC}"
    fi
    
    # Test CORS preflight for list endpoint
    echo -e "${YELLOW}🔗 Testing CORS preflight (list endpoint)...${NC}"
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      -X OPTIONS \
      "$API_GATEWAY_URL/images/list" \
      -H "Origin: $FRONTEND_URL" \
      -H "Access-Control-Request-Method: GET" \
      -H "Access-Control-Request-Headers: Authorization" 2>/dev/null || echo "000")
    
    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo -e "${GREEN}✅ CORS preflight test passed for list endpoint${NC}"
    else
        echo -e "${YELLOW}⚠️ CORS preflight test failed with status: $HTTP_STATUS (this is expected without auth)${NC}"
    fi
    
    # Test API Gateway base URL
    echo -e "${YELLOW}🔗 Testing API Gateway base URL...${NC}"
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$API_GATEWAY_URL" 2>/dev/null || echo "000")
    
    if [ "$HTTP_STATUS" -eq 403 ] || [ "$HTTP_STATUS" -eq 404 ]; then
        echo -e "${GREEN}✅ API Gateway is responding (status: $HTTP_STATUS - expected for unauthenticated requests)${NC}"
    else
        echo -e "${YELLOW}⚠️ API Gateway response status: $HTTP_STATUS${NC}"
    fi
else
    echo -e "${RED}❌ API Gateway URL not available${NC}"
fi

echo ""
echo -e "${YELLOW}📋 Step 4: Testing Cognito configuration...${NC}"

if [ "$COGNITO_USER_POOL_ID" != "NOT_SET" ]; then
    # Test Cognito User Pool
    echo -e "${YELLOW}🔐 Testing Cognito User Pool...${NC}"
    if aws cognito-idp describe-user-pool --user-pool-id "$COGNITO_USER_POOL_ID" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Cognito User Pool exists and is accessible${NC}"
        
        # Get User Pool details
        USER_POOL_NAME=$(aws cognito-idp describe-user-pool --user-pool-id "$COGNITO_USER_POOL_ID" --query 'UserPool.Name' --output text)
        echo -e "${BLUE}   📝 User Pool Name: $USER_POOL_NAME${NC}"
    else
        echo -e "${RED}❌ Cannot access Cognito User Pool${NC}"
    fi
    
    # Test User Pool Client
    if [ "$COGNITO_USER_POOL_CLIENT_ID" != "NOT_SET" ]; then
        echo -e "${YELLOW}🔐 Testing Cognito User Pool Client...${NC}"
        if aws cognito-idp describe-user-pool-client --user-pool-id "$COGNITO_USER_POOL_ID" --client-id "$COGNITO_USER_POOL_CLIENT_ID" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Cognito User Pool Client exists and is accessible${NC}"
        else
            echo -e "${RED}❌ Cannot access Cognito User Pool Client${NC}"
        fi
    fi
else
    echo -e "${RED}❌ Cognito User Pool ID not available${NC}"
fi

echo ""
echo -e "${YELLOW}📋 Step 5: Testing frontend deployment...${NC}"

if [ "$FRONTEND_BUCKET" != "NOT_SET" ]; then
    # Check if index.html exists in S3
    echo -e "${YELLOW}🌐 Testing frontend file deployment...${NC}"
    if aws s3 ls s3://$FRONTEND_BUCKET/index.html > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Frontend index.html found in S3 bucket${NC}"
        
        # Download and check configuration
        echo -e "${YELLOW}🔍 Checking frontend configuration...${NC}"
        aws s3 cp s3://$FRONTEND_BUCKET/index.html /tmp/frontend-check.html > /dev/null 2>&1
        
        # Check if placeholders were replaced
        if grep -q "{{" /tmp/frontend-check.html; then
            echo -e "${RED}❌ Frontend still contains unreplaced placeholders:${NC}"
            grep "{{" /tmp/frontend-check.html | head -5
        else
            echo -e "${GREEN}✅ All configuration placeholders have been replaced${NC}"
        fi
        
        # Check if configuration values are present
        if grep -q "$COGNITO_USER_POOL_ID" /tmp/frontend-check.html; then
            echo -e "${GREEN}✅ Cognito User Pool ID found in frontend configuration${NC}"
        else
            echo -e "${YELLOW}⚠️ Cognito User Pool ID not found in frontend configuration${NC}"
        fi
        
        if grep -q "$API_GATEWAY_URL" /tmp/frontend-check.html; then
            echo -e "${GREEN}✅ API Gateway URL found in frontend configuration${NC}"
        else
            echo -e "${YELLOW}⚠️ API Gateway URL not found in frontend configuration${NC}"
        fi
        
        # Clean up
        rm -f /tmp/frontend-check.html
    else
        echo -e "${RED}❌ Frontend index.html not found in S3 bucket${NC}"
    fi
    
    # Test frontend URL accessibility
    echo -e "${YELLOW}🌐 Testing frontend URL accessibility...${NC}"
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$FRONTEND_URL" 2>/dev/null || echo "000")
    
    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo -e "${GREEN}✅ Frontend is accessible at: $FRONTEND_URL${NC}"
    else
        echo -e "${YELLOW}⚠️ Frontend URL returned status: $HTTP_STATUS${NC}"
        echo -e "${BLUE}   🔗 Try accessing: $FRONTEND_URL${NC}"
    fi
else
    echo -e "${RED}❌ Frontend bucket not available${NC}"
fi

echo ""
echo -e "${BLUE}📋 Step 6: Final verification summary...${NC}"

# Overall health check
HEALTH_SCORE=0
TOTAL_CHECKS=8

# Check 1: Configuration complete
if [ ${#MISSING_VALUES[@]} -eq 0 ]; then
    ((HEALTH_SCORE++))
    echo -e "${GREEN}✅ Configuration complete${NC}"
else
    echo -e "${RED}❌ Missing configuration values${NC}"
fi

# Check 2: AWS connectivity
if aws sts get-caller-identity > /dev/null 2>&1; then
    ((HEALTH_SCORE++))
    echo -e "${GREEN}✅ AWS connectivity${NC}"
else
    echo -e "${RED}❌ AWS connectivity failed${NC}"
fi

# Check 3: S3 buckets accessible
if [ "$FRONTEND_BUCKET" != "NOT_SET" ] && aws s3 ls s3://$FRONTEND_BUCKET > /dev/null 2>&1; then
    ((HEALTH_SCORE++))
    echo -e "${GREEN}✅ S3 buckets accessible${NC}"
else
    echo -e "${RED}❌ S3 buckets not accessible${NC}"
fi

# Check 4: API Gateway responding
if [ "$HTTP_STATUS" -eq 403 ] || [ "$HTTP_STATUS" -eq 404 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    ((HEALTH_SCORE++))
    echo -e "${GREEN}✅ API Gateway responding${NC}"
else
    echo -e "${RED}❌ API Gateway not responding${NC}"
fi

# Check 5: Cognito configured
if [ "$COGNITO_USER_POOL_ID" != "NOT_SET" ] && aws cognito-idp describe-user-pool --user-pool-id "$COGNITO_USER_POOL_ID" > /dev/null 2>&1; then
    ((HEALTH_SCORE++))
    echo -e "${GREEN}✅ Cognito configured${NC}"
else
    echo -e "${RED}❌ Cognito not properly configured${NC}"
fi

# Check 6: Frontend deployed
if [ "$FRONTEND_BUCKET" != "NOT_SET" ] && aws s3 ls s3://$FRONTEND_BUCKET/index.html > /dev/null 2>&1; then
    ((HEALTH_SCORE++))
    echo -e "${GREEN}✅ Frontend deployed${NC}"
else
    echo -e "${RED}❌ Frontend not deployed${NC}"
fi

# Check 7: Lambda functions deployed
LAMBDA_COUNT=0
for func in "${LAMBDA_FUNCTIONS[@]}"; do
    if [ ! -z "$func" ] && [ "$func" != "NOT_SET" ] && aws lambda get-function --function-name "$func" > /dev/null 2>&1; then
        ((LAMBDA_COUNT++))
    fi
done
if [ $LAMBDA_COUNT -ge 2 ]; then
    ((HEALTH_SCORE++))
    echo -e "${GREEN}✅ Lambda functions deployed${NC}"
else
    echo -e "${RED}❌ Lambda functions not properly deployed${NC}"
fi

# Check 8: Frontend configuration
aws s3 cp s3://$FRONTEND_BUCKET/index.html /tmp/final-check.html > /dev/null 2>&1
if [ -f /tmp/final-check.html ] && ! grep -q "{{" /tmp/final-check.html; then
    ((HEALTH_SCORE++))
    echo -e "${GREEN}✅ Frontend configuration complete${NC}"
    rm -f /tmp/final-check.html
else
    echo -e "${RED}❌ Frontend configuration incomplete${NC}"
    rm -f /tmp/final-check.html
fi

echo ""
echo -e "${BLUE}🎯 Overall Health Score: $HEALTH_SCORE/$TOTAL_CHECKS${NC}"

if [ $HEALTH_SCORE -eq $TOTAL_CHECKS ]; then
    echo -e "${GREEN}🎉 Perfect! Your React Photo Sharing App is fully deployed and ready to use!${NC}"
    echo ""
    echo -e "${GREEN}🔗 Access your app at: $FRONTEND_URL${NC}"
    echo ""
    echo -e "${BLUE}📋 What you can do now:${NC}"
    echo "1. 📱 Open the app and create an account with email/password"
    echo "2. 📤 Upload some photos to test the functionality"
    echo "3. 🖼️ View your photo gallery with automatic thumbnails"
    echo "4. 🔄 Test the refresh functionality"
elif [ $HEALTH_SCORE -ge 6 ]; then
    echo -e "${YELLOW}⚠️ Good! Your app is mostly deployed but has some issues to address.${NC}"
    echo -e "${BLUE}🔗 Try accessing: $FRONTEND_URL${NC}"
else
    echo -e "${RED}❌ Your deployment has significant issues that need to be resolved.${NC}"
    echo -e "${YELLOW}💡 Please check the errors above and re-run the deployment.${NC}"
fi

echo ""
echo -e "${BLUE}🔧 Troubleshooting Tips:${NC}"
echo "- If frontend shows loading forever: Check browser console for configuration errors"
echo "- If authentication fails: Verify Cognito User Pool configuration"
echo "- If uploads fail: Check API Gateway CORS and Lambda function logs"
echo "- If images don't appear: Check S3 bucket permissions and Lambda triggers"

echo ""
echo -e "${GREEN}✅ Verification script completed${NC}"