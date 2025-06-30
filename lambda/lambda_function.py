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
            
            print(f"Processing: {source_key} from bucket: {source_bucket}")
            
            # Generate unique image ID
            image_id = str(uuid.uuid4())
            
            # Define target key for thumbnail
            target_key = f"thumb-{source_key}"
            
            try:
                # Download image from S3
                response = s3.get_object(Bucket=source_bucket, Key=source_key)
                image_content = response['Body'].read()
                
                # Get metadata from S3 object
                s3_metadata = response.get('Metadata', {})
                content_type = response.get('ContentType', 'image/jpeg')
                
                print(f"Downloaded image: {len(image_content)} bytes")
                
                # Open and process image
                image = Image.open(io.BytesIO(image_content))
                
                # Convert to RGB if necessary (for JPEG)
                if image.mode in ('RGBA', 'P'):
                    image = image.convert('RGB')
                
                # Get original dimensions
                original_width, original_height = image.size
                
                # Create thumbnail (150x150 max, preserving aspect ratio)
                image.thumbnail((150, 150), Image.Resampling.LANCZOS)
                thumbnail_width, thumbnail_height = image.size
                
                # Save thumbnail to bytes
                buffer = io.BytesIO()
                image.save(buffer, "JPEG", quality=85, optimize=True)
                buffer.seek(0)
                
                # Upload thumbnail to S3
                s3.put_object(
                    Bucket=THUMBNAIL_BUCKET,
                    Key=target_key,
                    Body=buffer,
                    ContentType="image/jpeg",
                    CacheControl="max-age=31536000",  # 1 year cache
                    Metadata={
                        'original-key': source_key,
                        'original-bucket': source_bucket,
                        'processed-time': datetime.utcnow().isoformat()
                    }
                )
                
                print(f"Uploaded thumbnail: {target_key}")
                
                # Calculate file sizes
                original_size = len(image_content)
                thumbnail_size = len(buffer.getvalue())
                
                # Extract user ID from metadata or derive from key
                user_id = s3_metadata.get('userid', 'unknown')
                original_name = s3_metadata.get('originalname', source_key)
                upload_time = s3_metadata.get('uploadtime', datetime.utcnow().isoformat())
                
                # Store metadata in DynamoDB
                table.put_item(
                    Item={
                        'image_id': image_id,
                        'user_id': user_id,
                        'original_key': source_key,
                        'thumbnail_key': target_key,
                        'original_bucket': source_bucket,
                        'thumbnail_bucket': THUMBNAIL_BUCKET,
                        'original_name': original_name,
                        'original_size': original_size,
                        'thumbnail_size': thumbnail_size,
                        'original_width': original_width,
                        'original_height': original_height,
                        'thumbnail_width': thumbnail_width,
                        'thumbnail_height': thumbnail_height,
                        'upload_time': upload_time,
                        'processed_time': datetime.utcnow().isoformat(),
                        'content_type': content_type,
                        'status': 'processed'
                    }
                )
                
                print(f"Stored metadata for image: {image_id}")
                
                # Create public URL for thumbnail
                # AWS_REGION is automatically available in Lambda context
                region = os.environ.get('AWS_DEFAULT_REGION', 'eu-west-1')
                thumbnail_url = f"https://{THUMBNAIL_BUCKET}.s3.{region}.amazonaws.com/{target_key}"
                
                print(f"Successfully processed {source_key} -> {target_key}")
                print(f"Thumbnail URL: {thumbnail_url}")
                
            except Exception as e:
                print(f"Error processing {source_key}: {str(e)}")
                
                # Store error metadata
                try:
                    table.put_item(
                        Item={
                            'image_id': str(uuid.uuid4()),
                            'user_id': s3_metadata.get('userid', 'unknown'),
                            'original_key': source_key,
                            'original_bucket': source_bucket,
                            'upload_time': s3_metadata.get('uploadtime', datetime.utcnow().isoformat()),
                            'processed_time': datetime.utcnow().isoformat(),
                            'status': 'error',
                            'error_message': str(e)
                        }
                    )
                except:
                    pass  # Don't fail if we can't store error metadata
                
                continue
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Images processed successfully',
                'processed_count': len(event['Records'])
            })
        }
        
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Error processing images',
                'message': str(e)
            })
        }