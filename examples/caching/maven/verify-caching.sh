#!/usr/bin/env bash
set -euo pipefail

main=src/main/java/demo/app/Main.java
saved="$(mktemp -d)"
cp "$main" "$saved"
trap 'cp "$saved"/Main.java "$main"; rm -rf "$saved"' EXIT
rm -rf target

build() {
    echo "\$ mvn verify    # $1"
    mvn -B verify -Dmaven.build.cache.location="$saved/cache" > "$saved/log" 2>&1 || { cat "$saved/log"; exit 1; }
    grep -E 'Tests run: [0-9]+, Failures: [0-9]+, Errors: [0-9]+, Skipped: [0-9]+$|from cache by checksum|BUILD' "$saved/log" || true
}

tested() {
    grep -q 'Tests run: 1, Failures: 0' "$saved/log" || { echo "expected GreeterTest to run: $1"; exit 1; }
}

restored() {
    grep -q 'Skipping plugin execution (cached): surefire:test' "$saved/log" \
        && ! grep -q 'Tests run:' "$saved/log" \
        || { echo "expected the module from the cache: $1"; exit 1; }
}

build "first build"
tested "first build"

build "nothing changed"
restored "nothing changed"

sed -i 's/args.length == 0/args.length < 1/' "$main"
build "Main.java edited"
tested "Main.java edited"

cp "$saved"/Main.java "$main"
build "edit undone"
restored "edit undone"

rm -rf target
build "target wiped"
restored "target wiped"
test -f target/app-1.0.0.jar

echo "caching verified"
