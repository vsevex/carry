#!/bin/bash
set -e

# Build Carry Engine for Android
# Requires Android NDK to be installed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Detect NDK path
if [ -z "$ANDROID_NDK_HOME" ]; then
    # Try common locations
    if [ -d "$HOME/Library/Android/sdk/ndk" ]; then
        # Find latest NDK version
        ANDROID_NDK_HOME=$(ls -d "$HOME/Library/Android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
    elif [ -d "$HOME/Android/Sdk/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$HOME/Android/Sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
    elif [ -d "/usr/local/lib/android/sdk/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "/usr/local/lib/android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
    fi
fi

if [ -z "$ANDROID_NDK_HOME" ] || [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo "Error: Android NDK not found."
    echo "Please set ANDROID_NDK_HOME environment variable."
    echo ""
    echo "Install NDK via Android Studio: SDK Manager > SDK Tools > NDK"
    echo "Or via command line: sdkmanager --install 'ndk;26.1.10909125'"
    exit 1
fi

echo "Using NDK: $ANDROID_NDK_HOME"

# Output directory
OUTPUT_DIR="$SCRIPT_DIR/target/android"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Android API level (minimum supported)
API_LEVEL=21

# Configure cargo for Android cross-compilation
export ANDROID_NDK_HOME
export PATH="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin:$PATH"
export PATH="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"

# Create cargo config for Android targets
mkdir -p .cargo
cat > .cargo/config.toml << EOF
[target.aarch64-linux-android]
ar = "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-ar"
linker = "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android${API_LEVEL}-clang"

[target.armv7-linux-androideabi]
ar = "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-ar"
linker = "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/armv7a-linux-androideabi${API_LEVEL}-clang"

[target.x86_64-linux-android]
ar = "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-ar"
linker = "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/x86_64-linux-android${API_LEVEL}-clang"

[target.i686-linux-android]
ar = "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-ar"
linker = "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/i686-linux-android${API_LEVEL}-clang"
EOF

# Detect host OS and update config if on Linux
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sed -i 's/darwin-x86_64/linux-x86_64/g' .cargo/config.toml
fi

echo "==> Installing Android targets..."
rustup target add aarch64-linux-android
rustup target add armv7-linux-androideabi
rustup target add x86_64-linux-android
rustup target add i686-linux-android

echo "==> Building for arm64-v8a..."
cargo build --release --target aarch64-linux-android

echo "==> Building for armeabi-v7a..."
cargo build --release --target armv7-linux-androideabi

echo "==> Building for x86_64..."
cargo build --release --target x86_64-linux-android

echo "==> Building for x86..."
cargo build --release --target i686-linux-android

echo "==> Copying libraries to output directory..."
mkdir -p "$OUTPUT_DIR/jniLibs/arm64-v8a"
mkdir -p "$OUTPUT_DIR/jniLibs/armeabi-v7a"
mkdir -p "$OUTPUT_DIR/jniLibs/x86_64"
mkdir -p "$OUTPUT_DIR/jniLibs/x86"

cp target/aarch64-linux-android/release/libcarry_engine.so "$OUTPUT_DIR/jniLibs/arm64-v8a/"
cp target/armv7-linux-androideabi/release/libcarry_engine.so "$OUTPUT_DIR/jniLibs/armeabi-v7a/"
cp target/x86_64-linux-android/release/libcarry_engine.so "$OUTPUT_DIR/jniLibs/x86_64/"
cp target/i686-linux-android/release/libcarry_engine.so "$OUTPUT_DIR/jniLibs/x86/"

echo "==> Done! Libraries created at:"
echo "    $OUTPUT_DIR/jniLibs/"
echo ""
echo "Directory structure:"
find "$OUTPUT_DIR/jniLibs" -name "*.so" | while read f; do
    echo "    $f ($(du -h "$f" | cut -f1))"
done
echo ""
echo "To use in your Flutter Android app:"
echo "1. Copy jniLibs/ to android/app/src/main/"
echo "2. Or add to build.gradle: android.sourceSets.main.jniLibs.srcDirs = ['src/main/jniLibs']"
