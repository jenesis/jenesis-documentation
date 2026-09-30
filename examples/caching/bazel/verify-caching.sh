#!/usr/bin/env bash
set -euo pipefail

main=src/main/java/demo/app/Main.java
saved="$(mktemp -d)"
cp "$main" "$saved"
trap 'cp "$saved"/Main.java "$main"; rm -rf "$saved"' EXIT

build() {
    echo "\$ bazel test //...    # $1"
    bazel test //... > "$saved/log" 2>&1 || { cat "$saved/log"; exit 1; }
    grep -E '^//:GreeterTest|processes:' "$saved/log" || true
}

tested() {
    grep -E '^//:GreeterTest ' "$saved/log" | grep -v '(cached)' | grep -q PASSED \
        || { echo "expected GreeterTest to run: $1"; exit 1; }
}

cached() {
    grep -E '^//:GreeterTest ' "$saved/log" | grep -q '(cached) PASSED' \
        || { echo "expected GreeterTest from the cache: $1"; exit 1; }
}

build "first build"

build "nothing changed"
cached "nothing changed"

sed -i "s/^public class Main {/public class Main {\n\n    static final String EDITED = \"$(date +%s%N)\";/" "$main"
build "Main.java edited"
tested "Main.java edited"

cp "$saved"/Main.java "$main"
build "edit undone"
cached "edit undone"

bazel clean > /dev/null 2>&1
build "after bazel clean"
cached "after bazel clean"
grep -q 'disk cache hit' "$saved/log" || { echo "expected actions from the disk cache: after bazel clean"; exit 1; }

echo "caching verified"
