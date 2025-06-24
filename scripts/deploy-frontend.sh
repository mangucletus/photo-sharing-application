#!/bin/bash

# Frontend deployment script
# This script updates the frontend configuration and deploys to S3

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting frontend deployment...${NC}"

# Check if required environment variables are set
if [ -z "$IMAGES_BUCKET" ] || [ -z "$THUMBNAILS_BUCKET" ] || [ -z "$FRONTEND_BUCKET" ] || [ -z "$API_GATEWAY_URL" ]; then
    echo -e "${RED}❌ Error: Required environment variables not set${NC}"
    echo "Please set: IMAGES_BUCKET, THUMBNAILS_BUCKET, FRONTEND_BUCKET, API_GATEWAY_URL"
    exit 1
fi

# Navigate to frontend directory
cd "$(dirname "$0")/../frontend"

# Create a temporary copy of index.html
cp index.html index.html.tmp

# Replace placeholders with actual values
echo -e "${YELLOW}📝 Updating configuration...${NC}"
sed -i "s/{{IMAGES_BUCKET}}/${IMAGES_BUCKET}/g" index.html.tmp
sed -i "s/{{THUMBNAILS_BUCKET}}/${THUMBNAILS_BUCKET}/g" index.html.tmp
sed -i "s|{{API_GATEWAY_URL}}|${API_GATEWAY_URL}|g" index.html.tmp

# Deploy to S3
echo -e "${YELLOW}📤 Uploading to S3...${NC}"
aws s3 cp index.html.tmp s3://${FRONTEND_BUCKET}/index.html \
    --content-type "text/html" \
    --cache-control "max-age=300"

# Clean up
rm index.html.tmp

echo -e "${GREEN}✅ Frontend deployment complete!${NC}"
echo -e "${GREEN}🌐 Your app is available at: http://${FRONTEND_BUCKET}.s3-website.eu-west-1.amazonaws.com/${NC}"