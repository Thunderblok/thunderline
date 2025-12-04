#!/bin/bash
# Thunderline Development Startup Script
# 
# This script ensures all services start in the correct sequence:
# 1. PostgreSQL (Docker)
# 2. MLflow (Docker) 
# 3. Thunderline Phoenix Server
# 4. Cerebros Python Service (optional)
#
# Usage:
#   ./scripts/dev_startup.sh          # Start all services
#   ./scripts/dev_startup.sh --stop   # Stop all services
#   ./scripts/dev_startup.sh --status # Check service status

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if a service is running
check_port() {
    local port=$1
    lsof -i :$port -sTCP:LISTEN -t >/dev/null 2>&1
}

wait_for_port() {
    local port=$1
    local service=$2
    local timeout=${3:-30}
    local count=0
    
    echo -n "Waiting for $service on port $port"
    while ! check_port $port && [ $count -lt $timeout ]; do
        echo -n "."
        sleep 1
        count=$((count + 1))
    done
    echo ""
    
    if check_port $port; then
        log_success "$service is ready"
        return 0
    else
        log_error "$service failed to start within ${timeout}s"
        return 1
    fi
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
}

start_postgres() {
    log_info "Starting PostgreSQL..."
    
    # Check if already running
    if docker ps --format '{{.Names}}' | grep -q "thunderline_postgres"; then
        log_success "PostgreSQL already running"
        return 0
    fi
    
    # Start or create container
    if docker ps -a --format '{{.Names}}' | grep -q "thunderline_postgres"; then
        docker start thunderline_postgres
    else
        docker compose -f "$PROJECT_ROOT/docker-compose.yml" up -d postgres
    fi
    
    # Wait for health check
    local count=0
    echo -n "Waiting for PostgreSQL health check"
    while [ $count -lt 30 ]; do
        if docker inspect --format='{{.State.Health.Status}}' thunderline_postgres 2>/dev/null | grep -q "healthy"; then
            echo ""
            log_success "PostgreSQL is healthy"
            return 0
        fi
        echo -n "."
        sleep 1
        count=$((count + 1))
    done
    echo ""
    log_warn "PostgreSQL health check timeout, but may still be usable"
}

start_mlflow() {
    log_info "Starting MLflow..."
    
    # Check if already running
    if docker ps --format '{{.Names}}' | grep -q "thunderline_mlflow"; then
        log_success "MLflow already running"
        return 0
    fi
    
    # Start or create container
    if docker ps -a --format '{{.Names}}' | grep -q "thunderline_mlflow"; then
        docker start thunderline_mlflow
    else
        docker compose -f "$PROJECT_ROOT/docker-compose.yml" up -d mlflow
    fi
    
    wait_for_port 5000 "MLflow" 30
}

start_thunderline() {
    log_info "Starting Thunderline Phoenix server..."
    
    # Check if already running
    if check_port 5001; then
        log_success "Thunderline already running on port 5001"
        return 0
    fi
    
    # Ensure deps are compiled
    if [ ! -d "_build/dev" ] || [ ! -f "_build/dev/lib/thunderline/ebin/Elixir.Thunderline.Application.beam" ]; then
        log_info "Compiling project..."
        mix compile
    fi
    
    # Export environment variables
    export MLFLOW_TRACKING_URI=http://localhost:5000
    export CEREBROS_ENABLED=1
    export TL_ENABLE_OBAN=1
    
    # Start in background
    log_info "Starting Phoenix (MLFLOW_TRACKING_URI=$MLFLOW_TRACKING_URI)"
    nohup mix phx.server > "$PROJECT_ROOT/thunderline.log" 2>&1 &
    
    wait_for_port 5001 "Thunderline" 60
}

start_cerebros() {
    log_info "Starting Cerebros Python service..."
    
    local CEREBROS_DIR="$PROJECT_ROOT/python/cerebros/service"
    local VENV_DIR="$PROJECT_ROOT/.venv"
    
    if [ ! -d "$VENV_DIR" ]; then
        log_warn "Python venv not found at $VENV_DIR"
        log_info "Create with: python3 -m venv .venv && source .venv/bin/activate && pip install -r python/cerebros/requirements.txt"
        return 1
    fi
    
    # Check if cerebros_service.py exists
    if [ ! -f "$CEREBROS_DIR/cerebros_service.py" ]; then
        log_error "Cerebros service not found at $CEREBROS_DIR/cerebros_service.py"
        return 1
    fi
    
    # Export environment
    export THUNDERLINE_URL=http://localhost:5001
    export MLFLOW_TRACKING_URI=http://localhost:5000
    export CEREBROS_SERVICE_ID=cerebros-dev-1
    
    log_info "Starting Cerebros service (THUNDERLINE_URL=$THUNDERLINE_URL)"
    source "$VENV_DIR/bin/activate"
    nohup python "$CEREBROS_DIR/cerebros_service.py" > "$PROJECT_ROOT/cerebros.log" 2>&1 &
    
    log_success "Cerebros service started (check cerebros.log for output)"
}

stop_services() {
    log_info "Stopping all Thunderline services..."
    
    # Stop Phoenix
    pkill -f "mix phx.server" 2>/dev/null || true
    pkill -f "beam.smp.*thunderline" 2>/dev/null || true
    
    # Stop Cerebros
    pkill -f "cerebros_service.py" 2>/dev/null || true
    
    # Stop Docker services
    docker stop thunderline_mlflow 2>/dev/null || true
    docker stop thunderline_postgres 2>/dev/null || true
    
    log_success "All services stopped"
}

show_status() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            Thunderline Service Status                       ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    
    # PostgreSQL
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "thunderline_postgres"; then
        health=$(docker inspect --format='{{.State.Health.Status}}' thunderline_postgres 2>/dev/null || echo "unknown")
        echo -e "║  PostgreSQL (5432):     ${GREEN}Running${NC} ($health)             ║"
    else
        echo -e "║  PostgreSQL (5432):     ${RED}Stopped${NC}                          ║"
    fi
    
    # MLflow
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "thunderline_mlflow"; then
        echo -e "║  MLflow (5000):         ${GREEN}Running${NC}                          ║"
    else
        echo -e "║  MLflow (5000):         ${RED}Stopped${NC}                          ║"
    fi
    
    # Thunderline
    if check_port 5001; then
        echo -e "║  Thunderline (5001):    ${GREEN}Running${NC}                          ║"
    else
        echo -e "║  Thunderline (5001):    ${RED}Stopped${NC}                          ║"
    fi
    
    # Cerebros
    if pgrep -f "cerebros_service.py" > /dev/null; then
        echo -e "║  Cerebros Service:      ${GREEN}Running${NC}                          ║"
    else
        echo -e "║  Cerebros Service:      ${YELLOW}Not started${NC}                      ║"
    fi
    
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  URLs:                                                       ║"
    echo "║    • Thunderline:  http://localhost:5001                     ║"
    echo "║    • MLflow UI:    http://localhost:5000                     ║"
    echo "║    • LiveDashboard: http://localhost:5001/dev/dashboard      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

main() {
    case "${1:-}" in
        --stop)
            stop_services
            ;;
        --status)
            show_status
            ;;
        --help|-h)
            echo "Thunderline Development Startup Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  (no args)   Start all services in sequence"
            echo "  --stop      Stop all services"
            echo "  --status    Show service status"
            echo "  --help      Show this help"
            ;;
        *)
            echo ""
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║        Thunderline Development Environment Startup          ║"
            echo "╚══════════════════════════════════════════════════════════════╝"
            echo ""
            
            check_docker
            
            # Start services in order
            start_postgres
            start_mlflow
            start_thunderline
            
            echo ""
            log_info "Core services started. To start Cerebros Python service:"
            echo "    source .venv/bin/activate"
            echo "    THUNDERLINE_URL=http://localhost:5001 MLFLOW_TRACKING_URI=http://localhost:5000 \\"
            echo "      python python/cerebros/service/cerebros_service.py"
            echo ""
            
            show_status
            ;;
    esac
}

main "$@"
