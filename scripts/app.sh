#!/bin/bash

# app.sh - Application Manager (Inside Container)
# This file should be located at: scripts/app.sh

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utility functions
source "${script_dir}/utils.sh"

# Check if we're inside the container
if [ ! -f "/.dockerenv" ]; then
    error "This script should only be run inside the Docker container!"
    echo "Use './main.sh connect' from the host system to access this menu."
    exit 1
fi

# Display welcome message
print_header "LocalStack Application Manager"
echo "Running inside Docker container: $(hostname)"
echo "AWS Endpoint: ${AWS_ENDPOINT_URL:-http://localstack:4566}"
echo

# Source workflow functions
if [ -f "${script_dir}/workflows.sh" ]; then
    source "${script_dir}/workflows.sh"
else
    error "workflows.sh not found!"
    exit 1
fi

# Function to prepare Lambda ZIP files
prepare_lambda_zips() {
    print_header "Preparing Lambda ZIP Files"
    
    local lambdas_dir="/app/src/lambdas"
    
    # Check if lambdas directory exists
    if [ ! -d "$lambdas_dir" ]; then
        error "Lambda directory not found: $lambdas_dir"
        return 1
    fi
    
    cd "$lambdas_dir" || return 1
    
    # Check if Python files exist
    echo "Checking for Lambda Python files..."
    local missing_files=0
    for lambda_file in preprocessing_lambda.py profanity_lambda.py sentiment_lambda.py ddb_lambda.py; do
        if [ ! -f "$lambda_file" ]; then
            error "Missing: $lambda_file"
            missing_files=$((missing_files + 1))
        else
            success "Found: $lambda_file"
        fi
    done
    
    if [ $missing_files -gt 0 ]; then
        error "Missing $missing_files Lambda files. Please ensure all Lambda functions are created."
        return 1
    fi
    
    # Download NLTK data if needed
    if [ ! -d "nltk_data" ]; then
        echo
        echo "Downloading NLTK data..."
        if [ -f "download_nltk_data.py" ]; then
            python download_nltk_data.py
            if [ $? -eq 0 ]; then
                success "NLTK data downloaded successfully"
            else
                error "Failed to download NLTK data"
                return 1
            fi
        else
            warn "download_nltk_data.py not found, skipping NLTK data download"
        fi
    fi
    
    # Check if create_lambda_zips.sh exists and run it
    if [ -f "${script_dir}/create_lambda_zips.sh" ]; then
        echo
        echo "Running ZIP creation script..."
        bash "${script_dir}/create_lambda_zips.sh"
    else
        # Fallback: Create simple ZIPs
        echo
        warn "create_lambda_zips.sh not found, creating simple ZIP files..."
        
        for lambda_name in preprocessing_lambda profanity_lambda sentiment_lambda ddb_lambda; do
            if [ -f "${lambda_name}.py" ]; then
                zip -q "${lambda_name}.zip" "${lambda_name}.py"
                if [ $? -eq 0 ]; then
                    success "Created ${lambda_name}.zip"
                else
                    error "Failed to create ${lambda_name}.zip"
                fi
            fi
        done
    fi
    
    # Verify all ZIPs exist
    echo
    echo "Verifying ZIP files..."
    local all_zips_exist=true
    for zip_file in preprocessing_lambda.zip profanity_lambda.zip sentiment_lambda.zip ddb_lambda.zip; do
        if [ -f "$zip_file" ]; then
            local size=$(du -h "$zip_file" | cut -f1)
            success "✅ $zip_file ($size)"
        else
            error "❌ $zip_file missing"
            all_zips_exist=false
        fi
    done
    
    if [ "$all_zips_exist" = true ]; then
        echo
        success "All Lambda ZIP files are ready for deployment!"
    else
        echo
        error "Some ZIP files are missing. Please fix the issues and try again."
    fi
    
    cd - > /dev/null
}

# Function to run full workflow
run_full_workflow() {
    print_header "Running Full AWS Workflow"

    if confirm "This will run ALL AWS operations. Are you sure?"; then
        echo
        create_s3_and_dynamodb
        echo
        set_ssm_parameters  
        echo
        prepare_lambda_zips
        echo
        deploy_lambdas
        echo
        set_lambda_permissions
        echo
        set_s3_notifications
        echo
        if confirm "Do you want to upload the reviews (start pipeline)?"; then
            start_pipeline
        fi
        echo
        if confirm "Do you want to scan and show DynamoDB results now?"; then
            show_results
        fi
        success "✅ Full workflow completed."
    else
        warn "Cancelled full workflow run."
    fi
}

# Function to check AWS connectivity
check_aws_connectivity() {
    print_header "Checking AWS Connectivity"
    
    echo "Testing connection to LocalStack..."
    if aws --endpoint-url=http://localstack:4566 --region us-east-1 s3 ls >/dev/null 2>&1; then
        success "✅ Successfully connected to LocalStack"
    else
        error "❌ Cannot connect to LocalStack"
        echo "Make sure LocalStack container is running and healthy."
        return 1
    fi
}

# Display application menu
show_app_menu() {
    echo -e "${YELLOW}"
    echo "==============================================="
    echo "       AWS Operations Menu"
    echo "==============================================="
    echo -e "${NC}"
    echo "Setup Operations:"
    echo "  1) Check AWS Connectivity"
    echo "  2) Create S3 & DynamoDB"
    echo "  3) Set SSM Parameters"
    echo "  4) Prepare Lambda ZIP Files 📦"
    echo "  5) Deploy Lambda Functions"
    echo "  6) Set Lambda Permissions"
    echo "  7) Set S3 Notifications"
    echo
    echo "Pipeline Operations:"
    echo "  8) Start Pipeline (upload reviews)"
    echo "  9) Show Results (DynamoDB Scan)"
    echo " 10) Show Lambda Logs"
    echo
    echo "Other:"
    echo " 11) 🚀 Run FULL Workflow (ALL Steps)"
    echo " 12) Exit (return to host)"
    echo
}

# Main application loop
main() {
    # Initial connectivity check
    check_aws_connectivity
    echo
    
    while true; do
        show_app_menu
        read -p "Please choose an option [1-12]: " choice
        echo

        case $choice in
            1) check_aws_connectivity ;;
            2) create_s3_and_dynamodb ;;
            3) set_ssm_parameters ;;
            4) prepare_lambda_zips ;;   
            5) deploy_lambdas ;;       
            6) set_lambda_permissions ;;
            7) set_s3_notifications ;;  
            8) start_pipeline ;;        
            9) show_results ;;         
            10) show_logs ;;            
            11) run_full_workflow ;;
            12)
                success "Exiting application container."
                echo "You are now back on the host system."
                exit 0
                ;;
            *) error "Invalid option. Please try again." ;;
        esac

        echo
        read -p "Press Enter to continue..."
        echo
    done
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    main
fi