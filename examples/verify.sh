#!/usr/bin/env bash
#
# Builds and runs every example of jenesis.build/why/tool/ with its own tool and checks what it printed. Each
# example's .verify holds the command on its first line and, on its second, a line the output must contain.
#
#   examples/verify.sh                   # every example
#   examples/verify.sh basic tests/maven # the examples of one section, or one example
#
# Needs a JDK 25 on the PATH and, for the examples of each tool, Maven 3.9.16 (mvn), Bazelisk or Bazel 9.2.0
# (bazel) and a Docker daemon; each Gradle example's wrapper downloads Gradle 9.8.0. A Jenesis example uses
# build/jenesis/ when it is there; otherwise it links JENESIS_HOME, a checkout's sources/build/jenesis folder, or
# installs the release that JENESIS_REF names (the latest by default) with https://get.jenesis.build.

set -uo pipefail

EXAMPLES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

jenesis() {
    [ -e "$1/build/jenesis" ] && return 0
    mkdir -p "$1/build"
    if [ -n "${JENESIS_HOME:-}" ]; then
        ln -s "$JENESIS_HOME" "$1/build/jenesis"
    else
        (cd "$1" && curl -fsSL https://get.jenesis.build | JENESIS_MODE=vendor bash -s -- ${JENESIS_REF:-})
    fi
}

selected() {
    [ "$#" -eq 1 ] && return 0
    local name="$1" pattern
    shift
    for pattern in "$@"; do
        case "$name" in "${pattern%/}" | "${pattern%/}"/*) return 0 ;; esac
    done
    return 1
}

passed=0
failed=()
for spec in "$EXAMPLES"/*/*/.verify; do
    folder="$(dirname "$spec")"
    name="${folder#"$EXAMPLES"/}"
    selected "$name" "$@" || continue
    command="$(sed -n 1p "$spec")"
    expected="$(sed -n 2p "$spec")"
    case "$name" in */jenesis) jenesis "$folder" ;; esac
    printf '%-28s %s\n' "$name" "$command"
    log="$(mktemp)"
    if (cd "$folder" && bash -c "$command") >"$log" 2>&1 && grep -qF -- "$expected" "$log"; then
        passed=$((passed + 1))
    else
        failed+=("$name")
        echo "  expected: $expected"
        tail -n 20 "$log" | sed 's/^/  | /'
    fi
    rm -f "$log"
done

echo
echo "$passed passed, ${#failed[@]} failed${failed[*]:+: ${failed[*]}}"
[ "${#failed[@]}" -eq 0 ]
