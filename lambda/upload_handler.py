"""
Lambda function to handle file uploads via API Gateway for React frontend.
Generates presigned URLs for secure S3 uploads with Cognito authentication.
"""

import json
import boto3
import os
import logging
import uuid
import base64
from datetime import datetime
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Handle upload requests from React frontend via API Gateway.
    Returns presigned URLs for direct S3 uploads.
    """
    
    # Enable CORS for all responses
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'POST,OPTIONS',
        'Content-Type': 'application/json'
    }
    
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Handle CORS preflight
        if event.get('httpMethod') == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({'message': 'CORS preflight'})
            }
        
        # Get environment variables
        bucket_name = os.environ.get('IMAGES_BUCKET')
        dynamodb_table = os.environ.get('DYNAMODB_TABLE')
        
        if not bucket_name:
            raise ValueError("IMAGES_BUCKET environment variable not set")
        if not dynamodb_table:
            raise ValueError("DYNAMODB_TABLE environment variable not set")
        
        # Extract user information from Cognito context
        user_id = 'anonymous'
        user_email = 'unknown'
        
        # Get user info from Cognito authorizer context
        request_context = event.get('requestContext', {})
        authorizer = request_context.get('authorizer', {})
        
        if authorizer and 'claims' in authorizer:
            claims = authorizer['claims']
            user_id = claims.get('sub', 'anonymous')
            user_email = claims.get('email', 'unknown')
            logger.info(f"Authenticated user: {user_email} ({user_id})")
        else:
            # Try to extract from headers if authorizer context is missing
            auth_header = event.get('headers', {}).get('Authorization', '')
            if auth_header.startswith('Bearer '):
                try:
                    # Extract basic info from token (in production, validate JWT properly)
                    token = auth_header.replace('Bearer ', '')
                    # For now, generate a user ID from token hash
                    user_id = f"user_{hash(token) % 1000000}"
                    logger.info(f"Token-based auth for user: {user_id}")
                except Exception as e:
                    logger.warning(f"Could not extract user from token: {str(e)}")
        
        # Parse request body
        try:
            if event.get('body'):
                # Handle base64 encoded body if needed
                body_content = event['body']
                if event.get('isBase64Encoded', False):
                    body_content = base64.b64decode(body_content).decode('utf-8')
                
                body = json.loads(body_content)
            else:
                return {
                    'statusCode': 400,
                    'headers': headers,
                    'body': json.dumps({'error': 'Request body is required'})
                }
        except json.JSONDecodeError as e:
            logger.error(f"JSON decode error: {str(e)}")
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Invalid JSON in request body'})
            }
        
        filename = body.get('filename')
        content_type = body.get('contentType', 'image/jpeg')
        
        if not filename:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Filename is required'})
            }
        
        # Enhanced file type validation
        allowed_types = [
            'image/jpeg', 'image/jpg', 'image/png', 'image/gif', 
            'image/webp', 'image/bmp', 'image/tiff'
        ]
        
        if content_type not in allowed_types:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({
                    'error': 'Invalid file type. Only images are allowed.',
                    'allowedTypes': allowed_types
                })
            }
        
        # Validate filename
        if not validate_filename(filename):
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Invalid filename. Please use safe characters and image extensions.'})
            }
        
        # Generate unique filename to prevent conflicts
        file_extension = filename.split('.')[-1].lower() if '.' in filename else 'jpg'
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        unique_filename = f"{user_id}_{timestamp}_{uuid.uuid4().hex[:8]}_{filename}"
        
        logger.info(f"Generating presigned URL for: {unique_filename}")
        
        # Generate presigned URL for upload
        try:
            presigned_url = s3.generate_presigned_url(
                'put_object',
                Params={
                    'Bucket': bucket_name,
                    'Key': unique_filename,
                    'ContentType': content_type,
                    'ACL': 'public-read',
                    'Metadata': {
                        'user-id': user_id,
                        'user-email': user_email,
                        'original-filename': filename,
                        'upload-timestamp': datetime.utcnow().isoformat()
                    }
                },
                ExpiresIn=3600  # URL expires in 1 hour
            )
        except ClientError as e:
            logger.error(f"Error generating presigned URL: {str(e)}")
            return {
                'statusCode': 500,
                'headers': headers,
                'body': json.dumps({'error': 'Failed to generate upload URL'})
            }
        
        # Store upload metadata in DynamoDB (pending status)
        upload_id = str(uuid.uuid4())
        upload_date = datetime.utcnow().isoformat()
        
        try:
            table = dynamodb.Table(dynamodb_table)
            
            table.put_item(
                Item={
                    'image_id': upload_id,
                    'original_filename': filename,
                    'unique_filename': unique_filename,
                    'upload_date': upload_date,
                    'user_id': user_id,
                    'user_email': user_email,
                    'status': 'pending_upload',
                    'content_type': content_type,
                    'source_bucket': bucket_name,
                    'presigned_url_generated': True,
                    'presigned_url_expires': upload_date
                }
            )
            
            logger.info(f"Stored upload metadata with ID: {upload_id}")
            
        except ClientError as e:
            logger.error(f"Error storing metadata in DynamoDB: {str(e)}")
            # Don't fail the upload if DynamoDB fails
        
        # Generate view URL for the uploaded file
        view_url = f"https://{bucket_name}.s3.amazonaws.com/{unique_filename}"
        
        # Prepare response
        response_body = {
            'uploadUrl': presigned_url,
            'viewUrl': view_url,
            'filename': unique_filename,
            'originalFilename': filename,
            'bucket': bucket_name,
            'uploadId': upload_id,
            'userId': user_id,
            'contentType': content_type,
            'expiresIn': 3600,
            'message': 'Upload URL generated successfully'
        }
        
        logger.info(f"Successfully generated upload URL for user {user_email}")
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps(response_body)
        }
        
    except ValueError as e:
        logger.error(f"Validation error: {str(e)}")
        
        return {
            'statusCode': 400,
            'headers': headers,
            'body': json.dumps({
                'error': f'Validation error: {str(e)}'
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error generating presigned URL: {str(e)}")
        
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': f'Internal server error: {str(e)}'
            })
        }

def validate_filename(filename):
    """
    Validate the uploaded filename for security.
    
    Args:
        filename (str): The filename to validate
    
    Returns:
        bool: True if valid, False otherwise
    """
    if not filename or len(filename) > 255:
        return False
    
    # Check for dangerous characters
    dangerous_chars = ['..', '/', '\\', '<', '>', ':', '"', '|', '?', '*']
    if any(char in filename for char in dangerous_chars):
        return False
    
    # Check file extension
    allowed_extensions = {
        '.jpg', '.jpeg', '.png', '.gif', '.bmp', 
        '.webp', '.tiff', '.tif'
    }
    
    file_extension = '.' + filename.lower().split('.')[-1] if '.' in filename else ''
    
    return file_extension in allowed_extensions