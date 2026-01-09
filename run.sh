#!/bin/bash

# EasyScreenRecord - Build and Run Script

PROJECT_DIR="/Users/takahashinaoki/Dev/Hobby/EasyScreenRecord/EasyScreenRecord"
APP_PATH="/Users/takahashinaoki/Library/Developer/Xcode/DerivedData/EasyScreenRecord-fkakfsnxmyskmefpvewziicawekc/Build/Products/Debug/EasyScreenRecord.app"

# Kill existing process
pkill -x EasyScreenRecord 2>/dev/null

cd "$PROJECT_DIR"

# Parse arguments
CLEAN=false
BUILD=true
for arg in "$@"; do
    case $arg in
        --clean|-c)
            CLEAN=true
            ;;
        --no-build|-n)
            BUILD=false
            ;;
        --help|-h)
            echo "Usage: ./run.sh [options]"
            echo "Options:"
            echo "  -c, --clean     Clean before build"
            echo "  -n, --no-build  Skip build, just run"
            echo "  -h, --help      Show this help"
            exit 0
            ;;
    esac
done

# Clean if requested
if $CLEAN; then
    echo "🧹 Cleaning..."
    xcodebuild -scheme EasyScreenRecord clean -quiet
fi

# Build
if $BUILD; then
    echo "🔨 Building..."
    xcodebuild -scheme EasyScreenRecord -configuration Debug build -quiet
    if [ $? -ne 0 ]; then
        echo "❌ Build failed"
        exit 1
    fi
    echo "✅ Build succeeded"
fi

# Run
echo "🚀 Starting app..."
open "$APP_PATH"
