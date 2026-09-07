#!/bin/bash
set -euo pipefail
# Some upgraded Command Line Tools installations retain an old private
# PackageDescription interface beside a Swift 6 public interface and library.
# Use a project-local copy of the matching public interface in that case.
# This never changes the installed Apple toolchain.
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_EXECUTABLE="$(xcrun --find swift)"
API_DIR="$(dirname "$SWIFT_EXECUTABLE")/../lib/swift/pm/ManifestAPI"
ARCH="$(uname -m)"
PUBLIC_INTERFACE="$API_DIR/PackageDescription.swiftmodule/$ARCH-apple-macos.swiftinterface"
PRIVATE_INTERFACE="$API_DIR/PackageDescription.swiftmodule/$ARCH-apple-macos.private.swiftinterface"
if [ -f "$PUBLIC_INTERFACE" ] && [ -f "$PRIVATE_INTERFACE" ] &&
   grep -q 'public enum SwiftLanguageMode' "$PUBLIC_INTERFACE" &&
   grep -q 'public enum SwiftVersion' "$PRIVATE_INTERFACE"; then
    LOCAL_LIBS="$PROJECT_ROOT/.build/manifest-runtime"
    mkdir -p "$LOCAL_LIBS"
    ditto "$API_DIR" "$LOCAL_LIBS/ManifestAPI"
    for MODULE in PackageDescription CompilerPluginSupport; do
        for CPU in x86_64 arm64; do
            rm -f "$LOCAL_LIBS/ManifestAPI/$MODULE.swiftmodule/$CPU-apple-macos.private.swiftinterface"
        done
    done
    export SWIFTPM_CUSTOM_LIBS_DIR="$LOCAL_LIBS"
fi
# Command Line Tools can ship Swift Testing without SwiftPM's usual framework
# search paths. Provide those paths explicitly when running this test suite.
if [ "${1:-}" = "test" ]; then
    DEVELOPER_DIR_PATH="$(xcode-select -p)"
    TEST_FRAMEWORKS="$DEVELOPER_DIR_PATH/Library/Developer/Frameworks"
    TEST_LIBS="$DEVELOPER_DIR_PATH/Library/Developer/usr/lib"
    if [ -d "$TEST_FRAMEWORKS/Testing.framework" ]; then
        shift
        exec "$SWIFT_EXECUTABLE" test --disable-xctest \
            -Xswiftc -F -Xswiftc "$TEST_FRAMEWORKS" \
            -Xlinker -F -Xlinker "$TEST_FRAMEWORKS" \
            -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS" \
            -Xlinker -rpath -Xlinker "$TEST_LIBS" "$@"
    fi
fi
exec "$SWIFT_EXECUTABLE" "$@"
