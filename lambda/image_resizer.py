"""
AWS Lambda function to automatically resize images uploaded to S3.
Triggered when an image is uploaded to the source bucket,
creates a thumbnail, saves it to the destination bucket, and stores metadata in DynamoDB.
"""

import json
import boto3
import os
from PIL import Image
import io
import logging
import uuid
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Main Lambda handler function.
    
    Args:
        event: S3 event data containing bucket and object information
        context: Lambda runtime context
    
    Returns:
        dict: Response with status code and message
    """
    
    try:
        # Extract S3 event details
        record = event['Records'][0]
        source_bucket = record['s3']['bucket']['name']
        source_key = record['s3']['object']['key']
        
        logger.info(f"Processing image: {source_key} from bucket: {source_bucket}")
        
        # Get environment variables
        target_bucket = os.environ.get('THUMBNAIL_BUCKET')
        thumbnail_size = int(os.environ.get('THUMBNAIL_SIZE', '150'))
        dynamodb_table = os.environ.get('DYNAMODB_TABLE')
        
        if not target_bucket:
            raise ValueError("THUMBNAIL_BUCKET environment variable not set")
        if not dynamodb_table:
            raise ValueError("DYNAMODB_TABLE environment variable not set")
        
        # Skip if file is already a thumbnail
        if source_key.startswith('thumb-'):
            logger.info("Skipping thumbnail file")
            return {
                'statusCode': 200,
                'body': json.dumps('Skipped thumbnail file')
            }
        
        # Check if file is an image
        if not is_image_file(source_key):
            logger.info("Skipping non-image file")
            return {
                'statusCode': 200,
                'body': json.dumps('Skipped non-image file')
            }
        
        # Define target key with thumb- prefix
        target_key = f"thumb-{source_key}"
        
        # Download image from source bucket
        logger.info("Downloading image from S3")
        response = s3.get_object(Bucket=source_bucket, Key=source_key)
        image_data = response['Body'].read()
        content_length = len(image_data)
        
        # Open and process image
        logger.info("Processing image")
        image = Image.open(io.BytesIO(image_data))
        
        # Convert to RGB if necessary (for PNG with transparency)
        if image.mode in ('RGBA', 'LA', 'P'):
            # Create a white background
            background = Image.new('RGB', image.size, (255, 255, 255))
            if image.mode == 'P':
                image = image.convert('RGBA')
            background.paste(image, mask=image.split()[-1] if image.mode == 'RGBA' else None)
            image = background
        
        # Create thumbnail
        original_size = image.size
        image.thumbnail((thumbnail_size, thumbnail_size), Image.Resampling.LANCZOS)
        
        logger.info(f"Resized image from {original_size} to {image.size}")
        
        # Save thumbnail to buffer
        buffer = io.BytesIO()
        image.save(buffer, "JPEG", quality=85, optimize=True)
        buffer.seek(0)
        thumbnail_size_bytes = len(buffer.getvalue())
        
        # Upload thumbnail to target bucket
        logger.info(f"Uploading thumbnail to {target_bucket}/{target_key}")
        s3.put_object(
            Bucket=target_bucket,
            Key=target_key,
            Body=buffer.getvalue(),
            ContentType="image/jpeg",
            ACL="public-read",
            Metadata={
                'original-size': f"{original_size[0]}x{original_size[1]}",
                'thumbnail-size': f"{image.size[0]}x{image.size[1]}",
                'source-bucket': source_bucket,
                'source-key': source_key
            }
        )
        
        # Store metadata in DynamoDB
        logger.info("Storing metadata in DynamoDB")
        table = dynamodb.Table(dynamodb_table)
        
        image_id = str(uuid.uuid4())
        upload_date = datetime.utcnow().isoformat()
        
        table.put_item(
            Item={
                'image_id': image_id,
                'original_filename': source_key,
                'thumbnail_filename': target_key,
                'original_size_width': original_size[0],
                'original_size_height': original_size[1],
                'thumbnail_size_width': image.size[0],
                'thumbnail_size_height': image.size[1],
                'original_size_bytes': content_length,
                'thumbnail_size_bytes': thumbnail_size_bytes,
                'upload_date': upload_date,
                'user_id': 'anonymous',  # Can be updated to use actual user authentication
                'source_bucket': source_bucket,
                'target_bucket': target_bucket,
                'status': 'processed'
            }
        )
        
        logger.info("Thumbnail created and metadata stored successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Thumbnail created successfully: {target_key}',
                'image_id': image_id,
                'original_size': original_size,
                'thumbnail_size': list(image.size),
                'source_bucket': source_bucket,
                'target_bucket': target_bucket,
                'upload_date': upload_date
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing image: {str(e)}")
        
        # Store error in DynamoDB if possible
        try:
            if 'dynamodb_table' in locals() and dynamodb_table:
                table = dynamodb.Table(dynamodb_table)
                table.put_item(
                    Item={
                        'image_id': str(uuid.uuid4()),
                        'original_filename': source_key if 'source_key' in locals() else 'unknown',
                        'upload_date': datetime.utcnow().isoformat(),
                        'user_id': 'anonymous',
                        'status': 'error',
                        'error_message': str(e)
                    }
                )
        except Exception as db_error:
            logger.error(f"Failed to store error in DynamoDB: {str(db_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Error processing image: {str(e)}'
            })
        }

def is_image_file(filename):
    """
    Check if the file is an image based on its extension.
    
    Args:
        filename (str): The filename to check
    
    Returns:
        bool: True if it's an image file, False otherwise
    """
    image_extensions = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.webp'}
    return any(filename.lower().endswith(ext) for ext in image_extensions)