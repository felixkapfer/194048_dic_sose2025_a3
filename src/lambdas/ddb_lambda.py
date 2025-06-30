import json
import boto3
import os
from urllib.parse import unquote_plus
from datetime import datetime

# Initialize AWS clients
s3 = boto3.client('s3', endpoint_url=os.environ.get('AWS_ENDPOINT_URL'))
ssm = boto3.client('ssm', endpoint_url=os.environ.get('AWS_ENDPOINT_URL'))
dynamodb = boto3.resource('dynamodb', endpoint_url=os.environ.get('AWS_ENDPOINT_URL'))

def get_parameter(param_name):
    """Get parameter from SSM Parameter Store"""
    try:
        response = ssm.get_parameter(Name=f'/myapp/{param_name}')
        return response['Parameter']['Value']
    except Exception as e:
        print(f"Error getting parameter {param_name}: {str(e)}")
        raise

def update_user_stats(table, review_data):
    """Update user statistics in DynamoDB"""
    reviewer_id = review_data.get('reviewerID')
    if not reviewer_id:
        print("No reviewerID found in review")
        return False
    
    # Check if review contains profanity
    contains_profanity = review_data.get('profanity_check', {}).get('contains_profanity', False)
    
    # Get sentiment analysis results
    sentiment = review_data.get('sentiment_analysis', {}).get('overall_sentiment', 'neutral')
    
    try:
        # Get current user stats or create new entry
        response = table.get_item(Key={'reviewerID': reviewer_id})
        
        if 'Item' in response:
            # Update existing user
            current_item = response['Item']
            total_reviews = current_item.get('total_reviews', 0) + 1
            profanity_reviews = current_item.get('profanity_reviews', 0)
            positive_reviews = current_item.get('positive_reviews', 0)
            negative_reviews = current_item.get('negative_reviews', 0)
            neutral_reviews = current_item.get('neutral_reviews', 0)
            
            # Update profanity count
            if contains_profanity:
                profanity_reviews += 1
            
            # Update sentiment counts
            if sentiment == 'positive':
                positive_reviews += 1
            elif sentiment == 'negative':
                negative_reviews += 1
            else:
                neutral_reviews += 1
            
            # Check if user should be banned (more than 3 profanity reviews)
            is_banned = profanity_reviews > 3
            
        else:
            # New user
            total_reviews = 1
            profanity_reviews = 1 if contains_profanity else 0
            positive_reviews = 1 if sentiment == 'positive' else 0
            negative_reviews = 1 if sentiment == 'negative' else 0
            neutral_reviews = 1 if sentiment == 'neutral' else 0
            is_banned = False
        
        # Prepare item to save
        item = {
            'reviewerID': reviewer_id,
            'reviewerName': review_data.get('reviewerName', 'Unknown'),
            'total_reviews': total_reviews,
            'profanity_reviews': profanity_reviews,
            'positive_reviews': positive_reviews,
            'negative_reviews': negative_reviews,
            'neutral_reviews': neutral_reviews,
            'banned': is_banned,
            'last_review_time': datetime.utcnow().isoformat(),
            'last_review_category': review_data.get('category', 'Unknown')
        }
        
        # Add profane words list if user has any
        if profanity_reviews > 0:
            # Get existing profane words list
            existing_words = current_item.get('all_profane_words', []) if 'Item' in response else []
            new_words = review_data.get('profanity_check', {}).get('profane_words_found', [])
            # Combine and remove duplicates
            all_words = list(set(existing_words + new_words))
            item['all_profane_words'] = all_words
        
        # Save to DynamoDB
        table.put_item(Item=item)
        
        print(f"Updated stats for user {reviewer_id}: "
              f"Total: {total_reviews}, Profanity: {profanity_reviews}, "
              f"Banned: {is_banned}")
        
        return True
        
    except Exception as e:
        print(f"Error updating user stats: {str(e)}")
        return False

def get_banned_users_count(table):
    """Count total number of banned users"""
    try:
        response = table.scan(
            FilterExpression='banned = :val',
            ExpressionAttributeValues={':val': True}
        )
        return response.get('Count', 0)
    except Exception as e:
        print(f"Error counting banned users: {str(e)}")
        return 0

def process_single_review(bucket, key, table):
    """Process a single review and update DynamoDB"""
    try:
        print(f"Processing: {key} from bucket: {bucket}")
        
        # Download the review from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        review_content = response['Body'].read().decode('utf-8')
        review = json.loads(review_content)
        
        # Update user statistics
        success = update_user_stats(table, review)
        
        return success
        
    except Exception as e:
        print(f"Error processing review {key}: {str(e)}")
        return False

def lambda_handler(event, context):
    """Main Lambda handler"""
    print(f"Event received: {json.dumps(event)}")
    
    successful = 0
    failed = 0
    
    try:
        # Get table name from SSM
        table_name = get_parameter('user_reviews_table')
        table = dynamodb.Table(table_name)
        
        # Parse S3 event
        for record in event['Records']:
            # Get the object key and bucket
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            # Skip if not in sentiment folder
            if not key.startswith('sentiment/'):
                print(f"Skipping {key} - not in sentiment folder")
                continue
            
            # Process the review
            if process_single_review(bucket, key, table):
                successful += 1
            else:
                failed += 1
        
        # Get total banned users count
        banned_count = get_banned_users_count(table)
        
        # Get overall statistics
        try:
            scan_response = table.scan()
            total_users = scan_response.get('Count', 0)
            
            # Calculate aggregated stats
            total_profanity_reviews = sum(
                item.get('profanity_reviews', 0) 
                for item in scan_response.get('Items', [])
            )
            
        except:
            total_users = 0
            total_profanity_reviews = 0
        
        result_message = (f"DynamoDB update completed. "
                         f"Successful: {successful}, Failed: {failed}. "
                         f"Total banned users: {banned_count}/{total_users}. "
                         f"Total profanity reviews: {total_profanity_reviews}")
        print(result_message)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': result_message,
                'successful': successful,
                'failed': failed,
                'banned_users_count': banned_count,
                'total_users': total_users,
                'total_profanity_reviews': total_profanity_reviews
            })
        }
        
    except Exception as e:
        print(f"Lambda execution error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Lambda execution error: {str(e)}')
        }