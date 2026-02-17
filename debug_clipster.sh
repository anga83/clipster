#!/bin/bash

echo "🚀 Starting Clipster with Debug Logging..."
echo "📊 Debug output will be shown below:"
echo "================================================"

# Build the app first
echo "🔨 Building Clipster..."
swift build

if [ $? -eq 0 ]; then
    echo "✅ Build successful"
    echo "🎯 Starting Clipster with debug logging..."
    echo "================================================"
    
    # Run the app and capture all output
    ./.build/debug/Clipster 2>&1 | while IFS= read -r line; do
        echo "[$(date '+%H:%M:%S.%3N')] $line"
    done
else
    echo "❌ Build failed"
    exit 1
fi
