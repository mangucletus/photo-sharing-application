"""
Lambda function to handle file uploads via API Gateway.
Generates presigned URLs for secure S3 uploads.
"""

import json
import boto3
import os
import logging
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize S3 client
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Handle upload requests from API Gateway.
    Returns presigned URLs for direct S3 uploads.
    """
    
    # Enable CORS
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'POST,OPTIONS'
    }
    
    try:
        # Parse request body
        if event.get('httpMethod') == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({'message': 'CORS preflight'})
            }
        
        body = json.loads(event.get('body', '{}'))
        filename = body.get('filename')
        content_type = body.get('contentType', 'image/jpeg')
        
        if not filename:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Filename is required'})
            }
        
        # Get environment variables
        bucket_name = os.environ.get('IMAGES_BUCKET')
        if not bucket_name:
            raise ValueError("IMAGES_BUCKET environment variable not set")
        
        # Validate file type
        allowed_types = ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp', 'image/bmp']
        if content_type not in allowed_types:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Invalid file type. Only images are allowed.'})
            }
        
        # Generate presigned URL for upload
        presigned_url = s3.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': bucket_name,
                'Key': filename,
                'ContentType': content_type,
                'ACL': 'public-read'
            },
            ExpiresIn=3600  # URL expires in 1 hour
        )
        
        # Also generate a presigned URL for viewing the uploaded file
        view_url = f"https://{bucket_name}.s3.amazonaws.com/{filename}"
        
        logger.info(f"Generated presigned URL for {filename}")
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'uploadUrl': presigned_url,
                'viewUrl': view_url,
                'filename': filename,
                'bucket': bucket_name
            })
        }
        
    except Exception as e:
        logger.error(f"Error generating presigned URL: {str(e)}")
        
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': f'Error generating upload URL: {str(e)}'
            })
        }