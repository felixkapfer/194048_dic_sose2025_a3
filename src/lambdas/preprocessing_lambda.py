import json
import boto3
import os
import re
from urllib.parse import unquote_plus
import nltk
from nltk.tokenize import word_tokenize
from nltk.corpus import stopwords
from nltk.stem import WordNetLemmatizer

# Initialize AWS clients
s3 = boto3.client('s3', endpoint_url=os.environ.get('AWS_ENDPOINT_URL'))
ssm = boto3.client('ssm', endpoint_url=os.environ.get('AWS_ENDPOINT_URL'))

# Set NLTK data path (include data in the deployment package)
nltk.data.path.append('/opt/nltk_data')
nltk.data.path.append('./nltk_data_minimal')
nltk.data.path.append('./nltk_data_minimal')

# Initialize NLTK components
try:
    lemmatizer = WordNetLemmatizer()
    stop_words = set(stopwords.words('english'))
except Exception as e:
    print(f"Error initializing NLTK components: {e}")
    # Fallback if NLTK data not found
    lemmatizer = None
    stop_words = set()

def get_parameter(param_name):
    """Get parameter from SSM Parameter Store"""
    try:
        response = ssm.get_parameter(Name=f'/myapp/{param_name}')
        return response['Parameter']['Value']
    except Exception as e:
        print(f"Error getting parameter {param_name}: {str(e)}")
        raise

def preprocess_text(text):
    """
    Preprocess text with comprehensive cleaning:
    - Convert to lowercase
    - Remove URLs, emails, special characters
    - Handle numbers
    - Tokenization
    - Stop word removal
    - Lemmatization
    """
    if not text:
        return ""
    
    # Convert to lowercase
    text = text.lower()
    
    # Remove URLs
    text = re.sub(r'http[s]?://(?:[a-zA-Z]|[0-9]|[$-_@.&+]|[!*\\(\\),]|(?:%[0-9a-fA-F][0-9a-fA-F]))+', '', text)
    
    # Remove email addresses
    text = re.sub(r'\S+@\S+', '', text)
    
    # Replace numbers with 'NUM' token
    text = re.sub(r'\d+', 'NUM', text)
    
    # Remove special characters but keep spaces
    text = re.sub(r'[^a-zA-Z\s]', ' ', text)
    
    # Remove extra whitespaces
    text = ' '.join(text.split())
    
    # Tokenization
    try:
        tokens = word_tokenize(text)
    except:
        # Fallback to simple split if tokenization fails
        tokens = text.split()
    
    # Remove stop words and lemmatize
    processed_tokens = []
    for token in tokens:
        if len(token) > 2 and token not in stop_words:  # Keep words longer than 2 chars
            if lemmatizer:
                try:
                    lemmatized = lemmatizer.lemmatize(token)
                    processed_tokens.append(lemmatized)
                except:
                    processed_tokens.append(token)
            else:
                processed_tokens.append(token)
    
    return ' '.join(processed_tokens)

def process_single_review(bucket, key):
    """Process a single review file"""
    try:
        print(f"Processing: {key} from bucket: {bucket}")
        
        # Download the review from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        review_content = response['Body'].read().decode('utf-8')
        review = json.loads(review_content)
        
        # Preprocess reviewText and summary
        preprocessed_text = preprocess_text(review.get('reviewText', ''))
        preprocessed_summary = preprocess_text(review.get('summary', ''))
        
        # Add preprocessed fields to the review
        review['preprocessed_text'] = preprocessed_text
        review['preprocessed_summary'] = preprocessed_summary
        
        # Add processing metadata
        review['processing_stage'] = 'preprocessed'
        
        # Create the new key for preprocessed data
        new_key = key.replace('raw/', 'preprocessed/')
        
        # Upload to preprocessed folder
        s3.put_object(
            Bucket=bucket,
            Key=new_key,
            Body=json.dumps(review),
            ContentType='application/json'
        )
        
        print(f"Successfully preprocessed and saved to: {new_key}")
        return True
        
    except Exception as e:
        print(f"Error processing review {key}: {str(e)}")
        return False

def lambda_handler(event, context):
    """Main Lambda handler"""
    print(f"Event received: {json.dumps(event)}")
    
    successful = 0
    failed = 0
    
    try:
        # Get bucket names from SSM
        source_bucket = get_parameter('bucket')
        
        # Parse S3 event
        for record in event['Records']:
            # Get the object key and bucket
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            # Skip if not in raw folder
            if not key.startswith('raw/'):
                print(f"Skipping {key} - not in raw folder")
                continue
            
            # Process the review
            if process_single_review(bucket, key):
                successful += 1
            else:
                failed += 1
        
        result_message = f"Preprocessing completed. Successful: {successful}, Failed: {failed}"
        print(result_message)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': result_message,
                'successful': successful,
                'failed': failed
            })
        }
        
    except Exception as e:
        print(f"Lambda execution error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Lambda execution error: {str(e)}')
        }