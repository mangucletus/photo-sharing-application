"""
Lambda function to list images from DynamoDB and S3 for React frontend.
Returns image metadata and thumbnail URLs with proper CORS.
"""

import json
import boto3
import os
import logging
from boto3.dynamodb.conditions import Key, Attr
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Handle list requests from React frontend via API Gateway.
    Returns list of images with metadata and URLs.
    """
    
    # Enable CORS for all responses
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,OPTIONS',
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
        dynamodb_table = os.environ.get('DYNAMODB_TABLE')
        thumbnail_bucket = os.environ.get('THUMBNAIL_BUCKET')
        
        if not dynamodb_table or not thumbnail_bucket:
            raise ValueError("Environment variables not set")
        
        # Get query parameters
        query_params = event.get('queryStringParameters') or {}
        limit = int(query_params.get('limit', 50))
        user_id = query_params.get('user_id')
        
        # Extract user information from Cognito context
        request_context = event.get('requestContext', {})
        authorizer = request_context.get('authorizer', {})
        
        current_user_id = 'anonymous'
        if authorizer and 'claims' in authorizer:
            claims = authorizer['claims']
            current_user_id = claims.get('sub', 'anonymous')
            current_user_email = claims.get('email', 'unknown')
            logger.info(f"Authenticated user: {current_user_email} ({current_user_id})")
        
        # Query DynamoDB for image metadata
        table = dynamodb.Table(dynamodb_table)
        
        try:
            # Scan the table for processed images
            # In production, you might want to filter by user or use GSI
            scan_params = {
                'FilterExpression': Attr('status').eq('processed'),
                'Limit': limit
            }
            
            # If user_id is specified and matches current user, filter by user
            if user_id and user_id == current_user_id:
                scan_params['FilterExpression'] = scan_params['FilterExpression'] & Attr('user_id').eq(user_id)
            
            response = table.scan(**scan_params)
            items = response.get('Items', [])
            
            logger.info(f"Found {len(items)} items in DynamoDB")
            
        except ClientError as e:
            logger.error(f"DynamoDB error: {str(e)}")
            # Fallback to S3 listing if DynamoDB fails
            items = []
        
        # If no items from DynamoDB, fall back to S3 listing
        if not items:
            logger.info("No items from DynamoDB, falling back to S3 listing")
            items = list_from_s3(thumbnail_bucket, limit)
        
        # Format response with thumbnail URLs
        images = []
        for item in items:
            try:
                if isinstance(item, dict):
                    # DynamoDB item
                    thumbnail_filename = item.get('thumbnail_filename', '')
                    original_filename = item.get('original_filename', '')
                    upload_date = item.get('upload_date', '')
                    user_id_item = item.get('user_id', 'unknown')
                    
                    # Additional metadata
                    original_size_width = item.get('original_size_width', 0)
                    original_size_height = item.get('original_size_height', 0)
                    thumbnail_size_width = item.get('thumbnail_size_width', 0)
                    thumbnail_size_height = item.get('thumbnail_size_height', 0)
                    size_bytes = item.get('thumbnail_size_bytes', 0)
                    
                else:
                    # S3 object (fallback)
                    thumbnail_filename = item
                    original_filename = item.replace('thumb-', '') if item.startswith('thumb-') else item
                    upload_date = ''
                    user_id_item = 'unknown'
                    
                    # Default values for S3 objects
                    original_size_width = 0
                    original_size_height = 0
                    thumbnail_size_width = 0
                    thumbnail_size_height = 0
                    size_bytes = 0
                
                if thumbnail_filename:
                    # Generate HTTPS thumbnail URL
                    thumbnail_url = f"https://{thumbnail_bucket}.s3.amazonaws.com/{thumbnail_filename}"
                    
                    # Check if thumbnail exists and is accessible
                    try:
                        s3.head_object(Bucket=thumbnail_bucket, Key=thumbnail_filename)
                        
                        image_data = {
                            'id': item.get('image_id', thumbnail_filename) if isinstance(item, dict) else thumbnail_filename,
                            'originalFilename': original_filename,
                            'thumbnailFilename': thumbnail_filename,
                            'thumbnailUrl': thumbnail_url,
                            'uploadDate': upload_date,
                            'userId': user_id_item,
                            'originalSize': {
                                'width': original_size_width,
                                'height': original_size_height
                            },
                            'thumbnailSize': {
                                'width': thumbnail_size_width,
                                'height': thumbnail_size_height
                            },
                            'sizeBytes': size_bytes
                        }
                        
                        images.append(image_data)
                        
                    except ClientError as s3_error:
                        # Thumbnail doesn't exist or isn't accessible, skip it
                        logger.warning(f"Thumbnail not accessible: {thumbnail_filename} - {str(s3_error)}")
                        continue
                        
            except Exception as item_error:
                logger.error(f"Error processing item: {str(item_error)}")
                continue
        
        # Sort images by upload date (newest first)
        images.sort(key=lambda x: x.get('uploadDate', ''), reverse=True)
        
        logger.info(f"Returning {len(images)} images to frontend")
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'images': images,
                'count': len(images),
                'limit': limit,
                'message': f'Successfully retrieved {len(images)} images'
            })
        }
        
    except Exception as e:
        logger.error(f"Error listing images: {str(e)}")
        
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': f'Error listing images: {str(e)}',
                'images': [],
                'count': 0
            })
        }

def list_from_s3(bucket_name, limit):
    """
    Fallback method to list thumbnails directly from S3.
    """
    try:
        logger.info(f"Listing objects from S3 bucket: {bucket_name}")
        
        response = s3.list_objects_v2(
            Bucket=bucket_name,
            Prefix='thumb-',
            MaxKeys=limit
        )
        
        objects = response.get('Contents', [])
        
        # Return object keys with additional metadata
        s3_items = []
        for obj in objects:
            try:
                # Get additional object metadata
                head_response = s3.head_object(Bucket=bucket_name, Key=obj['Key'])
                
                s3_items.append({
                    'thumbnail_filename': obj['Key'],
                    'original_filename': obj['Key'].replace('thumb-', '') if obj['Key'].startswith('thumb-') else obj['Key'],
                    'upload_date': obj.get('LastModified', '').isoformat() if obj.get('LastModified') else '',
                    'thumbnail_size_bytes': obj.get('Size', 0),
                    'user_id': head_response.get('Metadata', {}).get('user-id', 'unknown'),
                    'status': 'processed'
                })
            except Exception as e:
                logger.warning(f"Error getting metadata for {obj['Key']}: {str(e)}")
                # Add basic item without metadata
                s3_items.append({
                    'thumbnail_filename': obj['Key'],
                    'original_filename': obj['Key'].replace('thumb-', '') if obj['Key'].startswith('thumb-') else obj['Key'],
                    'upload_date': '',
                    'thumbnail_size_bytes': obj.get('Size', 0),
                    'user_id': 'unknown',
                    'status': 'processed'
                })
        
        logger.info(f"Found {len(s3_items)} objects in S3")
        return s3_items
        
    except ClientError as e:
        logger.error(f"S3 listing error: {str(e)}")
        return []

def format_file_size(size_bytes):
    """
    Format file size in human readable format.
    """
    if size_bytes == 0:
        return "0 B"
    
    size_names = ["B", "KB", "MB", "GB"]
    i = 0
    while size_bytes >= 1024 and i < len(size_names) - 1:
        size_bytes /= 1024.0
        i += 1
    
    return f"{size_bytes:.1f} {size_names[i]}"