#!/usr/bin/env bash
# swift-testing under the Command Line Tools (no Xcode) needs its macro plugin
# and runtime libraries passed in by hand.
set -euo pipefail
cd "$(dirname "$0")/.."
CLT="$(xcode-select -p)"
if [[ "$CLT" == *CommandLineTools* ]]; then
  exec swift test \
    -Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing" \
    -Xlinker -rpath -Xlinker "$CLT/Library/Developer/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Library/Developer/usr/lib" \
    "$@"
fi
exec swift test "$@"
