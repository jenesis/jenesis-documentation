#!/usr/bin/env bash
set -euo pipefail

main=sources/demo/app/Main.java
greeter=sources/demo/app/Greeter.java
saved="$(mktemp -d)"
cp "$main" "$greeter" "$saved"
trap 'cp "$saved"/Main.java "$main"; cp "$saved"/Greeter.java "$greeter"; rm -rf "$saved"' EXIT
rm -rf target .jenesis/cache

compile=module-sources/produce/assemble/binary/compiled/compile/javac

build() {
    echo "\$ java build/jenesis/Make.java    # $1"
    java -Djenesis.print.tests=true -Djenesis.print.cache=true build/jenesis/Make.java 2>&1 \
        | sed 's/\x1b\[[0-9;]*m//g' > "$saved/log"
    grep -E 'greets\(\)|COMPLETED' "$saved/log" || true
}

tested() {
    grep -q 'greets() ✔' "$saved/log" || { echo "expected GreeterTest to run: $1"; exit 1; }
}

untested() {
    ! grep -q 'greets()' "$saved/log" || { echo "expected no test to run: $1"; exit 1; }
}

compiled() {
    grep -q "^\[EXECUTED\] .*/$compile " "$saved/log" || { echo "expected a compilation: $1"; exit 1; }
}

cached() {
    grep -q "^\[LOADED\] .*/$compile " "$saved/log" || { echo "expected the compilation from the cache: $1"; exit 1; }
}

build "first build"
tested "first build"

build "nothing changed"
untested "nothing changed"
! grep -q "^\[EXECUTED\] .*/$compile " "$saved/log" || { echo "expected no compilation: nothing changed"; exit 1; }

sed -i 's/args.length == 0/args.length < 1/' "$main"
build "Main.java edited"
compiled "Main.java edited"
untested "Main.java edited"

sed -i 's/return "Hello, " + name + "!";/return "Hello, %s!".formatted(name);/' "$greeter"
build "Greeter.java edited"
tested "Greeter.java edited"

cp "$saved"/Main.java "$main"
cp "$saved"/Greeter.java "$greeter"
build "both edits undone"
cached "both edits undone"
untested "both edits undone"

rm -rf target
build "target wiped"
cached "target wiped"
untested "target wiped"

echo "caching verified"
