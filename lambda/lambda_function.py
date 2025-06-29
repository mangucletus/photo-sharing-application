import json
import boto3
import os
import uuid
from datetime import datetime
from PIL import Image
import io
from urllib.parse import unquote_plus

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# Environment variables
THUMBNAIL_BUCKET = os.environ['THUMBNAIL_BUCKET']
METADATA_TABLE = os.environ['METADATA_TABLE']

table = dynamodb.Table(METADATA_TABLE)

def lambda_handler(event, context):
    try:
        # Get S3 event details
        for record in event['Records']:
            source_bucket = record['s3']['bucket']['name']
            source_key = unquote_plus(record['s3']['object']['key'])
            
            # Skip if it's already a thumbnail
            if source_key.startswith('thumb-'):
                continue
            
            # Generate unique image ID
            image_id = str(uuid.uuid4())
            
            # Define target key for thumbnail
            target_key = f"thumb-{image_id}-{source_key}"
            
            print(f"Processing: {source_key} -> {target_key}")
            
            # Download image from S3
            try:
                response = s3.get_object(Bucket=source_bucket, Key=source_key)
                image_content = response['Body'].read()
                
                # Open and resize image
                image = Image.open(io.BytesIO(image_content))
                
                # Convert to RGB if necessary (for JPEG)
                if image.mode in ('RGBA', 'P'):
                    image = image.convert('RGB')
                
                # Create thumbnail
                image.thumbnail((150, 150), Image.Resampling.LANCZOS)
                
                # Save thumbnail to bytes
                buffer = io.BytesIO()
                image.save(buffer, "JPEG", quality=85)
                buffer.seek(0)
                
                # Upload thumbnail to S3
                s3.put_object(
                    Bucket=THUMBNAIL_BUCKET,
                    Key=target_key,
                    Body=buffer,
                    ContentType="image/jpeg",
                    CacheControl="max-age=31536000"  # 1 year cache
                )
                
                # Get image metadata
                original_size = len(image_content)
                thumbnail_size = len(buffer.getvalue())
                width, height = image.size
                
                # Store metadata in DynamoDB
                table.put_item(
                    Item={
                        'image_id': image_id,
                        'original_key': source_key,
                        'thumbnail_key': target_key,
                        'original_bucket': source_bucket,
                        'thumbnail_bucket': THUMBNAIL_BUCKET,
                        'original_size': original_size,
                        'thumbnail_size': thumbnail_size,
                        'width': width,
                        'height': height,
                        'upload_time': datetime.utcnow().isoformat(),
                        'content_type': response.get('ContentType', 'image/jpeg')
                    }
                )
                
                print(f"Successfully processed {source_key}")
                
            except Exception as e:
                print(f"Error processing {source_key}: {str(e)}")
                continue
        
        return {
            'statusCode': 200,
            'body': json.dumps('Images processed successfully')
        }
        
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing images: {str(e)}')
        }