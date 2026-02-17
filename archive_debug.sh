#!/bin/bash

echo "🔍 Clipster Archive Debug Session"
echo "================================="
echo "This script will help diagnose the Archive tab crash."
echo ""

# Check if the app binary exists
if [ ! -f "./.build/debug/Clipster" ]; then
    echo "❌ App binary not found. Building..."
    swift build
    
    if [ $? -ne 0 ]; then
        echo "❌ Build failed. Please fix compilation errors first."
        exit 1
    fi
fi

echo "✅ App binary found"
echo ""

# Check database status
echo "🗄️ Checking database status..."
DATABASE_PATH="$HOME/Library/Application Support/Clipster/database.sqlite"

if [ -f "$DATABASE_PATH" ]; then
    echo "✅ Database file exists at: $DATABASE_PATH"
    echo "📊 Database size: $(ls -lh "$DATABASE_PATH" | awk '{print $5}')"
    
    # Try to check database structure
    echo "🔍 Checking database structure..."
    sqlite3 "$DATABASE_PATH" "SELECT name FROM sqlite_master WHERE type='table';" 2>/dev/null | while read table; do
        echo "   📋 Table: $table"
    done
    
    # Check recently_deleted table
    echo "📦 Checking recently_deleted table..."
    COUNT=$(sqlite3 "$DATABASE_PATH" "SELECT COUNT(*) FROM recently_deleted;" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "   📊 Recently deleted items: $COUNT"
    else
        echo "   ❌ Error reading recently_deleted table"
    fi
else
    echo "⚠️  Database file not found - this is expected for first run"
fi

echo ""
echo "🚀 Starting Clipster with Archive Debug Logging..."
echo "📝 Watch for these key patterns:"
echo "   🔹 ENTER/EXIT - Function calls"
echo "   📦 ARCHIVE - Archive operations"
echo "   🗄️ DATABASE - Database operations"
echo "   🛡️ CRASH PREVENTION - Safety checks"
echo "   ❌ ERROR - Error conditions"
echo ""
echo "================================="

# Run the app with debug output
./.build/debug/Clipster
