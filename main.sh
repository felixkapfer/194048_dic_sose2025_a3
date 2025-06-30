#!/bin/bash

# main.sh - Infrastructure Manager (Host System)

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scripts_dir="${script_dir}/scripts"

# Source utils for styling
if [ -f "${scripts_dir}/utils.sh" ]; then
    source "${scripts_dir}/utils.sh"
else
    # Fallback color definitions if utils.sh not found
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[1;34m'
    NC='\033[0m'
    
    print_header() { echo -e "${BLUE}===============================================\n$1\n===============================================${NC}"; }
    success() { echo -e "${GREEN}✔️  $1${NC}"; }
    error() { echo -e "${RED}❌  $1${NC}"; }
    warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
    confirm() { read -p "$1 [y/N]: " response; case "$response" in [yY][eE][sS]|[yY]) return 0 ;; *) return 1 ;; esac; }
fi

# Infrastructure functions
start_infra() {
    print_header "Starting Infrastructure"
    if docker compose up -d; then
        success "Infrastructure started."
        echo
        print_header "Waiting for containers to be ready..."
        sleep 5
        
        if docker compose ps | grep -q "Up"; then
            success "Containers are running."
            echo
            warn "To connect to the application container and run operations, use:"
            echo -e "${YELLOW}  ./main.sh connect${NC}"
            echo
        else
            error "Containers failed to start properly!"
            docker compose ps
        fi
    else
        error "Failed to start infrastructure!"
    fi
}

stop_infra() {
    print_header "Stopping Infrastructure"
    if docker compose down; then
        success "Infrastructure stopped."
    else
        error "Failed to stop infrastructure!"
    fi
}

status_infra() {
    print_header "Infrastructure Status"
    docker compose ps
    echo
    
    # Check if app container is running
    if docker compose ps | grep -q "app-main.*Up"; then
        success "App container is running. You can connect with: ./main.sh connect"
    else
        warn "App container is not running. Start infrastructure first."
    fi
}

connect_to_app() {
    print_header "Connecting to Application Container"
    
    # Check if container is running
    if ! docker compose ps | grep -q "app-main.*Up"; then
        error "App container is not running!"
        echo "Please start the infrastructure first with: ./main.sh start"
        return 1
    fi
    
    echo "Connecting to app container and starting application menu..."
    echo "Use 'exit' to return to host system."
    echo
    
    # Connect to container and run app.sh
    docker compose exec app bash -c "cd /app && ./scripts/app.sh"
}

# Display menu
show_main_menu() {
    echo -e "${YELLOW}"
    echo "==============================================="
    echo "        Infrastructure Manager"
    echo "==============================================="
    echo -e "${NC}"
    echo "1) Start Infrastructure (docker compose up)"
    echo "2) Stop Infrastructure (docker compose down)"  
    echo "3) Show Infrastructure Status"
    echo "4) Connect to Application Container"
    echo "5) Exit"
    echo
}

# Quick commands
case "$1" in
    "start")
        start_infra
        exit 0
        ;;
    "stop")
        stop_infra
        exit 0
        ;;
    "status")
        status_infra
        exit 0
        ;;
    "connect")
        connect_to_app
        exit 0
        ;;
    "")
        # No argument - show interactive menu
        ;;
    *)
        echo "Usage: $0 [start|stop|status|connect]"
        echo "  start   - Start the infrastructure"
        echo "  stop    - Stop the infrastructure"
        echo "  status  - Show infrastructure status"
        echo "  connect - Connect to application container"
        echo "  (no arg) - Show interactive menu"
        exit 1
        ;;
esac

# Main interactive loop
main() {
    while true; do
        show_main_menu
        read -p "Please choose an option [1-5]: " choice
        echo

        case $choice in
            1) start_infra ;;            
            2) stop_infra ;;
            3) status_infra ;;
            4) connect_to_app ;;
            5)
                success "Exiting. Goodbye!"
                exit 0
                ;;
            *) error "Invalid option. Please try again." ;;
        esac

        echo
        read -p "Press Enter to continue..."
        echo
    done
}

# Start interactive menu
main