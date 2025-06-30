import json
import boto3
from boto3.dynamodb.conditions import Key
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')
table = dynamodb.Table(os.environ['METADATA_TABLE'])

def decimal_default(obj):
    """JSON serializer for DynamoDB Decimal types"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def lambda_handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    try:
        # Enable CORS
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS'
        }
        
        # Handle preflight requests
        if event['httpMethod'] == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': ''
            }
        
        # Get user ID from path parameters
        path_params = event.get('pathParameters') or {}
        user_id = path_params.get('user_id')
        
        if not user_id:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({
                    'error': 'user_id is required',
                    'message': 'Please provide user_id in path parameters',
                    'received_event': {
                        'pathParameters': path_params,
                        'httpMethod': event['httpMethod']
                    }
                })
            }
        
        # Handle different HTTP methods
        if event['httpMethod'] == 'GET':
            return get_user_images(user_id, headers)
        elif event['httpMethod'] == 'DELETE':
            image_id = path_params.get('image_id')
            if not image_id:
                return {
                    'statusCode': 400,
                    'headers': headers,
                    'body': json.dumps({
                        'error': 'image_id is required for DELETE operation',
                        'message': 'Please provide image_id in path parameters'
                    })
                }
            return delete_user_image(user_id, image_id, headers)
        else:
            return {
                'statusCode': 405,
                'headers': headers,
                'body': json.dumps({'error': 'Method not allowed'})
            }
            
    except Exception as e:
        print(f"Error: {str(e)}")
        import traceback
        print(f"Full traceback: {traceback.format_exc()}")
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }

def get_user_images(user_id, headers):
    """Fetch all images for a specific user"""
    try:
        print(f"Querying DynamoDB for user_id: {user_id}")
        
        # First, let's try to scan all items to see what's in the table (for debugging)
        try:
            scan_response = table.scan(Limit=5)
            print(f"Sample items in table: {scan_response.get('Items', [])}")
        except Exception as scan_error:
            print(f"Error scanning table: {scan_error}")
        
        # Query DynamoDB for user's images using GSI
        try:
            response = table.query(
                IndexName='user-id-index',
                KeyConditionExpression=Key('user_id').eq(user_id),
                ScanIndexForward=False,  # Sort by sort key descending (newest first)
                FilterExpression='attribute_exists(thumbnail_key) AND #status = :status',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={':status': 'processed'}
            )
            print(f"Query response: {response}")
        except Exception as query_error:
            print(f"GSI query failed: {query_error}")
            # Try a scan as fallback
            print(f"Trying scan as fallback...")
            response = table.scan(
                FilterExpression='user_id = :user_id AND attribute_exists(thumbnail_key) AND #status = :status',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':user_id': user_id,
                    ':status': 'processed'
                }
            )
            print(f"Scan response: {response}")
        
        images = response['Items']
        print(f"Found {len(images)} images for user {user_id}")
        
        # Process images to add thumbnail URLs and format data
        processed_images = []
        thumbnail_bucket = os.environ.get('THUMBNAIL_BUCKET')
        # AWS_DEFAULT_REGION is available in Lambda, or use fallback
        region = os.environ.get('AWS_DEFAULT_REGION', 'eu-west-1')
        
        for image in images:
            print(f"Processing image: {image}")
            
            thumbnail_url = f"https://{thumbnail_bucket}.s3.{region}.amazonaws.com/{image['thumbnail_key']}"
            
            processed_image = {
                'id': image['image_id'],
                'originalKey': image['original_key'],
                'thumbnailKey': image['thumbnail_key'],
                'thumbnailUrl': thumbnail_url,
                'originalName': image.get('original_name', image['original_key']),
                'uploadTime': image['upload_time'],
                'processedTime': image.get('processed_time'),
                'size': image.get('original_size', 0),
                'originalWidth': image.get('original_width'),
                'originalHeight': image.get('original_height'),
                'thumbnailWidth': image.get('thumbnail_width'),
                'thumbnailHeight': image.get('thumbnail_height'),
                'contentType': image.get('content_type', 'image/jpeg')
            }
            
            processed_images.append(processed_image)
            print(f"Processed image: {processed_image}")
        
        # Sort by upload time (newest first)
        processed_images.sort(key=lambda x: x['uploadTime'], reverse=True)
        
        result = {
            'images': processed_images,
            'count': len(processed_images),
            'user_id': user_id
        }
        
        print(f"Returning result: {result}")
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps(result, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error fetching images for user {user_id}: {str(e)}")
        import traceback
        print(f"Full traceback: {traceback.format_exc()}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': 'Failed to fetch images',
                'message': str(e),
                'user_id': user_id
            })
        }

def delete_user_image(user_id, image_id, headers):
    """Delete a specific image for a user"""
    try:
        print(f"Deleting image {image_id} for user {user_id}")
        
        # First, get the image metadata to find the thumbnail key
        try:
            # Try to find the image by image_id first
            response = table.scan(
                FilterExpression='image_id = :image_id AND user_id = :user_id',
                ExpressionAttributeValues={
                    ':image_id': image_id,
                    ':user_id': user_id
                }
            )
            
            items = response.get('Items', [])
            if not items:
                # If not found by image_id, try finding by original_key (for backward compatibility)
                response = table.scan(
                    FilterExpression='original_key = :original_key AND user_id = :user_id',
                    ExpressionAttributeValues={
                        ':original_key': image_id,  # image_id might actually be the original_key
                        ':user_id': user_id
                    }
                )
                items = response.get('Items', [])
            
            if not items:
                print(f"Image not found: {image_id} for user {user_id}")
                return {
                    'statusCode': 404,
                    'headers': headers,
                    'body': json.dumps({
                        'error': 'Image not found',
                        'message': f'Image {image_id} not found for user {user_id}'
                    })
                }
            
            image_metadata = items[0]
            print(f"Found image metadata: {image_metadata}")
            
            # Delete thumbnail from S3 if it exists
            thumbnail_bucket = os.environ.get('THUMBNAIL_BUCKET')
            thumbnail_key = image_metadata.get('thumbnail_key')
            
            if thumbnail_bucket and thumbnail_key:
                try:
                    s3.delete_object(Bucket=thumbnail_bucket, Key=thumbnail_key)
                    print(f"Deleted thumbnail from S3: {thumbnail_key}")
                except Exception as s3_error:
                    print(f"Error deleting thumbnail from S3: {s3_error}")
                    # Continue with metadata deletion even if S3 delete fails
            
            # Delete metadata from DynamoDB
            try:
                table.delete_item(
                    Key={'image_id': image_metadata['image_id']}
                )
                print(f"Deleted metadata from DynamoDB: {image_metadata['image_id']}")
            except Exception as db_error:
                print(f"Error deleting from DynamoDB: {db_error}")
                return {
                    'statusCode': 500,
                    'headers': headers,
                    'body': json.dumps({
                        'error': 'Failed to delete image metadata',
                        'message': str(db_error)
                    })
                }
            
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({
                    'message': 'Image deleted successfully',
                    'deleted_image_id': image_metadata['image_id'],
                    'deleted_thumbnail_key': thumbnail_key
                })
            }
            
        except Exception as e:
            print(f"Error in delete process: {str(e)}")
            import traceback
            print(f"Full traceback: {traceback.format_exc()}")
            return {
                'statusCode': 500,
                'headers': headers,
                'body': json.dumps({
                    'error': 'Failed to delete image',
                    'message': str(e)
                })
            }
            
    except Exception as e:
        print(f"Error deleting image {image_id} for user {user_id}: {str(e)}")
        import traceback
        print(f"Full traceback: {traceback.format_exc()}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': 'Failed to delete image',
                'message': str(e),
                'user_id': user_id,
                'image_id': image_id
            })
        }