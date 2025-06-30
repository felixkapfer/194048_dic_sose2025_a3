import json
import boto3
import os
from urllib.parse import unquote_plus
from textblob import TextBlob

# Initialize AWS clients
s3 = boto3.client('s3', endpoint_url=os.environ.get('AWS_ENDPOINT_URL'))
ssm = boto3.client('ssm', endpoint_url=os.environ.get('AWS_ENDPOINT_URL'))

def get_parameter(param_name):
    """Get parameter from SSM Parameter Store"""
    try:
        response = ssm.get_parameter(Name=f'/myapp/{param_name}')
        return response['Parameter']['Value']
    except Exception as e:
        print(f"Error getting parameter {param_name}: {str(e)}")
        raise

def analyze_sentiment(text):
    """
    Analyze sentiment of text using TextBlob
    Returns: (polarity, subjectivity, sentiment_label)
    - polarity: -1 (negative) to 1 (positive)
    - subjectivity: 0 (objective) to 1 (subjective)
    - sentiment_label: 'positive', 'negative', or 'neutral'
    """
    if not text:
        return 0.0, 0.0, 'neutral'
    
    try:
        # Create TextBlob object
        blob = TextBlob(text)
        
        # Get sentiment scores
        polarity = blob.sentiment.polarity
        subjectivity = blob.sentiment.subjectivity
        
        # Determine sentiment label
        if polarity > 0.1:
            sentiment_label = 'positive'
        elif polarity < -0.1:
            sentiment_label = 'negative'
        else:
            sentiment_label = 'neutral'
        
        return polarity, subjectivity, sentiment_label
        
    except Exception as e:
        print(f"Error analyzing sentiment: {str(e)}")
        return 0.0, 0.0, 'neutral'

def process_single_review(bucket, key):
    """Process a single review file for sentiment analysis"""
    try:
        print(f"Processing: {key} from bucket: {bucket}")
        
        # Download the review from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        review_content = response['Body'].read().decode('utf-8')
        review = json.loads(review_content)
        
        # Analyze sentiment for different text fields
        # Original review text
        review_polarity, review_subjectivity, review_sentiment = analyze_sentiment(
            review.get('reviewText', '')
        )
        
        # Summary
        summary_polarity, summary_subjectivity, summary_sentiment = analyze_sentiment(
            review.get('summary', '')
        )
        
        # Preprocessed text (if available)
        preprocessed_polarity, preprocessed_subjectivity, preprocessed_sentiment = 0.0, 0.0, 'neutral'
        if 'preprocessed_text' in review:
            preprocessed_polarity, preprocessed_subjectivity, preprocessed_sentiment = analyze_sentiment(
                review.get('preprocessed_text', '')
            )
        
        # Calculate overall sentiment (weighted average)
        # Give more weight to review text than summary
        total_weight = 0
        weighted_polarity = 0
        
        if review.get('reviewText'):
            weighted_polarity += review_polarity * 0.7
            total_weight += 0.7
        
        if review.get('summary'):
            weighted_polarity += summary_polarity * 0.3
            total_weight += 0.3
        
        overall_polarity = weighted_polarity / total_weight if total_weight > 0 else 0.0
        
        # Determine overall sentiment
        if overall_polarity > 0.1:
            overall_sentiment = 'positive'
        elif overall_polarity < -0.1:
            overall_sentiment = 'negative'
        else:
            overall_sentiment = 'neutral'
        
        # Compare with the 'overall' rating if present
        rating = review.get('overall', 0)
        rating_sentiment = 'neutral'
        if rating >= 4:
            rating_sentiment = 'positive'
        elif rating <= 2:
            rating_sentiment = 'negative'
        else:
            rating_sentiment = 'neutral'
        
        # Check for sentiment mismatch
        sentiment_matches_rating = (overall_sentiment == rating_sentiment)
        
        # Add sentiment analysis results to review
        review['sentiment_analysis'] = {
            'overall_sentiment': overall_sentiment,
            'overall_polarity': round(overall_polarity, 3),
            'review_text_sentiment': review_sentiment,
            'review_text_polarity': round(review_polarity, 3),
            'review_text_subjectivity': round(review_subjectivity, 3),
            'summary_sentiment': summary_sentiment,
            'summary_polarity': round(summary_polarity, 3),
            'summary_subjectivity': round(summary_subjectivity, 3),
            'preprocessed_sentiment': preprocessed_sentiment,
            'preprocessed_polarity': round(preprocessed_polarity, 3),
            'sentiment_matches_rating': sentiment_matches_rating,
            'rating_sentiment': rating_sentiment
        }
        
        # Update processing stage
        review['processing_stage'] = 'sentiment_analyzed'
        
        # Create the new key for sentiment-analyzed data
        new_key = key.replace('profanity/', 'sentiment/')
        
        # Upload to sentiment folder
        s3.put_object(
            Bucket=bucket,
            Key=new_key,
            Body=json.dumps(review),
            ContentType='application/json'
        )
        
        print(f"Successfully analyzed sentiment and saved to: {new_key}")
        print(f"Overall sentiment: {overall_sentiment} (polarity: {overall_polarity:.3f})")
        return True, overall_sentiment
        
    except Exception as e:
        print(f"Error processing review {key}: {str(e)}")
        return False, None

def lambda_handler(event, context):
    """Main Lambda handler"""
    print(f"Event received: {json.dumps(event)}")
    
    successful = 0
    failed = 0
    sentiment_counts = {
        'positive': 0,
        'negative': 0,
        'neutral': 0
    }
    
    try:
        # Get bucket name from SSM
        bucket_name = get_parameter('sentiment_bucket')
        
        # Parse S3 event
        for record in event['Records']:
            # Get the object key and bucket
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            # Skip if not in profanity folder
            if not key.startswith('profanity/'):
                print(f"Skipping {key} - not in profanity folder")
                continue
            
            # Process the review
            success, sentiment = process_single_review(bucket, key)
            if success:
                successful += 1
                if sentiment:
                    sentiment_counts[sentiment] += 1
            else:
                failed += 1
        
        result_message = (f"Sentiment analysis completed. "
                         f"Successful: {successful}, Failed: {failed}. "
                         f"Positive: {sentiment_counts['positive']}, "
                         f"Negative: {sentiment_counts['negative']}, "
                         f"Neutral: {sentiment_counts['neutral']}")
        print(result_message)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': result_message,
                'successful': successful,
                'failed': failed,
                'sentiment_counts': sentiment_counts
            })
        }
        
    except Exception as e:
        print(f"Lambda execution error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Lambda execution error: {str(e)}')
        }