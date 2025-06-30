#!/usr/bin/env python3
"""
Script to download NLTK data for Lambda deployment
Run this before creating the Lambda ZIP files
"""

import nltk
import os

# Create directory for NLTK data
nltk_data_dir = './nltk_data'
os.makedirs(nltk_data_dir, exist_ok=True)

# Download required NLTK data
print("Downloading NLTK data...")
nltk.download('punkt', download_dir=nltk_data_dir)
nltk.download('stopwords', download_dir=nltk_data_dir)
nltk.download('wordnet', download_dir=nltk_data_dir)
nltk.download('omw-1.4', download_dir=nltk_data_dir)  # Required for wordnet

print(f"NLTK data downloaded to {nltk_data_dir}")
print("This directory should be included in your Lambda ZIP files")