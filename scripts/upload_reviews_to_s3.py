#!/usr/bin/env python3
"""
Upload reviews from dataset to S3 to start the processing pipeline
"""

import json
import boto3
import os
import sys
import time

# Initialize S3 client
s3 = boto3.client('s3', endpoint_url=os.environ.get('AWS_ENDPOINT_URL', 'http://localstack:4566'))

def upload_reviews(dataset_path, bucket_name, max_reviews=None):
    """Upload reviews from dataset file to S3"""
    
    if not os.path.exists(dataset_path):
        print(f"Error: Dataset file not found: {dataset_path}")
        return False
    
    print(f"Reading reviews from: {dataset_path}")
    
    uploaded = 0
    failed = 0
    
    try:
        with open(dataset_path, 'r') as f:
            # Read file line by line (each line is a JSON object)
            for line_num, line in enumerate(f, 1):
                if max_reviews and uploaded >= max_reviews:
                    break
                
                try:
                    # Parse JSON
                    review = json.loads(line.strip())
                    
                    # Create key for S3 (using zero-padded numbers)
                    key = f"raw/review_{line_num:06d}.json"
                    
                    # Upload to S3
                    s3.put_object(
                        Bucket=bucket_name,
                        Key=key,
                        Body=json.dumps(review),
                        ContentType='application/json'
                    )
                    
                    uploaded += 1
                    print(f"Uploaded: {key} - ReviewerID: {review.get('reviewerID', 'Unknown')}")
                    
                    # Small delay to avoid overwhelming LocalStack
                    if uploaded % 10 == 0:
                        time.sleep(0.1)
                    
                except json.JSONDecodeError as e:
                    print(f"Error parsing JSON on line {line_num}: {e}")
                    failed += 1
                except Exception as e:
                    print(f"Error uploading review {line_num}: {e}")
                    failed += 1
        
        print(f"\nUpload complete!")
        print(f"Successfully uploaded: {uploaded} reviews")
        print(f"Failed: {failed} reviews")
        
        return True
        
    except Exception as e:
        print(f"Error reading dataset file: {e}")
        return False

def main():
    """Main function"""
    # Default values
    bucket_name = 'reviews-bucket'
    dataset_path = '/app/data/reviews_devset.json'
    
    # Check if custom dataset path provided
    if len(sys.argv) > 1:
        dataset_path = sys.argv[1]
    
    # Check if custom max reviews provided
    max_reviews = None
    if len(sys.argv) > 2:
        try:
            max_reviews = int(sys.argv[2])
            print(f"Limiting upload to {max_reviews} reviews")
        except ValueError:
            print("Warning: Invalid max_reviews value, uploading all reviews")
    
    print(f"Starting review upload to S3...")
    print(f"Bucket: {bucket_name}")
    print(f"Dataset: {dataset_path}")
    print(f"AWS Endpoint: {os.environ.get('AWS_ENDPOINT_URL', 'http://localstack:4566')}")
    print()
    
    # Verify bucket exists
    try:
        s3.head_bucket(Bucket=bucket_name)
    except:
        print(f"Error: Bucket '{bucket_name}' does not exist!")
        print("Please create the bucket first using the setup script.")
        return 1
    
    # Upload reviews
    if upload_reviews(dataset_path, bucket_name, max_reviews):
        return 0
    else:
        return 1

if __name__ == '__main__':
    sys.exit(main())