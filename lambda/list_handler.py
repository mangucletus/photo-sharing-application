"""
Lambda function to list images from DynamoDB and S3.
Returns image metadata and thumbnail URLs.
"""

import json
import boto3
import os
import logging
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Handle list requests from API Gateway.
    Returns list of images with metadata and URLs.
    """
    
    # Enable CORS
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,OPTIONS'
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
        dynamodb_table = os.environ.get('DYNAMODB_TABLE')
        thumbnail_bucket = os.environ.get('THUMBNAIL_BUCKET')
        
        if not dynamodb_table or not thumbnail_bucket:
            raise ValueError("Environment variables not set")
        
        # Get query parameters
        query_params = event.get('queryStringParameters') or {}
        limit = int(query_params.get('limit', 50))
        user_id = query_params.get('user_id', 'anonymous')
        
        # Query DynamoDB for image metadata
        table = dynamodb.Table(dynamodb_table)
        
        try:
            # Scan the table (in production, you'd want to use Query with proper indexes)
            response = table.scan(
                FilterExpression=boto3.dynamodb.conditions.Attr('status').eq('processed'),
                Limit=limit
            )
            
            items = response.get('Items', [])
            
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
            if isinstance(item, dict):
                # DynamoDB item
                thumbnail_filename = item.get('thumbnail_filename', '')
                original_filename = item.get('original_filename', '')
            else:
                # S3 object
                thumbnail_filename = item
                original_filename = item.replace('thumb-', '') if item.startswith('thumb-') else item
            
            if thumbnail_filename:
                thumbnail_url = f"https://{thumbnail_bucket}.s3.amazonaws.com/{thumbnail_filename}"
                
                # Check if thumbnail exists
                try:
                    s3.head_object(Bucket=thumbnail_bucket, Key=thumbnail_filename)
                    
                    image_data = {
                        'id': item.get('image_id', thumbnail_filename) if isinstance(item, dict) else thumbnail_filename,
                        'originalFilename': original_filename,
                        'thumbnailFilename': thumbnail_filename,
                        'thumbnailUrl': thumbnail_url,
                        'uploadDate': item.get('upload_date', '') if isinstance(item, dict) else '',
                        'originalSize': {
                            'width': item.get('original_size_width', 0) if isinstance(item, dict) else 0,
                            'height': item.get('original_size_height', 0) if isinstance(item, dict) else 0
                        },
                        'thumbnailSize': {
                            'width': item.get('thumbnail_size_width', 0) if isinstance(item, dict) else 0,
                            'height': item.get('thumbnail_size_height', 0) if isinstance(item, dict) else 0
                        },
                        'sizeBytes': item.get('thumbnail_size_bytes', 0) if isinstance(item, dict) else 0
                    }
                    
                    images.append(image_data)
                    
                except ClientError:
                    # Thumbnail doesn't exist, skip it
                    continue
        
        logger.info(f"Returning {len(images)} images")
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'images': images,
                'count': len(images),
                'limit': limit
            })
        }
        
    except Exception as e:
        logger.error(f"Error listing images: {str(e)}")
        
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': f'Error listing images: {str(e)}'
            })
        }

def list_from_s3(bucket_name, limit):
    """
    Fallback method to list thumbnails directly from S3.
    """
    try:
        response = s3.list_objects_v2(
            Bucket=bucket_name,
            Prefix='thumb-',
            MaxKeys=limit
        )
        
        objects = response.get('Contents', [])
        return [obj['Key'] for obj in objects]
        
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