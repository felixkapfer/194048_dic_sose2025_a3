#!/usr/bin/env python3
"""
Create minimal NLTK data for Lambda deployment
Only includes the essential files needed
"""
import os
import shutil
from pathlib import Path

def create_minimal_nltk():
    """Create a minimal nltk_data directory with only essential files"""
    
    # Create minimal directory
    minimal_dir = "nltk_data_minimal"
    if os.path.exists(minimal_dir):
        shutil.rmtree(minimal_dir)
    
    # Essential paths needed
    essential_paths = [
        # Punkt tokenizer (needed for word_tokenize)
        "nltk_data/tokenizers/punkt/english.pickle",
        "nltk_data/tokenizers/punkt/PY3/english.pickle",
        
        # Stopwords
        "nltk_data/corpora/stopwords/english",
        
        # WordNet (keep minimal)
        "nltk_data/corpora/wordnet/data.adj",
        "nltk_data/corpora/wordnet/data.adv",
        "nltk_data/corpora/wordnet/data.noun",
        "nltk_data/corpora/wordnet/data.verb",
        "nltk_data/corpora/wordnet/index.adj",
        "nltk_data/corpora/wordnet/index.adv",  
        "nltk_data/corpora/wordnet/index.noun",
        "nltk_data/corpora/wordnet/index.verb",
        "nltk_data/corpora/wordnet/index.sense",
        "nltk_data/corpora/wordnet/lexnames",
        
        # OMW - minimal
        "nltk_data/corpora/omw-1.4/citation.bib",
        "nltk_data/corpora/omw-1.4/README"
    ]
    
    # Copy only essential files
    for path in essential_paths:
        if os.path.exists(path):
            dest_path = os.path.join(minimal_dir, path.replace("nltk_data/", ""))
            os.makedirs(os.path.dirname(dest_path), exist_ok=True)
            try:
                shutil.copy2(path, dest_path)
                print(f"✓ Copied: {path}")
            except Exception as e:
                print(f"✗ Failed to copy {path}: {e}")
    
    # Check size
    total_size = 0
    for root, dirs, files in os.walk(minimal_dir):
        for file in files:
            total_size += os.path.getsize(os.path.join(root, file))
    
    print(f"\nMinimal NLTK data size: {total_size / (1024*1024):.1f} MB")
    return minimal_dir

if __name__ == "__main__":
    os.chdir("/app/src/lambdas")
    minimal_dir = create_minimal_nltk()
    print(f"\nCreated minimal NLTK data in: {minimal_dir}")
    print("\nNow update Lambda ZIPs to use 'nltk_data_minimal' instead of 'nltk_data'")