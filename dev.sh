#!/bin/bash

# OptTab Development Script
# Usage: ./dev.sh [build|run|release|clean]

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

function print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

function print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

function print_error() {
    echo -e "${RED}❌ $1${NC}"
}

function build() {
    print_info "Building OptTab..."
    swift build
    print_success "Build completed!"
}

function run() {
    print_info "Running OptTab..."
    print_warning "Press Ctrl+C to stop"
    echo ""
    swift run
}

function build_release() {
    print_info "Building OptTab (Release mode)..."
    swift build -c release
    print_success "Release build completed!"
    print_info "Binary location: .build/release/OptTab"
}

function clean() {
    print_info "Cleaning build artifacts..."
    rm -rf .build
    print_success "Clean completed!"
}

function show_help() {
    echo "OptTab Development Script"
    echo ""
    echo "Usage: ./dev.sh [command]"
    echo ""
    echo "Commands:"
    echo "  build     - Build the project (debug mode)"
    echo "  run       - Build and run the project"
    echo "  release   - Build optimized release version"
    echo "  clean     - Remove build artifacts"
    echo "  help      - Show this help message"
    echo ""
    echo "If no command is provided, 'run' will be executed."
}

# Main script
case "${1:-run}" in
    build)
        build
        ;;
    run)
        run
        ;;
    release)
        build_release
        ;;
    clean)
        clean
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
