import json
import boto3
from boto3.dynamodb.conditions import Key
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
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
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
        }
        
        # Handle preflight requests
        if event['httpMethod'] == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': ''
            }
        
        # Get user ID from query parameters or path
        user_id = None
        
        # Try to get user_id from query parameters
        query_params = event.get('queryStringParameters') or {}
        user_id = query_params.get('user_id')
        
        # Try to get user_id from path parameters
        if not user_id:
            path_params = event.get('pathParameters') or {}
            user_id = path_params.get('user_id')
        
        # Try to get user_id from body (for POST requests)
        if not user_id and event.get('body'):
            try:
                body = json.loads(event['body'])
                user_id = body.get('user_id')
            except:
                pass
        
        print(f"Extracted user_id: {user_id}")
        
        if not user_id:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({
                    'error': 'user_id is required',
                    'message': 'Please provide user_id in query parameters, path, or request body',
                    'received_event': {
                        'queryStringParameters': query_params,
                        'pathParameters': event.get('pathParameters'),
                        'httpMethod': event['httpMethod']
                    }
                })
            }
        
        # Handle different HTTP methods
        if event['httpMethod'] == 'GET':
            return get_user_images(user_id, headers)
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
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
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
            scan_response = table.scan(Limit=10)
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