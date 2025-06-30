import json
import boto3
import os
from urllib.parse import unquote_plus
from better_profanity import profanity
import re

# Initialize AWS clients
s3 = boto3.client('s3', endpoint_url=os.environ.get('AWS_ENDPOINT_URL'))
ssm = boto3.client('ssm', endpoint_url=os.environ.get('AWS_ENDPOINT_URL'))
lambda_client = boto3.client('lambda', endpoint_url=os.environ.get('AWS_ENDPOINT_URL'))

# Initialize profanity checker
profanity.load_censor_words()

def get_parameter(param_name):
    """Get parameter from SSM Parameter Store"""
    try:
        response = ssm.get_parameter(Name=f'/myapp/{param_name}')
        return response['Parameter']['Value']
    except Exception as e:
        print(f"Error getting parameter {param_name}: {str(e)}")
        raise

def check_profanity(text):
    """
    Check if text contains profanity and extract the actual profane words
    Returns: (contains_profanity: bool, profane_words: list, profanity_count: int)
    """
    if not text:
        return False, [], 0
    
    # Check if text contains profanity
    contains_profanity = profanity.contains_profanity(text)
    
    # Extract the actual profane words
    profane_words = []
    if contains_profanity:
        # Split text into words and check each
        words = text.split()
        for word in words:
            # Clean the word from punctuation for checking
            clean_word = re.sub(r'[^\w\s]', '', word.lower())
            if clean_word and profanity.contains_profanity(clean_word):
                profane_words.append(word)  # Keep original form
    
    # Remove duplicates while preserving order
    seen = set()
    unique_profane_words = []
    for word in profane_words:
        word_lower = word.lower()
        if word_lower not in seen:
            seen.add(word_lower)
            unique_profane_words.append(word)
    
    return contains_profanity, unique_profane_words, len(unique_profane_words)

def invoke_next_lambda(bucket, key):
    """Invoke the next Lambda in the chain (sentiment_lambda)"""
    try:
        print(f"Invoking sentiment_lambda for {key}")
        
        payload = {
            "Records": [{
                "s3": {
                    "bucket": {"name": bucket},
                    "object": {"key": key}
                }
            }]
        }
        
        response = lambda_client.invoke(
            FunctionName='sentiment_lambda',
            InvocationType='Event',  # Asynchronous
            Payload=json.dumps(payload)
        )
        
        if response['StatusCode'] in [200, 202]:
            print("Successfully invoked sentiment_lambda")
        else:
            print(f"Failed to invoke sentiment_lambda: {response}")
            
    except Exception as e:
        print(f"Error invoking next lambda: {str(e)}")

def process_single_review(bucket, key):
    """Process a single review file for profanity"""
    try:
        print(f"Processing: {key} from bucket: {bucket}")
        
        # Download the review from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        review_content = response['Body'].read().decode('utf-8')
        review = json.loads(review_content)
        
        # Check profanity in different fields
        # Original text fields
        review_text_profanity, review_text_words, review_text_count = check_profanity(
            review.get('reviewText', '')
        )
        summary_profanity, summary_words, summary_count = check_profanity(
            review.get('summary', '')
        )
        
        # Preprocessed text fields (if they exist)
        preprocessed_text_profanity = False
        preprocessed_text_words = []
        preprocessed_summary_profanity = False
        preprocessed_summary_words = []
        
        if 'preprocessed_text' in review:
            preprocessed_text_profanity, preprocessed_text_words, _ = check_profanity(
                review.get('preprocessed_text', '')
            )
        if 'preprocessed_summary' in review:
            preprocessed_summary_profanity, preprocessed_summary_words, _ = check_profanity(
                review.get('preprocessed_summary', '')
            )
        
        # Determine if review contains any profanity
        contains_profanity = any([
            review_text_profanity,
            summary_profanity,
            preprocessed_text_profanity,
            preprocessed_summary_profanity
        ])
        
        # Combine all found profane words
        all_profane_words = list(set(
            review_text_words + 
            summary_words + 
            preprocessed_text_words + 
            preprocessed_summary_words
        ))
        
        # Add profanity check results to review
        review['profanity_check'] = {
            'contains_profanity': contains_profanity,
            'review_text_has_profanity': review_text_profanity,
            'summary_has_profanity': summary_profanity,
            'profanity_count': len(all_profane_words),
            'profane_words_found': all_profane_words,
            'profane_words_in_review_text': review_text_words,
            'profane_words_in_summary': summary_words
        }
        
        # Update processing stage
        review['processing_stage'] = 'profanity_checked'
        
        # Create the new key for profanity-checked data
        new_key = key.replace('preprocessed/', 'profanity/')
        
        # Upload to profanity folder
        s3.put_object(
            Bucket=bucket,
            Key=new_key,
            Body=json.dumps(review),
            ContentType='application/json'
        )
        
        print(f"Successfully checked profanity and saved to: {new_key}")
        print(f"Contains profanity: {contains_profanity}")
        if contains_profanity:
            print(f"Profane words found: {all_profane_words}")
        
        # INVOKE NEXT LAMBDA IN CHAIN
        invoke_next_lambda(bucket, new_key)
        
        return True
        
    except Exception as e:
        print(f"Error processing review {key}: {str(e)}")
        return False

def lambda_handler(event, context):
    """Main Lambda handler"""
    print(f"Event received: {json.dumps(event)}")
    
    successful = 0
    failed = 0
    profanity_found = 0
    
    try:
        # Get bucket name from SSM
        bucket_name = get_parameter('profanity_bucket')
        
        # Parse S3 event
        for record in event['Records']:
            # Get the object key and bucket
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            # Skip if not in preprocessed folder
            if not key.startswith('preprocessed/'):
                print(f"Skipping {key} - not in preprocessed folder")
                continue
            
            # Process the review
            if process_single_review(bucket, key):
                successful += 1
                
                # Check if profanity was found (for statistics)
                try:
                    response = s3.get_object(
                        Bucket=bucket,
                        Key=key.replace('preprocessed/', 'profanity/')
                    )
                    review = json.loads(response['Body'].read().decode('utf-8'))
                    if review.get('profanity_check', {}).get('contains_profanity', False):
                        profanity_found += 1
                except:
                    pass
            else:
                failed += 1
        
        result_message = f"Profanity check completed. Successful: {successful}, Failed: {failed}, With profanity: {profanity_found}"
        print(result_message)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': result_message,
                'successful': successful,
                'failed': failed,
                'profanity_found': profanity_found
            })
        }
        
    except Exception as e:
        print(f"Lambda execution error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Lambda execution error: {str(e)}')
        }