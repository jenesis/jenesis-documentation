# Sourced by benchmarks/<project>/run.sh, which sets, before sourcing it:
#
#   UPSTREAM, COMMIT   the project's repository and the commit the migration starts from
#   OLD                maven or gradle, the build the project had
#   EDITED             the main source file the edit build changes, relative to the project's root
#   edit <token>       makes the edit, naming a local variable <token> so that no earlier build has seen it
#   jenesis            runs the Jenesis build (in the project's root), passing $JENESIS_MODE to java
#   old full|again     runs the original build, from scratch or once more, through the mvn or gradlew below
#
# A project script may call root, true where the user is root, who reads a file whose read permission is taken away.
#
# The project is cloned into a temporary folder, the migration patch applied and committed, and Jenesis installed
# into it from JENESIS_REF; the original build runs in a worktree of the same commit, so neither tool reads the
# other's output. Each tool gets one unmeasured warm-up, then ROUNDS rounds of a full build from scratch, the same
# build again with nothing changed, and a build after the edit, which is reverted afterwards.
#
# Settings, as environment variables:
#   JENESIS_REF      the Jenesis commit, tag or branch to install (default: the one the published numbers used)
#   ROUNDS           rounds per tool (default 3; 1 for a project whose full build takes more than five minutes)
#   PAIRINGS         nodaemon, daemon or both: with a daemon, Gradle runs with --daemon and Jenesis under
#                    jenesis.make.mode=daemon (default: nodaemon; Gradle projects: nodaemon daemon)
#   MAVEN_MIRROR     a Maven Central mirror for all three tools, where repo.maven.apache.org is rate-limited
#   BENCHMARK_FOLDER the folder to work in (default: a new temporary folder), which keeps logs/ and results.tsv
#
# Downloaded dependencies stay in ~/.m2, ~/.gradle and ~/.jenesis, as they would on a developer's machine.

set -uo pipefail

JENESIS_REF="${JENESIS_REF:-84f478894cd39a8c89d56fe0f77f44fec14d8754}"
BENCHMARKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)")"
PATCH="$BENCHMARKS/$NAME/migration.patch"

die() {
    echo "$NAME: $*" >&2
    exit 2
}

say() {
    printf '\n== %s\n' "$*"
}

java_version="$(java -XshowSettings:properties -version 2>&1 | sed -n 's/^ *java\.specification\.version = //p')"
[ "${java_version:-0}" -ge 25 ] 2>/dev/null || die "needs a JDK 25 or newer as java (found: ${java_version:-none})"
for tool in git curl python3; do
    command -v "$tool" >/dev/null || die "needs $tool"
done
[ "$OLD" = maven ] && ! command -v mvn >/dev/null && die "needs Maven as mvn"
[ -f "$PATCH" ] || die "no migration patch at $PATCH"
case "$(locale charmap 2>/dev/null)" in UTF-8) ;; *) export LANG=C.UTF-8 ;; esac
# Maven and Gradle follow JAVA_HOME, so all three tools run on the java the PATH names.
export JAVA_HOME="$(java -XshowSettings:properties -version 2>&1 | sed -n 's/^ *java\.home = //p')"

if [ -z "${PAIRINGS:-}" ]; then
    if [ "$OLD" = gradle ]; then PAIRINGS="nodaemon daemon"; else PAIRINGS=nodaemon; fi
fi
ROUNDS="${ROUNDS:-3}"
WORK="${BENCHMARK_FOLDER:-$(mktemp -d "${TMPDIR:-/tmp}/jenesis-benchmark-$NAME.XXXXXX")}"
PROJECT="$WORK/$NAME" ORIGINAL="$WORK/$NAME-$OLD" LOGS="$WORK/logs" RESULTS="$WORK/results.tsv"
mkdir -p "$LOGS"
[ -e "$PROJECT" ] && die "$PROJECT exists already; name an empty BENCHMARK_FOLDER"
NONCE="$(date +%s)"

# A mirror is handed to Maven as a settings file, to Gradle as an init script and to Jenesis as the variable it reads.
MAVEN_ARGS=() GRADLE_ARGS=(--no-scan --init-script "$WORK/benchmark.init.gradle")
if [ -n "${MAVEN_MIRROR:-}" ]; then
    cat >"$WORK/settings.xml" <<EOF
<settings>
  <mirrors>
    <mirror><id>benchmark</id><mirrorOf>central</mirrorOf><url>$MAVEN_MIRROR</url></mirror>
  </mirrors>
</settings>
EOF
    MAVEN_ARGS=(-s "$WORK/settings.xml")
    export MAVEN_REPOSITORY_URI="$MAVEN_MIRROR"
fi
# Neither build reads a remote build cache, and Gradle reads the mirror where one is named.
cat >"$WORK/benchmark.init.gradle" <<EOF
def mirror = '${MAVEN_MIRROR:-}'
def redirect = { RepositoryHandler repositories ->
    if (mirror) {
        repositories.configureEach { repository ->
            if (repository instanceof MavenArtifactRepository && repository.url.toString().startsWith('https://repo.maven.apache.org')) {
                repository.url = mirror
            }
        }
    }
}
def prepend = { RepositoryHandler repositories ->
    if (mirror && !repositories.findByName('benchmarkMirror')) {
        def first = repositories.maven { name = 'benchmarkMirror'; url = mirror }
        repositories.remove(first)
        repositories.addFirst(first)
    }
}
beforeSettings { settings ->
    redirect(settings.pluginManagement.repositories)
    prepend(settings.pluginManagement.repositories)
    redirect(settings.dependencyResolutionManagement.repositories)
    redirect(settings.buildscript.repositories)
}
settingsEvaluated { settings ->
    redirect(settings.dependencyResolutionManagement.repositories)
    if (settings.buildCache.remote != null) {
        settings.buildCache.remote.enabled = false
    }
}
allprojects {
    redirect(buildscript.repositories)
    redirect(repositories)
}
EOF

mvn() {
    command mvn "${MAVEN_ARGS[@]}" "$@"
}

gradlew() {
    ./gradlew "$GRADLE_MODE" "${GRADLE_ARGS[@]}" "$@"
}

# replace <file> <old> <new>: replaces the one occurrence of <old>, failing where there is none or more than one.
replace() {
    python3 -I - "$1" "$2" "$3" <<'EOF'
import sys
path, old, new = sys.argv[1:]
text = open(path, encoding='utf-8').read()
if text.count(old) != 1:
    sys.exit(f'{path}: expected the text to change once, found it {text.count(old)} times: {old!r}')
open(path, 'w', encoding='utf-8').write(text.replace(old, new, 1))
EOF
}

root() {
    [ "$(id -u)" -eq 0 ]
}

# measure <pairing> <tool> <measurement> <round> <command...>: runs the command in the current folder and records it.
measure() {
    local pairing=$1 tool=$2 measurement=$3 round=$4 log start end code
    shift 4
    log="$LOGS/$pairing-$tool-$measurement-$round.log"
    start=$EPOCHREALTIME
    "$@" >"$log" 2>&1
    code=$?
    end=$EPOCHREALTIME
    local seconds
    seconds="$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%.1f", e - s }')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$pairing" "$tool" "$measurement" "$round" "$seconds" "$code" >>"$RESULTS"
    printf '%-9s %-8s %-8s %s  %6s s%s\n' "$pairing" "$tool" "$measurement" "$round" "$seconds" \
        "$([ "$code" -eq 0 ] || echo "  FAILED, see $log")"
    [ "$code" -eq 0 ] || die "the $measurement build failed: tail $log"
}

say "Cloning $UPSTREAM at $COMMIT into $PROJECT"
git init -q "$PROJECT" && cd "$PROJECT" || die "cannot create $PROJECT"
git remote add origin "$UPSTREAM"
git fetch -q --depth 1 origin "$COMMIT" || die "cannot fetch $COMMIT from $UPSTREAM"
git checkout -q FETCH_HEAD
git apply --index "$PATCH" || die "the migration patch does not apply to $COMMIT"
git -c user.name=benchmark -c user.email=benchmark@example.invalid commit -q -m "Build with Jenesis"
git worktree add -q --detach "$ORIGINAL" HEAD

say "Installing Jenesis at $JENESIS_REF"
curl -fsSL https://get.jenesis.build | JENESIS_MODE=vendor JENESIS_TARGET="$PROJECT" bash -s -- "$JENESIS_REF" \
    || die "cannot install Jenesis at $JENESIS_REF"

printf 'pairing\ttool\tmeasurement\tround\tseconds\texit\n' >"$RESULTS"
for pairing in $PAIRINGS; do
    case "$pairing" in
        nodaemon) JENESIS_MODE="" GRADLE_MODE=--no-daemon ;;
        daemon) JENESIS_MODE=-Djenesis.make.mode=daemon GRADLE_MODE=--daemon ;;
        *) die "PAIRINGS takes nodaemon and daemon, not $pairing" ;;
    esac

    say "Jenesis ($pairing)"
    cd "$PROJECT" || exit 2
    rm -rf target
    measure "$pairing" jenesis warmup 0 jenesis
    for round in $(seq "$ROUNDS"); do
        rm -rf target
        measure "$pairing" jenesis full "$round" jenesis
        measure "$pairing" jenesis again "$round" jenesis
        edit "j${NONCE}${pairing}${round}"
        measure "$pairing" jenesis edit "$round" jenesis
        git checkout -q -- "$EDITED"
    done
    [ "$pairing" = daemon ] && java -Djenesis.make.mode=daemon build/jenesis/Make.java --stop >/dev/null 2>&1
    rm -rf target

    say "$OLD ($pairing)"
    cd "$ORIGINAL" || exit 2
    measure "$pairing" "$OLD" warmup 0 old full
    for round in $(seq "$ROUNDS"); do
        measure "$pairing" "$OLD" full "$round" old full
        measure "$pairing" "$OLD" again "$round" old again
        edit "o${NONCE}${pairing}${round}"
        measure "$pairing" "$OLD" edit "$round" old again
        git checkout -q -- "$EDITED"
        old again >"$LOGS/$pairing-$OLD-restore-$round.log" 2>&1
    done
    [ "$OLD" = gradle ] && ./gradlew --stop >/dev/null 2>&1
done

cd "$WORK" || exit 2
git -C "$PROJECT" worktree remove --force "$ORIGINAL"
rm -rf "${PROJECT:?}"

say "Medians of $ROUNDS round(s), in seconds"
awk -F'\t' 'NR > 1 && $3 != "warmup" { v[$1 "\t" $2 "\t" $3] = v[$1 "\t" $2 "\t" $3] " " $5 }
    END {
        printf "%-9s %-8s %8s %8s %8s\n", "pairing", "tool", "full", "again", "edit"
        for (key in v) { split(key, k, "\t"); seen[k[1] "\t" k[2]] = 1 }
        for (pair in seen) {
            split(pair, p, "\t"); line = sprintf("%-9s %-8s", p[1], p[2])
            for (i = 1; i <= 3; i++) {
                m = (i == 1 ? "full" : i == 2 ? "again" : "edit")
                n = split(v[pair "\t" m], xs, " ")
                for (a = 1; a <= n; a++) for (b = a + 1; b <= n; b++) if (xs[b] + 0 < xs[a] + 0) { t = xs[a]; xs[a] = xs[b]; xs[b] = t }
                line = line sprintf(" %8s", xs[int((n + 1) / 2)])
            }
            print line
        }
    }' "$RESULTS" | sort -k1,1r -k2,2
echo
echo "Every run is in $RESULTS, its output in $LOGS."
