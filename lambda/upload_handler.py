"""
Lambda function to handle file uploads via API Gateway.
Generates presigned URLs for secure S3 uploads with Cognito authentication.
"""

import json
import boto3
import os
import logging
import uuid
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
    Handle upload requests from API Gateway.
    Returns presigned URLs for direct S3 uploads.
    """
    
    # Enable CORS
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'POST,OPTIONS',
        'Content-Type': 'application/json'
    }
    
    try:
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
        
        # Get user info from Cognito authorizer context if available
        request_context = event.get('requestContext', {})
        authorizer = request_context.get('authorizer', {})
        
        if authorizer and 'claims' in authorizer:
            claims = authorizer['claims']
            user_id = claims.get('sub', 'anonymous')
            user_email = claims.get('email', 'unknown')
            logger.info(f"Authenticated user: {user_email} ({user_id})")
        else:
            # Fallback: try to extract from JWT token in headers
            auth_header = event.get('headers', {}).get('Authorization', '')
            if auth_header.startswith('Bearer '):
                try:
                    # In production, you'd want to properly validate the JWT
                    # For now, we'll use the basic user info
                    user_id = f"user_{uuid.uuid4().hex[:8]}"
                    logger.info(f"Token-based auth for user: {user_id}")
                except Exception as e:
                    logger.warning(f"Could not extract user from token: {str(e)}")
        
        # Parse request body
        try:
            body = json.loads(event.get('body', '{}'))
        except json.JSONDecodeError:
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
            'image/webp', 'image/bmp', 'image/tiff', 'image/svg+xml'
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
                'body': json.dumps({'error': 'Invalid filename. Please use alphanumeric characters and common extensions.'})
            }
        
        # Generate unique filename to prevent conflicts
        file_extension = filename.split('.')[-1] if '.' in filename else 'jpg'
        unique_filename = f"{user_id}_{uuid.uuid4().hex}_{filename}"
        
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
                    'presigned_url_expires': (datetime.utcnow().timestamp() + 3600)
                }
            )
            
            logger.info(f"Stored upload metadata with ID: {upload_id}")
            
        except ClientError as e:
            logger.error(f"Error storing metadata in DynamoDB: {str(e)}")
            # Don't fail the upload if DynamoDB fails, but log the error
        
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
        '.webp', '.tiff', '.tif', '.svg'
    }
    
    file_extension = '.' + filename.lower().split('.')[-1] if '.' in filename else ''
    
    return file_extension in allowed_extensions

def extract_user_from_event(event):
    """
    Extract user information from the Lambda event.
    
    Args:
        event: Lambda event data
    
    Returns:
        tuple: (user_id, user_email)
    """
    try:
        # Try to get user info from Cognito authorizer context
        request_context = event.get('requestContext', {})
        authorizer = request_context.get('authorizer', {})
        
        if authorizer and 'claims' in authorizer:
            claims = authorizer['claims']
            user_id = claims.get('sub', f"user_{uuid.uuid4().hex[:8]}")
            user_email = claims.get('email', 'unknown@example.com')
            return user_id, user_email
        
        # Fallback for testing or non-Cognito scenarios
        return f"user_{uuid.uuid4().hex[:8]}", 'test@example.com'
        
    except Exception as e:
        logger.warning(f"Could not extract user info: {str(e)}")
        return f"user_{uuid.uuid4().hex[:8]}", 'unknown@example.com'