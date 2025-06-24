"""
AWS Lambda function to automatically resize images uploaded to S3.
Triggered when an image is uploaded to the source bucket,
creates a thumbnail and saves it to the destination bucket.
"""

import json
import boto3
import os
from PIL import Image
import io
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize S3 client
s3 = boto3.client('s3')

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
        
        if not target_bucket:
            raise ValueError("THUMBNAIL_BUCKET environment variable not set")
        
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
        
        # Upload thumbnail to target bucket
        logger.info(f"Uploading thumbnail to {target_bucket}/{target_key}")
        s3.put_object(
            Bucket=target_bucket,
            Key=target_key,
            Body=buffer.getvalue(),
            ContentType="image/jpeg",
            Metadata={
                'original-size': f"{original_size[0]}x{original_size[1]}",
                'thumbnail-size': f"{image.size[0]}x{image.size[1]}",
                'source-bucket': source_bucket,
                'source-key': source_key
            }
        )
        
        logger.info("Thumbnail created successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Thumbnail created successfully: {target_key}',
                'original_size': original_size,
                'thumbnail_size': list(image.size),
                'source_bucket': source_bucket,
                'target_bucket': target_bucket
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing image: {str(e)}")
        
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