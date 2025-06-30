#!/bin/bash

# workflows.sh - AWS CLI tasks for the assignment

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/utils.sh"

# Define endpoint and region
ENDPOINT="--endpoint-url=http://localstack:4566"
REGION="--region us-east-1"

# Check if AWS CLI is available
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found!"
        echo "Trying to find AWS CLI in common locations..."
        
        # Check common installation paths
        for path in /usr/local/bin/aws /root/.local/bin/aws /usr/bin/aws; do
            if [ -f "$path" ]; then
                warn "Found AWS CLI at: $path"
                export PATH="$(dirname $path):$PATH"
                return 0
            fi
        done
        
        error "AWS CLI installation not found. Please check the Dockerfile."
        return 1
    fi
    
    # Test AWS CLI version
    local aws_version=$(aws --version 2>&1)
    success "AWS CLI found: $aws_version"
    return 0
}

create_s3_and_dynamodb() {
    print_header "Creating S3 Bucket and DynamoDB Table"
    
    # Check AWS CLI first
    if ! check_aws_cli; then
        return 1
    fi
    
    echo "Creating S3 bucket..."
    if aws $ENDPOINT $REGION s3 mb s3://reviews-bucket 2>/dev/null; then
        success "S3 Bucket created."
    else
        warn "S3 Bucket might already exist or creation failed."
    fi
    
    echo "Creating DynamoDB table..."
    if aws $ENDPOINT $REGION dynamodb create-table \
        --table-name user_reviews \
        --attribute-definitions AttributeName=reviewerID,AttributeType=S \
        --key-schema AttributeName=reviewerID,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 2>/dev/null; then
        success "DynamoDB Table created."
    else
        warn "DynamoDB Table might already exist or creation failed."
    fi
}

set_ssm_parameters() {
    print_header "Setting SSM Parameters"
    
    if ! check_aws_cli; then
        return 1
    fi
    
    declare -A params=(
        ["bucket"]="reviews-bucket"
        ["processed_bucket"]="reviews-bucket"
        ["user_reviews_table"]="user_reviews"
        ["profanity_bucket"]="reviews-bucket"
        ["sentiment_bucket"]="reviews-bucket"
    )
    
    for param in "${!params[@]}"; do
        local value="${params[$param]}"
        if aws $ENDPOINT $REGION ssm put-parameter \
            --name "/myapp/$param" \
            --value "$value" \
            --type String \
            --overwrite 2>/dev/null; then
            success "Parameter /myapp/$param set to '$value'."
        else
            error "Failed to set parameter /myapp/$param."
        fi
    done
}

deploy_lambdas() {
    print_header "Deploying Lambda Functions"
    
    if ! check_aws_cli; then
        return 1
    fi
    
    LAMBDA_DIR="${script_dir}/../src/lambdas"  # Adjusted path
    
    if [ ! -d "$LAMBDA_DIR" ]; then
        error "Lambda directory not found: $LAMBDA_DIR"
        return 1
    fi
    
    for fn in preprocessing profanity sentiment ddb; do
        local zip_file="${LAMBDA_DIR}/${fn}_lambda.zip"
        
        if [ ! -f "$zip_file" ]; then
            warn "Lambda zip file not found: $zip_file"
            continue
        fi
        
        if aws $ENDPOINT $REGION lambda create-function \
            --function-name "${fn}_lambda" \
            --runtime python3.11 \
            --handler "${fn}_lambda.lambda_handler" \
            --role arn:aws:iam::000000000000:role/lambda-role \
            --zip-file "fileb://${zip_file}" \
            --environment Variables="{AWS_ENDPOINT_URL=http://localstack:4566}" \
            --timeout 30 \
            --memory-size 256 2>/dev/null; then
            success "Lambda ${fn}_lambda deployed."
        else
            warn "Failed to deploy Lambda ${fn}_lambda (might already exist)."
            # Try to update environment variables for existing function
            aws $ENDPOINT $REGION lambda update-function-configuration \
                --function-name "${fn}_lambda" \
                --environment Variables="{AWS_ENDPOINT_URL=http://localstack:4566}" \
                --timeout 30 \
                --memory-size 256 2>/dev/null
        fi
    done
}

set_lambda_permissions() {
    print_header "Setting Lambda Permissions"
    
    if ! check_aws_cli; then
        return 1
    fi
    
    for fn in preprocessing profanity sentiment ddb; do
        if aws $ENDPOINT $REGION lambda add-permission \
            --function-name "${fn}_lambda" \
            --statement-id "s3invoke-${fn}" \
            --action "lambda:InvokeFunction" \
            --principal s3.amazonaws.com \
            --source-arn arn:aws:s3:::reviews-bucket 2>/dev/null; then
            success "Permission added to ${fn}_lambda."
        else
            warn "Failed to add permission to ${fn}_lambda (might already exist)."
        fi
    done
}

set_s3_notifications() {
    print_header "Configuring S3 Bucket Notifications"
    
    if ! check_aws_cli; then
        return 1
    fi
    
    # Try multiple locations for notification-config.json
    local config_file=""
    for location in "notification-config.json" "${script_dir}/notification-config.json" "/app/src/lambdas/notification-config.json" "../src/lambdas/notification-config.json"; do
        if [ -f "$location" ]; then
            config_file="$location"
            break
        fi
    done
    
    if [ -z "$config_file" ]; then
        error "Notification configuration file not found!"
        echo "Searched in current directory, scripts/, and src/lambdas/"
        return 1
    fi
    
    echo "Using notification config: $config_file"
    
    if aws $ENDPOINT $REGION s3api put-bucket-notification-configuration \
        --bucket reviews-bucket \
        --notification-configuration "file://$config_file"; then
        success "S3 notification configuration applied."
    else
        error "Failed to apply S3 notification configuration."
    fi
}


start_pipeline() {
    print_header "Uploading Reviews to S3 (Pipeline Start)"
    
    local upload_script="${script_dir}/upload_reviews_to_s3.py"
    
    if [ ! -f "$upload_script" ]; then
        error "Upload script not found: $upload_script"
        return 1
    fi
    
    # Make script executable
    chmod +x "$upload_script"
    
    # Check if dataset exists
    local dataset_path="/app/data/reviews_devset.json"
    if [ ! -f "$dataset_path" ]; then
        error "Dataset not found: $dataset_path"
        echo "Please ensure the reviews dataset is in the data/ directory"
        return 1
    fi
    
    echo "Starting review upload..."
    echo "Dataset: $dataset_path"
    echo
    
    if python "$upload_script" "$dataset_path"; then
        success "Reviews uploaded successfully"
    else
        error "Failed to upload reviews"
    fi
}

show_results() {
    print_header "Showing DynamoDB Results"
    
    if ! check_aws_cli; then
        return 1
    fi
    
    if aws $ENDPOINT $REGION dynamodb scan --table-name user_reviews; then
        success "DynamoDB scan completed."
    else
        error "Failed to scan DynamoDB table."
    fi
}

show_logs() {
    print_header "Fetching Lambda Logs"
    
    if ! check_aws_cli; then
        return 1
    fi
    
    for fn in preprocessing profanity sentiment ddb; do
        echo "=== Logs for ${fn}_lambda ==="
        if aws $ENDPOINT $REGION logs filter-log-events \
            --log-group-name "/aws/lambda/${fn}_lambda" 2>/dev/null; then
            echo "Logs retrieved successfully."
        else
            warn "No logs found for ${fn}_lambda or log group doesn't exist."
        fi
        echo
    done
}