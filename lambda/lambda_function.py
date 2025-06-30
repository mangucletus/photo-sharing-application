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
                print(f"S3 Metadata received: {s3_metadata}")
                
                # Extract user ID from metadata with various possible keys
                user_id = None
                possible_user_keys = ['user-id', 'userid', 'user_id', 'User-Id', 'UserId']
                for key in possible_user_keys:
                    if key in s3_metadata:
                        user_id = s3_metadata[key]
                        print(f"Found user_id '{user_id}' with key '{key}'")
                        break
                
                # If no user_id found in metadata, try to extract from object key or use unknown
                if not user_id:
                    print("No user_id found in metadata, using 'unknown'")
                    user_id = 'unknown'
                
                # Extract other metadata
                original_name = None
                upload_time = None
                
                # Try different possible keys for original name
                possible_name_keys = ['original-name', 'originalname', 'original_name', 'Original-Name', 'OriginalName']
                for key in possible_name_keys:
                    if key in s3_metadata:
                        original_name = s3_metadata[key]
                        break
                
                if not original_name:
                    original_name = source_key
                
                # Try different possible keys for upload time
                possible_time_keys = ['upload-time', 'uploadtime', 'upload_time', 'Upload-Time', 'UploadTime']
                for key in possible_time_keys:
                    if key in s3_metadata:
                        upload_time = s3_metadata[key]
                        break
                
                if not upload_time:
                    upload_time = datetime.utcnow().isoformat()
                
                # Open and process image
                image = Image.open(io.BytesIO(image_content))
                
                # Convert to RGB if necessary (for JPEG)
                if image.mode in ('RGBA', 'P'):
                    image = image.convert('RGB')
                
                # Get original dimensions
                original_width, original_height = image.size
                print(f"Original dimensions: {original_width}x{original_height}")
                
                # Create higher quality thumbnail (400x400 max, preserving aspect ratio)
                # This will provide much clearer images compared to 150x150
                max_thumbnail_size = 400
                image.thumbnail((max_thumbnail_size, max_thumbnail_size), Image.Resampling.LANCZOS)
                thumbnail_width, thumbnail_height = image.size
                
                print(f"Thumbnail dimensions: {thumbnail_width}x{thumbnail_height}")
                
                # Save thumbnail to bytes with higher quality
                buffer = io.BytesIO()
                
                # Use higher quality settings for better image clarity
                if content_type in ['image/png', 'image/PNG']:
                    # For PNG, use PNG format to maintain transparency and quality
                    image.save(buffer, "PNG", optimize=True)
                    thumbnail_content_type = "image/png"
                else:
                    # For JPEG and other formats, use JPEG with high quality
                    image.save(buffer, "JPEG", quality=90, optimize=True, progressive=True)
                    thumbnail_content_type = "image/jpeg"
                
                buffer.seek(0)
                
                # Upload thumbnail to S3
                s3.put_object(
                    Bucket=THUMBNAIL_BUCKET,
                    Key=target_key,
                    Body=buffer,
                    ContentType=thumbnail_content_type,
                    CacheControl="max-age=31536000",  # 1 year cache
                    Metadata={
                        'original-key': source_key,
                        'original-bucket': source_bucket,
                        'processed-time': datetime.utcnow().isoformat(),
                        'user-id': user_id,
                        'thumbnail-size': f"{thumbnail_width}x{thumbnail_height}",
                        'original-size': f"{original_width}x{original_height}"
                    }
                )
                
                print(f"Uploaded thumbnail: {target_key}")
                
                # Calculate file sizes
                original_size = len(image_content)
                thumbnail_size = len(buffer.getvalue())
                
                print(f"File sizes - Original: {original_size} bytes, Thumbnail: {thumbnail_size} bytes")
                
                # Store metadata in DynamoDB
                dynamodb_item = {
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
                    'thumbnail_content_type': thumbnail_content_type,
                    'status': 'processed',
                    'thumbnail_quality': 'high'  # Mark as high quality thumbnail
                }
                
                print(f"Storing DynamoDB item: {dynamodb_item}")
                
                table.put_item(Item=dynamodb_item)
                
                print(f"Stored metadata for image: {image_id}")
                
                # Create public URL for thumbnail
                # AWS_DEFAULT_REGION is automatically available in Lambda context
                region = os.environ.get('AWS_DEFAULT_REGION', 'eu-west-1')
                thumbnail_url = f"https://{THUMBNAIL_BUCKET}.s3.{region}.amazonaws.com/{target_key}"
                
                print(f"Successfully processed {source_key} -> {target_key}")
                print(f"Thumbnail URL: {thumbnail_url}")
                print(f"User ID: {user_id}")
                print(f"Quality: High ({thumbnail_width}x{thumbnail_height})")
                
            except Exception as e:
                print(f"Error processing {source_key}: {str(e)}")
                import traceback
                print(f"Full traceback: {traceback.format_exc()}")
                
                # Store error metadata
                try:
                    error_user_id = user_id if 'user_id' in locals() else 'unknown'
                    error_upload_time = upload_time if 'upload_time' in locals() else datetime.utcnow().isoformat()
                    
                    table.put_item(
                        Item={
                            'image_id': str(uuid.uuid4()),
                            'user_id': error_user_id,
                            'original_key': source_key,
                            'original_bucket': source_bucket,
                            'upload_time': error_upload_time,
                            'processed_time': datetime.utcnow().isoformat(),
                            'status': 'error',
                            'error_message': str(e)
                        }
                    )
                    print(f"Stored error metadata for failed processing")
                except Exception as db_error:
                    print(f"Failed to store error metadata: {db_error}")
                
                continue
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Images processed successfully',
                'processed_count': len(event['Records']),
                'thumbnail_quality': 'high',
                'max_thumbnail_size': 400
            })
        }
        
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        import traceback
        print(f"Full traceback: {traceback.format_exc()}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Error processing images',
                'message': str(e)
            })
        }