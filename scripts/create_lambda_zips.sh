#!/bin/bash

# create_lambda_zips.sh - Create ZIP files for Lambda deployment

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lambdas_dir="${script_dir}/../src/lambdas"

# Source utils for styling
source "${script_dir}/utils.sh"

print_header "Creating Lambda ZIP Files"

# Change to lambdas directory
cd "$lambdas_dir" || exit 1
echo "Working directory: $(pwd)"

# First, download NLTK data if not already present
if [ ! -d "nltk_data" ]; then
    print_header "Downloading NLTK Data"
    if [ -f "download_nltk_data.py" ]; then
        python download_nltk_data.py
        if [ $? -ne 0 ]; then
            error "Failed to download NLTK data"
            exit 1
        fi
        success "NLTK data downloaded"
    else
        error "download_nltk_data.py not found!"
        exit 1
    fi
fi

# Simple function to create Lambda ZIPs
echo
echo "Creating Lambda ZIP files..."

# Preprocessing Lambda (needs NLTK data)
if [ -f "preprocessing_lambda.py" ]; then
    echo -n "Creating preprocessing_lambda.zip... "
    zip -r -q preprocessing_lambda.zip preprocessing_lambda.py nltk_data/
    if [ $? -eq 0 ]; then
        success "✓"
    else
        error "Failed"
    fi
fi

# Profanity Lambda (simple)
if [ -f "profanity_lambda.py" ]; then
    echo -n "Creating profanity_lambda.zip... "
    zip -q profanity_lambda.zip profanity_lambda.py
    if [ $? -eq 0 ]; then
        success "✓"
    else
        error "Failed"
    fi
fi

# Sentiment Lambda (needs NLTK data)
if [ -f "sentiment_lambda.py" ]; then
    echo -n "Creating sentiment_lambda.zip... "
    zip -r -q sentiment_lambda.zip sentiment_lambda.py nltk_data/
    if [ $? -eq 0 ]; then
        success "✓"
    else
        error "Failed"
    fi
fi

# DDB Lambda (simple)
if [ -f "ddb_lambda.py" ]; then
    echo -n "Creating ddb_lambda.zip... "
    zip -q ddb_lambda.zip ddb_lambda.py
    if [ $? -eq 0 ]; then
        success "✓"
    else
        error "Failed"
    fi
fi

print_header "Lambda ZIP Creation Complete"
echo "ZIP files created in: $lambdas_dir"
echo
ls -lh *.zip 2>/dev/null || echo "No ZIP files found!"

# Final verification
echo
echo "Verification:"
missing=0
for zip_file in preprocessing_lambda.zip profanity_lambda.zip sentiment_lambda.zip ddb_lambda.zip; do
    if [ -f "$zip_file" ]; then
        size=$(du -h "$zip_file" | cut -f1)
        success "✅ $zip_file ($size)"
    else
        error "❌ $zip_file missing"
        missing=$((missing + 1))
    fi
done

if [ $missing -eq 0 ]; then
    echo
    success "All Lambda ZIP files created successfully!"
    exit 0
else
    echo
    error "$missing ZIP files are missing!"
    exit 1
fi