#!/bin/bash
# Compile each probe to a binary alongside its source. Binaries are gitignored.
set -e
cd "$(dirname "$0")"
for f in *.swift; do
    out="${f%.swift}"
    printf '%-12s' "$out"
    swiftc -O "$f" -o "$out" && echo "ok"
done
