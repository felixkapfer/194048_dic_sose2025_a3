#!/usr/bin/env python3
"""
Manual pipeline runner for LocalStack
Works around the S3 notification limitation
"""
import boto3
import json
import time
import sys

# Initialize clients
s3 = boto3.client('s3', endpoint_url='http://localstack:4566', region_name='us-east-1')
lambda_client = boto3.client('lambda', endpoint_url='http://localstack:4566', region_name='us-east-1')

def process_single_review(key):
    """Process a single review through all Lambda functions"""
    print(f"\nProcessing: {key}")
    
    # 1. Call preprocessing_lambda
    print("  → Calling preprocessing_lambda...")
    payload = {
        "Records": [{
            "s3": {
                "bucket": {"name": "reviews-bucket"},
                "object": {"key": key}
            }
        }]
    }
    
    response = lambda_client.invoke(
        FunctionName='preprocessing_lambda',
        InvocationType='RequestResponse',
        Payload=json.dumps(payload)
    )
    
    if response['StatusCode'] != 200:
        print(f"  ✗ preprocessing_lambda failed: {response}")
        return False
    print("  ✓ preprocessing_lambda completed")
    
    # 2. Call profanity_lambda  
    preprocessed_key = key.replace('raw/', 'preprocessed/')
    print("  → Calling profanity_lambda...")
    payload['Records'][0]['s3']['object']['key'] = preprocessed_key
    
    response = lambda_client.invoke(
        FunctionName='profanity_lambda',
        InvocationType='RequestResponse',
        Payload=json.dumps(payload)
    )
    
    if response['StatusCode'] != 200:
        print(f"  ✗ profanity_lambda failed: {response}")
        return False
    print("  ✓ profanity_lambda completed")
    
    # 3. Call sentiment_lambda
    profanity_key = preprocessed_key.replace('preprocessed/', 'profanity/')
    print("  → Calling sentiment_lambda...")
    payload['Records'][0]['s3']['object']['key'] = profanity_key
    
    response = lambda_client.invoke(
        FunctionName='sentiment_lambda',
        InvocationType='RequestResponse',
        Payload=json.dumps(payload)
    )
    
    if response['StatusCode'] != 200:
        print(f"  ✗ sentiment_lambda failed: {response}")
        return False
    print("  ✓ sentiment_lambda completed")
    
    # 4. Call ddb_lambda
    sentiment_key = profanity_key.replace('profanity/', 'sentiment/')
    print("  → Calling ddb_lambda...")
    payload['Records'][0]['s3']['object']['key'] = sentiment_key
    
    response = lambda_client.invoke(
        FunctionName='ddb_lambda',
        InvocationType='RequestResponse',
        Payload=json.dumps(payload)
    )
    
    if response['StatusCode'] != 200:
        print(f"  ✗ ddb_lambda failed: {response}")
        return False
    print("  ✓ ddb_lambda completed")
    
    return True

def main():
    """Process all reviews in raw/ folder"""
    print("Manual Pipeline Runner")
    print("======================")
    
    # List all files in raw/
    try:
        response = s3.list_objects_v2(Bucket='reviews-bucket', Prefix='raw/')
        
        if 'Contents' not in response:
            print("No files found in raw/ folder")
            return
        
        files = response['Contents']
        print(f"Found {len(files)} files to process")
        
        successful = 0
        failed = 0
        
        for obj in files:
            key = obj['Key']
            if process_single_review(key):
                successful += 1
            else:
                failed += 1
            
            # Small delay to avoid overwhelming LocalStack
            time.sleep(0.5)
        
        print(f"\n{'='*50}")
        print(f"Pipeline Complete!")
        print(f"Successful: {successful}")
        print(f"Failed: {failed}")
        print(f"{'='*50}")
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return 1
    
    return 0

if __name__ == '__main__':
    sys.exit(main())