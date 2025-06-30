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

# First, create minimal NLTK data if not present
if [ ! -d "nltk_data_minimal" ]; then
    print_header "Creating Minimal NLTK Data"
    if [ -f "${script_dir}/create_minimal_nltk.py" ]; then
        python "${script_dir}/create_minimal_nltk.py"
    else
        # Fallback: create minimal nltk manually
        echo "Creating minimal NLTK data manually..."
        mkdir -p nltk_data_minimal/tokenizers/punkt/PY3
        mkdir -p nltk_data_minimal/corpora/stopwords
        mkdir -p nltk_data_minimal/corpora/wordnet
        
        # Copy only essential files
        if [ -d "nltk_data" ]; then
            cp -r nltk_data/tokenizers/punkt/english.pickle nltk_data_minimal/tokenizers/punkt/ 2>/dev/null || true
            cp -r nltk_data/tokenizers/punkt/PY3/english.pickle nltk_data_minimal/tokenizers/punkt/PY3/ 2>/dev/null || true
            cp nltk_data/corpora/stopwords/english nltk_data_minimal/corpora/stopwords/ 2>/dev/null || true
            cp nltk_data/corpora/wordnet/*.* nltk_data_minimal/corpora/wordnet/ 2>/dev/null || true
        fi
    fi
fi

# Update Lambda files to use nltk_data_minimal
echo
echo "Updating Lambda files to use minimal NLTK path..."
for lambda_file in preprocessing_lambda.py sentiment_lambda.py; do
    if [ -f "$lambda_file" ]; then
        # Backup original
        cp "$lambda_file" "${lambda_file}.bak"
        
        # Update NLTK path
        sed -i "s|nltk.data.path.append('./nltk_data')|nltk.data.path.append('./nltk_data_minimal')|g" "$lambda_file"
        echo "✓ Updated $lambda_file"
    fi
done

# Simple function to create Lambda ZIPs
echo
echo "Creating Lambda ZIP files..."

# Preprocessing Lambda (needs minimal NLTK data)
if [ -f "preprocessing_lambda.py" ]; then
    echo -n "Creating preprocessing_lambda.zip... "
    zip -r -q preprocessing_lambda.zip preprocessing_lambda.py nltk_data_minimal/
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

# Sentiment Lambda (needs minimal NLTK data)
if [ -f "sentiment_lambda.py" ]; then
    echo -n "Creating sentiment_lambda.zip... "
    zip -r -q sentiment_lambda.zip sentiment_lambda.py nltk_data_minimal/
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