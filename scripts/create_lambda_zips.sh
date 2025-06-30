#!/bin/bash

# create_lambda_zips.sh - Create ZIP files for Lambda deployment

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lambdas_dir="${script_dir}/../src/lambdas"

# Source utils for styling
source "${script_dir}/utils.sh"

print_header "Creating Lambda ZIP Files"

# Change to lambdas directory
cd "$lambdas_dir" || exit 1

# First, download NLTK data if not already present
if [ ! -d "nltk_data" ]; then
    print_header "Downloading NLTK Data"
    python download_nltk_data.py
    if [ $? -ne 0 ]; then
        error "Failed to download NLTK data"
        exit 1
    fi
    success "NLTK data downloaded"
fi

# Function to create a Lambda ZIP with dependencies
create_lambda_zip() {
    local lambda_name=$1
    local needs_nltk=$2
    local dependencies=$3
    
    echo "Creating ZIP for ${lambda_name}..."
    
    # Create temp directory
    temp_dir="temp_${lambda_name}"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    # Copy Lambda function
    cp "${lambda_name}.py" "$temp_dir/"
    
    # Add NLTK data if needed
    if [ "$needs_nltk" = "yes" ] && [ -d "nltk_data" ]; then
        cp -r nltk_data "$temp_dir/"
    fi
    
    # Install dependencies if specified
    if [ -n "$dependencies" ]; then
        pip install -q $dependencies -t "$temp_dir/" --platform manylinux2014_x86_64 --only-binary=:all: 2>/dev/null
        
        # Clean up unnecessary files
        find "$temp_dir" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null
        find "$temp_dir" -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null
        rm -rf "$temp_dir"/bin 2>/dev/null
    fi
    
    # Create ZIP
    cd "$temp_dir" || exit 1
    zip -q -r "../${lambda_name}.zip" .
    cd ..
    
    # Clean up
    rm -rf "$temp_dir"
    
    # Check ZIP size
    zip_size=$(du -h "${lambda_name}.zip" | cut -f1)
    success "Created ${lambda_name}.zip (${zip_size})"
}

# Create preprocessing Lambda ZIP (needs NLTK)
create_lambda_zip "preprocessing_lambda" "yes" "nltk"

# Create profanity Lambda ZIP (needs better-profanity)
create_lambda_zip "profanity_lambda" "no" "better-profanity"

# Create sentiment Lambda ZIP (needs textblob and NLTK data)
create_lambda_zip "sentiment_lambda" "yes" "textblob nltk"

# Create DDB Lambda ZIP (no special dependencies)
create_lambda_zip "ddb_lambda" "no" ""

print_header "Lambda ZIP Creation Complete"
echo "ZIP files created in: $lambdas_dir"
ls -lh *.zip

echo
warn "Note: If ZIP files are larger than 50MB, they may need to be uploaded to S3 first"
echo "Maximum unzipped size for Lambda is 250MB"