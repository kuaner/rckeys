#!/bin/zsh
# rckeys 构建（只需 Command Line Tools，无需完整 Xcode）
set -e
cd "$(dirname "$0")"
mkdir -p .build
swiftc -O Sources/*.swift -o .build/rckeys
[ -d Resources ] && cp -R Resources .build/ 2>/dev/null
echo "构建完成: .build/rckeys"
.build/rckeys --self-test
