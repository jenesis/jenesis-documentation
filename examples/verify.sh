#!/usr/bin/env bash
#
# Builds and runs every example of jenesis.build/why/tool/ with its own tool and checks what it printed. Each
# example's .verify holds the command on its first line and, on its second, a line the output must contain.
#
#   examples/verify.sh                   # every example
#   examples/verify.sh basic tests/maven # the examples of one section, or one example
#
# Needs a JDK 25 on the PATH and, for the examples of each tool, Maven 3.9.16 (mvn), Bazelisk or Bazel 9.2.0
# (bazel) and a Docker daemon; each Gradle example's wrapper downloads Gradle 9.8.0. The tools the selected
# examples need are checked before any of them runs.
#
# Jenesis is installed once per run into examples/.jenesis-install/ with https://get.jenesis.build, from its main
# branch or the git ref JENESIS_REF names (a tag such as v0.15.2, or a commit), and every Jenesis example links it
# as build/jenesis. JENESIS_SOURCES instead names a folder holding Make.java, such as a checkout's
# sources/build/jenesis. JENESIS_HOME is not read: SDKMAN sets it to its own installation, which is no such folder.
#
# An example that fails on a download - a reset connection, HTTP 429 from Maven Central - is run once more.

set -uo pipefail

EXAMPLES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
    echo "verify.sh: $*" >&2
    exit 2
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

specs=()
for spec in "$EXAMPLES"/*/*/.verify; do
    name="$(dirname "${spec#"$EXAMPLES"/}")"
    selected "$name" "$@" && specs+=("$spec")
done
[ "${#specs[@]}" -gt 0 ] || die "no example matches: $*"

# Every tool the selection needs, checked up front, so a missing one is named once rather than failing each example.
needs() {
    local spec
    for spec in "${specs[@]}"; do
        case "$spec" in */"$1"/.verify) return 0 ;; esac
    done
    return 1
}
missing=()
java_version="$(java -XshowSettings:properties -version 2>&1 | sed -n 's/^ *java\.specification\.version = //p')"
[ "$java_version" = 25 ] || missing+=("a JDK 25 as java (found: ${java_version:-none})")
needs maven && ! command -v mvn >/dev/null && missing+=("Maven 3.9.16 as mvn")
needs bazel && ! command -v bazel >/dev/null && missing+=("Bazelisk as bazel")
for spec in "${specs[@]}"; do
    case "$spec" in */docker/*/.verify)
        docker info >/dev/null 2>&1 || missing+=("a running Docker daemon")
        break ;;
    esac
done
[ "${#missing[@]}" -eq 0 ] || die "the selected examples need $(printf '%s, ' "${missing[@]}" | sed 's/, $//')"

if needs jenesis; then
    if [ -n "${JENESIS_SOURCES:-}" ]; then
        [ -f "$JENESIS_SOURCES/Make.java" ] || die "JENESIS_SOURCES=$JENESIS_SOURCES holds no Make.java"
        sources="$(cd "$JENESIS_SOURCES" && pwd)"
    else
        install="$EXAMPLES/.jenesis-install"
        rm -rf "${install:?}"
        mkdir -p "$install"
        curl -fsSL https://get.jenesis.build \
            | JENESIS_MODE=vendor JENESIS_TARGET="$install" bash -s -- "${JENESIS_REF:-main}" \
            || die "could not install Jenesis at ${JENESIS_REF:-main}"
        sources="$install/build/jenesis"
    fi
    echo "Jenesis from $sources"
    echo
fi

# The link is replaced on every run, so no example keeps a Jenesis that an earlier run left in its build folder.
jenesis() {
    local link="$1/build/jenesis"
    mkdir -p "$1/build"
    rm -rf "${link:?}"
    ln -s "$sources" "$link"
}

# A failure on a download rather than in the build: the output of Maven, Gradle and Coursier when a connection
# drops or Maven Central answers a burst of requests with HTTP 429.
flaky() {
    grep -qiE 'connection reset|connection refused|timed out|status code 429|HTTP 429|Too Many Requests|download error|Could not transfer artifact|UnknownHostException' "$1"
}

run() {
    (cd "$1" && bash -c "$2") >"$4" 2>&1 && grep -qF -- "$3" "$4"
}

passed=0
failed=()
for spec in "${specs[@]}"; do
    folder="$(dirname "$spec")"
    name="${folder#"$EXAMPLES"/}"
    command="$(sed -n 1p "$spec")"
    expected="$(sed -n 2p "$spec")"
    case "$name" in */jenesis) jenesis "$folder" ;; esac
    printf '%-28s %s\n' "$name" "$command"
    log="$(mktemp)"
    if run "$folder" "$command" "$expected" "$log"; then
        passed=$((passed + 1))
    elif flaky "$log" && echo "  a download failed, running it again" && run "$folder" "$command" "$expected" "$log"; then
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
