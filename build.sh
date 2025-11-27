#!/bin/bash
set -e

# Configure and Build
# ARM64 only build
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build build --config Release -j$(sysctl -n hw.ncpu)
