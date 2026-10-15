#!/usr/bin/env bash
# Runs the DeskPetCore unit tests. With only the Command Line Tools installed,
# Swift Testing lives outside the default search paths, so point at it.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

DEV="$(xcode-select -p)"
FW="$DEV/Library/Developer/Frameworks"
LIB="$DEV/Library/Developer/usr/lib"

if [[ -d "$FW/Testing.framework" ]]; then
  swift test \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" "$@"
else
  swift test "$@" # full Xcode: works out of the box
fi
