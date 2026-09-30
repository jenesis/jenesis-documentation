#!/usr/bin/env bash
set -euo pipefail
digest() { (cd "$1" && find target/stage -type f -exec sha256sum {} + | sort -k 2 | sha256sum); }
rm -rf target
java build/jenesis/Make.java stage
second=target/second
mkdir -p "$second/build"
cp -r sources "$second/"
ln -s "$(cd build/jenesis && pwd -P)" "$second/build/jenesis"
(cd "$second" && umask 077 && TZ=Pacific/Kiritimati java build/jenesis/Make.java stage)
first="$(digest .)"
again="$(digest "$second")"
echo "first build:  $first"
echo "second build: $again"
[ "$first" = "$again" ] && echo "The staged files are identical"
