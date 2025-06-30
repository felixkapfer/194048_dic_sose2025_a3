#!/bin/bash

# workflows.sh - AWS CLI tasks for the assignment

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/utils.sh"

# Define endpoint and region
ENDPOINT="--endpoint-url=http://localhost:4566"
REGION="--region us-east-1"

create_s3_and_dynamodb() {
    print_header "Creating S3 Bucket and DynamoDB Table"
    aws $ENDPOINT $REGION s3 mb s3://reviews-bucket && success "S3 Bucket created."
    aws $ENDPOINT $REGION dynamodb create-table \
        --table-name user_reviews \
        --attribute-definitions AttributeName=reviewerID,AttributeType=S \
        --key-schema AttributeName=reviewerID,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
        && success "DynamoDB Table created."
}

set_ssm_parameters() {
    print_header "Setting SSM Parameters"
    for param in bucket processed_bucket user_reviews_table profanity_bucket sentiment_bucket; do
        value="reviews-bucket"
        [ "$param" = "user_reviews_table" ] && value="user_reviews"
        aws $ENDPOINT $REGION ssm put-parameter \
            --name "/myapp/$param" \
            --value "$value" \
            --type String \
            && success "Parameter /myapp/$param set."
    done
}

deploy_lambdas() {
    print_header "Deploying Lambda Functions"
    LAMBDA_DIR="${script_dir}/assignment_3/lambdas"
    for fn in preprocessing profanity sentiment ddb; do
        aws $ENDPOINT $REGION lambda create-function \
            --function-name "${fn}_lambda" \
            --runtime python3.11 \
            --handler "${fn}_lambda.lambda_handler" \
            --role arn:aws:iam::000000000000:role/lambda-role \
            --zip-file "fileb://${LAMBDA_DIR}/${fn}_lambda.zip" \
            && success "Lambda ${fn}_lambda deployed."
    done
}

set_lambda_permissions() {
    print_header "Setting Lambda Permissions"
    for fn in preprocessing profanity sentiment ddb; do
        aws $ENDPOINT $REGION lambda add-permission \
            --function-name "${fn}_lambda" \
            --statement-id "s3invoke-${fn}" \
            --action "lambda:InvokeFunction" \
            --principal s3.amazonaws.com \
            --source-arn arn:aws:s3:::reviews-bucket \
            && success "Permission added to ${fn}_lambda."
    done
}

set_s3_notifications() {
    print_header "Configuring S3 Bucket Notifications"
    aws $ENDPOINT $REGION s3api put-bucket-notification-configuration \
        --bucket reviews-bucket \
        --notification-configuration file://notification-config.json \
        && success "S3 notification configuration applied."
}

start_pipeline() {
    print_header "Uploading Reviews to S3 (Pipeline Start)"
    python upload_reviews_to_s3.py && success "Reviews uploaded."
}

show_results() {
    print_header "Showing DynamoDB Results"
    aws $ENDPOINT $REGION dynamodb scan --table-name user_reviews
}

show_logs() {
    print_header "Fetching Lambda Logs"
    for fn in preprocessing profanity sentiment ddb; do
        echo "Logs for ${fn}_lambda:"
        aws $ENDPOINT $REGION logs filter-log-events --log-group-name "/aws/lambda/${fn}_lambda"
    done
}
