#!/bin/bash

# infrastructure.sh - Docker Compose control

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source utils for print_header, success, error, etc
source "${script_dir}/utils.sh"

start_infra() {
    print_header "Starting Infrastructure"
    docker compose up -d && success "Infrastructure started."
}

stop_infra() {
    print_header "Stopping Infrastructure"
    docker compose down && success "Infrastructure stopped."
}

status_infra() {
    print_header "Infrastructure Status"
    docker compose ps
}