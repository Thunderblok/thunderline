#!/usr/bin/env bash
#
# Thunderline Release Build Script
# ---------------------------------
# Builds a production release for deployment.
#
# Usage:
#   ./scripts/release.sh              # Build release
#   ./scripts/release.sh --clean      # Clean and rebuild
#   ./scripts/release.sh --docker     # Build Docker image
#   ./scripts/release.sh --help       # Show help
#
# Environment Variables:
#   MIX_ENV          - Build environment (default: prod)
#   FEATURES         - Feature flags to enable (comma-separated)
#   RELEASE_VERSION  - Override release version
#   DOCKER_TAG       - Docker image tag (default: thunderline:latest)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Defaults
MIX_ENV="${MIX_ENV:-prod}"
FEATURES="${FEATURES:-}"
RELEASE_VERSION="${RELEASE_VERSION:-}"
DOCKER_TAG="${DOCKER_TAG:-thunderline:latest}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

show_help() {
    cat <<EOF
Thunderline Release Build Script

Usage:
  ./scripts/release.sh [OPTIONS]

Options:
  --clean        Clean build artifacts before building
  --docker       Build Docker image instead of local release
  --no-assets    Skip asset compilation (faster for CI)
  --no-deps      Skip deps.get (assumes deps are cached)
  --help, -h     Show this help message

Environment Variables:
  MIX_ENV          Build environment (default: prod)
  FEATURES         Feature flags to enable
  RELEASE_VERSION  Override version from mix.exs
  DOCKER_TAG       Docker image tag (default: thunderline:latest)
  SECRET_KEY_BASE  Required for prod builds (generated if missing)

Examples:
  # Standard production build
  ./scripts/release.sh

  # Clean rebuild with specific features
  FEATURES=demo_mode ./scripts/release.sh --clean

  # Build Docker image
  ./scripts/release.sh --docker

  # CI build (skip deps, just compile and release)
  ./scripts/release.sh --no-deps
EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v mix &>/dev/null; then
        log_error "Elixir/Mix not found. Install Elixir first."
        exit 1
    fi

    if ! command -v npm &>/dev/null; then
        log_warn "npm not found. Asset compilation may fail."
    fi

    # For prod builds, ensure SECRET_KEY_BASE is set or generate one
    if [[ "$MIX_ENV" == "prod" && -z "${SECRET_KEY_BASE:-}" ]]; then
        log_warn "SECRET_KEY_BASE not set. Generating temporary key..."
        export SECRET_KEY_BASE=$(mix phx.gen.secret 2>/dev/null || openssl rand -base64 64 | tr -d '\n')
    fi

    log_success "Prerequisites OK"
}

clean_build() {
    log_info "Cleaning build artifacts..."
    rm -rf _build/prod deps/_build
    mix deps.clean --unused
    log_success "Clean complete"
}

fetch_deps() {
    log_info "Fetching dependencies..."
    mix deps.get --only "$MIX_ENV"
    log_success "Dependencies fetched"
}

compile_deps() {
    log_info "Compiling dependencies..."
    mix deps.compile
    log_success "Dependencies compiled"
}

compile_assets() {
    log_info "Compiling assets..."

    # Install npm deps if package.json exists in assets
    if [[ -f "assets/package.json" ]]; then
        npm ci --prefix assets --silent 2>/dev/null || npm install --prefix assets --silent
    fi

    # Run Phoenix asset pipeline
    mix assets.deploy
    log_success "Assets compiled"
}

compile_app() {
    log_info "Compiling application (MIX_ENV=$MIX_ENV)..."

    if [[ -n "$FEATURES" ]]; then
        log_info "Features enabled: $FEATURES"
        FEATURES="$FEATURES" mix compile --force
    else
        mix compile
    fi

    log_success "Application compiled"
}

build_release() {
    log_info "Building release..."

    local release_opts=""
    if [[ -n "$RELEASE_VERSION" ]]; then
        release_opts="--version $RELEASE_VERSION"
    fi

    mix release $release_opts

    # Show release info
    local release_path="_build/$MIX_ENV/rel/thunderline"
    if [[ -d "$release_path" ]]; then
        log_success "Release built at: $release_path"
        log_info "Start with: $release_path/bin/thunderline start"
        log_info "Console:    $release_path/bin/thunderline remote"
    fi
}

build_docker() {
    log_info "Building Docker image: $DOCKER_TAG"

    local build_args=""
    if [[ -n "$FEATURES" ]]; then
        build_args="--build-arg FEATURES=$FEATURES"
    fi

    docker build \
        --tag "$DOCKER_TAG" \
        --build-arg MIX_ENV=prod \
        $build_args \
        .

    log_success "Docker image built: $DOCKER_TAG"
    log_info "Run with: docker run -p 4000:4000 $DOCKER_TAG"
}

# Parse arguments
DO_CLEAN=false
DO_DOCKER=false
SKIP_ASSETS=false
SKIP_DEPS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)     DO_CLEAN=true; shift ;;
        --docker)    DO_DOCKER=true; shift ;;
        --no-assets) SKIP_ASSETS=true; shift ;;
        --no-deps)   SKIP_DEPS=true; shift ;;
        --help|-h)   show_help; exit 0 ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log_info "=== Thunderline Release Build ==="
    log_info "Environment: $MIX_ENV"
    log_info "Project: $PROJECT_ROOT"
    echo

    check_prerequisites

    if $DO_DOCKER; then
        build_docker
        exit 0
    fi

    if $DO_CLEAN; then
        clean_build
    fi

    export MIX_ENV

    if ! $SKIP_DEPS; then
        fetch_deps
        compile_deps
    fi

    if ! $SKIP_ASSETS; then
        compile_assets
    fi

    compile_app
    build_release

    echo
    log_success "=== Release build complete! ==="
}

main
