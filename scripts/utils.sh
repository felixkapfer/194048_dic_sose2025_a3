#!/bin/bash

# utils.sh - common helper functions and styling

# Define color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Print a section header
print_header() {
    echo -e "${BLUE}"
    echo "==============================================="
    echo "$1"
    echo "==============================================="
    echo -e "${NC}"
}

# Print success message
success() {
    echo -e "${GREEN}✔️  $1${NC}"
}

# Print warning message
warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Print error message
error() {
    echo -e "${RED}❌  $1${NC}"
}

# Confirm action (yes/no prompt)
confirm() {
    read -p "$1 [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;  # yes
        *) return 1 ;;                # no
    esac
}

# Simple spinner (use after & to show progress)
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\\'
    while ps a | awk '{print $1}' | grep -q "$pid"; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}