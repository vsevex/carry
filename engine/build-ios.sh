#!/bin/bash
set -e

# Build Carry Engine for iOS
# Creates an XCFramework that can be embedded in iOS/macOS apps

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Output directory
OUTPUT_DIR="$SCRIPT_DIR/target/ios"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "==> Installing iOS targets..."
rustup target add aarch64-apple-ios
rustup target add aarch64-apple-ios-sim
rustup target add x86_64-apple-ios

echo "==> Building for iOS device (arm64)..."
cargo build --release --target aarch64-apple-ios

echo "==> Building for iOS simulator (arm64)..."
cargo build --release --target aarch64-apple-ios-sim

echo "==> Building for iOS simulator (x86_64)..."
cargo build --release --target x86_64-apple-ios

echo "==> Creating fat library for simulator..."
mkdir -p "$OUTPUT_DIR/sim"
lipo -create \
    target/aarch64-apple-ios-sim/release/libcarry_engine.a \
    target/x86_64-apple-ios/release/libcarry_engine.a \
    -output "$OUTPUT_DIR/sim/libcarry_engine.a"

echo "==> Creating XCFramework..."
rm -rf "$OUTPUT_DIR/CarryEngine.xcframework"
xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libcarry_engine.a \
    -headers include \
    -library "$OUTPUT_DIR/sim/libcarry_engine.a" \
    -headers include \
    -output "$OUTPUT_DIR/CarryEngine.xcframework"

echo "==> Done! XCFramework created at:"
echo "    $OUTPUT_DIR/CarryEngine.xcframework"
echo ""
echo "To use in your Flutter iOS app:"
echo "1. Copy CarryEngine.xcframework to ios/Frameworks/"
echo "2. Add to Xcode: Runner > Build Phases > Link Binary With Libraries"
echo "3. Set 'Framework Search Paths' to include \"\$(PROJECT_DIR)/Frameworks\""
