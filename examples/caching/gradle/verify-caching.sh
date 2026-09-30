#!/usr/bin/env bash
set -euo pipefail

main=src/main/java/demo/app/Main.java
saved="$(mktemp -d)"
cp "$main" "$saved"
trap 'cp "$saved"/Main.java "$main"; rm -rf "$saved"' EXIT

build() {
    echo "\$ gradle build    # $1"
    gradle --no-daemon --console=plain build > "$saved/log" 2>&1 || { cat "$saved/log"; exit 1; }
    grep -E '^> Task :(compileJava|compileTestJava|test)( |$)' "$saved/log" || true
}

outcome() {
    grep -qE "^> Task :$1$2\$" "$saved/log" || { echo "expected :$1 to be ${2:- executed}: $3"; exit 1; }
}

build "first build"

build "nothing changed"
outcome compileJava " UP-TO-DATE" "nothing changed"
outcome test " UP-TO-DATE" "nothing changed"

sed -i "s/^public class Main {/public class Main {\n\n    static final String EDITED = \"$(date +%s%N)\";/" "$main"
build "Main.java edited"
outcome compileJava "" "Main.java edited"
outcome test "" "Main.java edited"

cp "$saved"/Main.java "$main"
build "edit undone"
outcome compileJava " FROM-CACHE" "edit undone"
outcome test " FROM-CACHE" "edit undone"

rm -rf build
build "build folder wiped"
outcome compileJava " FROM-CACHE" "build folder wiped"
outcome test " FROM-CACHE" "build folder wiped"

echo "caching verified"
