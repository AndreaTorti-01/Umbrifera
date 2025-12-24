#!/bin/bash
set -e

# Configure and Build
# ARM64 only build
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build build --config Release -j$(sysctl -n hw.ncpu)

# Sign the app bundle with ad-hoc signature
echo "Signing app bundle..."
codesign --deep --force --sign - build/Imago.app

echo "Build complete: build/Imago.app"
