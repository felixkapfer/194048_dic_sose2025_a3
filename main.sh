#!/bin/bash

# main.sh - Interactive menu for infrastructure and workflows (Debug Version)

# Determine script directory and source modules
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scripts_dir="${script_dir}/scripts"

# Debug output
echo "=== DEBUG INFO ==="
echo "Script directory: $script_dir"
echo "Scripts directory: $scripts_dir" 
echo "Current working directory: $(pwd)"
echo

# Check multiple possible locations
echo "=== FILE CHECK ==="
possible_locations=("${script_dir}" "${scripts_dir}" "${script_dir}/.." "${script_dir}/../scripts")

for location in "${possible_locations[@]}"; do
    echo "Checking location: $location"
    for file in "utils.sh" "infrastructure.sh" "workflows.sh"; do
        if [ -f "${location}/${file}" ]; then
            echo "  ✓ ${location}/${file} exists"
        else
            echo "  ✗ ${location}/${file} NOT found"
        fi
    done
    echo
done

# Find the correct location
FOUND_LOCATION=""
for location in "${possible_locations[@]}"; do
    if [ -f "${location}/utils.sh" ] && [ -f "${location}/infrastructure.sh" ] && [ -f "${location}/workflows.sh" ]; then
        FOUND_LOCATION="$location"
        echo "✓ Found all scripts in: $FOUND_LOCATION"
        break
    fi
done

if [ -z "$FOUND_LOCATION" ]; then
    echo "✗ Could not find script files. Searching entire directory tree..."
    find "$script_dir" -name "utils.sh" -type f 2>/dev/null
    find "$script_dir" -name "infrastructure.sh" -type f 2>/dev/null  
    find "$script_dir" -name "workflows.sh" -type f 2>/dev/null
    exit 1
fi
echo

# Try to source files with error handling
echo "=== SOURCING FILES ==="
if source "${FOUND_LOCATION}/utils.sh" 2>/dev/null; then
    echo "✓ utils.sh sourced successfully"
else
    echo "✗ Failed to source utils.sh"
    exit 1
fi

if source "${FOUND_LOCATION}/infrastructure.sh" 2>/dev/null; then
    echo "✓ infrastructure.sh sourced successfully"
else
    echo "✗ Failed to source infrastructure.sh"
    exit 1
fi

if source "${FOUND_LOCATION}/workflows.sh" 2>/dev/null; then
    echo "✓ workflows.sh sourced successfully"
else
    echo "✗ Failed to source workflows.sh"
    exit 1
fi

# Check if functions are available
echo "=== FUNCTION CHECK ==="
if declare -f create_s3_and_dynamodb >/dev/null; then
    echo "✓ create_s3_and_dynamodb function is available"
else
    echo "✗ create_s3_and_dynamodb function NOT available"
    echo "Available functions:"
    declare -F | grep -E "(create|start|stop|show)"
fi
echo

# Function to run full workflow
run_full_workflow() {
    print_header "Running Full LocalStack Workflow"

    if confirm "This will run ALL steps. Are you sure?"; then
        start_infra
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

# Display menu
show_main_menu() {
    echo -e "${YELLOW}"
    echo "==============================================="
    echo "           LocalStack App Manager"
    echo "==============================================="
    echo -e "${NC}"
    echo "1) Start Infrastructure (docker compose up)"
    echo "2) Stop Infrastructure (docker compose down)"
    echo "3) Show Infrastructure Status"
    echo "-----------------------------------------------"
    echo "4) Create S3 & DynamoDB"
    echo "5) Set SSM Parameters"
    echo "6) Deploy Lambda Functions"
    echo "7) Set Lambda Permissions"
    echo "8) Set S3 Notifications"
    echo "9) Start Pipeline (upload reviews)"
    echo "10) Show Results (DynamoDB Scan)"
    echo "11) Show Lambda Logs"
    echo "-----------------------------------------------"
    echo "12) Exit"
    echo "13) 🚀 Run FULL Workflow (ALL Steps)"
    echo "14) Install AWS CLI and awslocal"
    echo
}

# Main loop
main() {
    while true; do
        show_main_menu
        read -p "Please choose an option [1-13]: " choice
        echo

        case $choice in
            1) start_infra ;;            
            2) stop_infra ;;
            3) status_infra ;;
            4) 
                echo "Attempting to call create_s3_and_dynamodb..."
                if declare -f create_s3_and_dynamodb >/dev/null; then
                    create_s3_and_dynamodb
                else
                    error "create_s3_and_dynamodb function not found!"
                fi
                ;;  
            5) set_ssm_parameters ;;   
            6) deploy_lambdas ;;       
            7) set_lambda_permissions ;;
            8) set_s3_notifications ;;  
            9) start_pipeline ;;        
            10) show_results ;;         
            11) show_logs ;;            
            12)
                success "Exiting. Goodbye!"
                exit 0
                ;;
            13) run_full_workflow ;;
            14) install_aws_cli ;;
            *) error "Invalid option. Please try again." ;;
        esac

        echo
    done
}

# Start
main