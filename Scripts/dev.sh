#!/bin/bash

# Clipster Development Build Script
# Quick build script for development and testing

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

APP_NAME="Clipster"

# Get project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}🔧 Clipster Development Build${NC}"
echo -e "${BLUE}============================${NC}"

cd "$PROJECT_DIR"

# Quick build function
quick_build() {
    echo -e "${BLUE}🔨 Building for development...${NC}"
    swift build
    echo -e "${GREEN}✅ Development build complete${NC}"
}

# Run the app function
run_app() {
    echo -e "${BLUE}🚀 Running ${APP_NAME}...${NC}"
    ./.build/debug/$APP_NAME
}

# Kill existing instances
kill_existing() {
    echo -e "${YELLOW}🛑 Stopping existing instances...${NC}"
    pkill -f "$APP_NAME" 2>/dev/null || true
    echo -e "${GREEN}✅ Cleanup complete${NC}"
}

# Check what to do based on arguments
case "${1:-build}" in
    "build")
        kill_existing
        quick_build
        ;;
    "run")
        kill_existing
        quick_build
        run_app
        ;;
    "clean")
        echo -e "${BLUE}🧹 Cleaning build directory...${NC}"
        rm -rf .build
        rm -rf "${APP_NAME}.app"
        echo -e "${GREEN}✅ Clean complete${NC}"
        ;;
    *)
        echo "Usage: $0 [build|run|clean]"
        echo "  build - Build the app for development (default)"
        echo "  run   - Build and run the app"
        echo "  clean - Clean all build artifacts"
        exit 1
        ;;
esac

echo -e "${GREEN}🎉 Done!${NC}"
