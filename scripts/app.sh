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

# Function to run full workflow
run_full_workflow() {
    print_header "Running Full AWS Workflow"

    if confirm "This will run ALL AWS operations. Are you sure?"; then
        echo
        create_s3_and_dynamodb
        echo
        set_ssm_parameters  
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
    echo "  4) Deploy Lambda Functions"
    echo "  5) Set Lambda Permissions"
    echo "  6) Set S3 Notifications"
    echo
    echo "Pipeline Operations:"
    echo "  7) Start Pipeline (upload reviews)"
    echo "  8) Show Results (DynamoDB Scan)"
    echo "  9) Show Lambda Logs"
    echo
    echo "Other:"
    echo " 10) 🚀 Run FULL Workflow (ALL Steps)"
    echo " 11) Exit (return to host)"
    echo
}

# Main application loop
main() {
    # Initial connectivity check
    check_aws_connectivity
    echo
    
    while true; do
        show_app_menu
        read -p "Please choose an option [1-11]: " choice
        echo

        case $choice in
            1) check_aws_connectivity ;;
            2) create_s3_and_dynamodb ;;
            3) set_ssm_parameters ;;   
            4) deploy_lambdas ;;       
            5) set_lambda_permissions ;;
            6) set_s3_notifications ;;  
            7) start_pipeline ;;        
            8) show_results ;;         
            9) show_logs ;;            
            10) run_full_workflow ;;
            11)
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