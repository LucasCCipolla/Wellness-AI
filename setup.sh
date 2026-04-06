#!/bin/bash

# WellnessAI Setup Script
# This script helps set up the WellnessAI project for development and testing

echo "🏥 Welcome to WellnessAI Setup!"
echo "================================"

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode is not installed or not in PATH"
    echo "Please install Xcode from the Mac App Store"
    exit 1
fi

echo "✅ Xcode found"

# Check if we're in the right directory
if [ ! -f "WellnessAI.xcodeproj/project.pbxproj" ]; then
    echo "❌ WellnessAI.xcodeproj not found"
    echo "Please run this script from the WellnessAI project directory"
    exit 1
fi

echo "✅ Project structure found"

# Check for required iOS version
echo "📱 Checking iOS deployment target..."
IOS_VERSION=$(grep -o 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*' WellnessAI.xcodeproj/project.pbxproj | head -1 | cut -d' ' -f3)
echo "iOS Deployment Target: $IOS_VERSION"

# Check for OpenAI API key configuration
echo "🤖 Checking OpenAI API configuration..."
if grep -q "YOUR_OPENAI_API_KEY" WellnessAI/WellnessAI/Managers/OpenAIAPIManager.swift; then
    echo "⚠️  OpenAI API key not configured"
    echo "Please update the API key in WellnessAI/WellnessAI/Managers/OpenAIAPIManager.swift"
    echo "Replace 'YOUR_OPENAI_API_KEY' with your actual OpenAI API key"
else
    echo "✅ OpenAI API key appears to be configured"
fi

# Check HealthKit configuration
echo "❤️ Checking HealthKit configuration..."
if grep -q "NSHealthShareUsageDescription" WellnessAI/WellnessAI/Info.plist; then
    echo "✅ HealthKit permissions configured"
else
    echo "❌ HealthKit permissions not found in Info.plist"
fi

# Create build directory if it doesn't exist
echo "📦 Setting up build environment..."
mkdir -p build

# Clean build if requested
read -p "🧹 Clean previous builds? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleaning build directory..."
    xcodebuild clean -project WellnessAI.xcodeproj -scheme WellnessAI
    rm -rf build/*
    echo "✅ Build cleaned"
fi

# Build the project
echo "🔨 Building project..."
xcodebuild -project WellnessAI.xcodeproj -scheme WellnessAI -destination 'generic/platform=iOS' build

if [ $? -eq 0 ]; then
    echo "✅ Build successful"
else
    echo "❌ Build failed"
    echo "Please check the build errors above"
    exit 1
fi

# Check for connected devices
echo "📱 Checking for connected iOS devices..."
DEVICES=$(xcrun xctrace list devices | grep "iPhone\|iPad" | grep -v "Simulator" | wc -l)

if [ $DEVICES -gt 0 ]; then
    echo "✅ Found $DEVICES iOS device(s)"
    xcrun xctrace list devices | grep "iPhone\|iPad" | grep -v "Simulator"
    
    echo ""
    echo "📋 Next Steps:"
    echo "1. Open WellnessAI.xcodeproj in Xcode"
    echo "2. Select your iPhone as the target device"
    echo "3. Connect your Apple Watch if you have one"
    echo "4. Run the app (⌘+R)"
    echo "5. Grant all necessary permissions when prompted"
else
    echo "⚠️  No iOS devices connected"
    echo "To test on a physical device:"
    echo "1. Connect your iPhone via USB"
    echo "2. Trust the computer on your iPhone"
    echo "3. Run this script again"
fi

echo ""
echo "🎉 Setup Complete!"
echo "=================="
echo ""
echo "📖 For detailed instructions, see README.md"
echo "🔧 For troubleshooting, check the README troubleshooting section"
echo ""
echo "⚠️  Important Notes:"
echo "- This app requires iOS 17.0+ and HealthKit"
echo "- Apple Watch integration requires a paired Apple Watch"
echo "- OpenAI API key must be configured for AI features"
echo "- Camera permission is required for nutrition photo analysis"
echo ""
echo "Happy coding! 🚀"
