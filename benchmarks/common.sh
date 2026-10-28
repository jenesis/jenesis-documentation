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
# build again with nothing changed, and a build after the edit, which is reverted afterwards. A round in which a build
# fails, as a project's own test can race, is run once more from scratch, and a second failure ends the run; the
# failed round stays in results.tsv and logs/, marked as discarded, and no median counts it.
#
# Settings, as environment variables:
#   JENESIS_REF      the Jenesis commit, tag or branch to install (default: the one the published numbers used)
#   ROUNDS           rounds per tool (default 3)
#   PAIRINGS         nodaemon, daemon or both: without a daemon, Maven runs as mvn, Gradle with --no-daemon and
#                    Jenesis under jenesis.make.mode=compiled; with one, Maven as the Maven Daemon, mvnd, Gradle
#                    with --daemon and Jenesis under jenesis.make.mode=daemon (default: both)
#   MAVEN_MIRROR     a Maven Central mirror for all three tools, where repo.maven.apache.org is rate-limited
#   BENCHMARK_FOLDER the folder to work in (default: a new temporary folder), which keeps logs/ and results.tsv
#
# Downloaded dependencies stay in ~/.m2, ~/.gradle and ~/.jenesis, as they would on a developer's machine. Jenesis
# runs with -Djenesis.make.global= and so reads no ~/.jenesis/jenesis.properties: the settings of the machine it runs
# on cannot replace what the migration declares, such as the repositories a project resolves from.

set -uo pipefail

JENESIS_REF="${JENESIS_REF:-f5aadaf7f2291e45f96341e61409e8b1c6e10454}"
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

PAIRINGS="${PAIRINGS:-nodaemon daemon}"
case " $PAIRINGS " in
    *" daemon "*) [ "$OLD" = maven ] && ! command -v mvnd >/dev/null \
        && die "needs the Maven Daemon as mvnd for the daemon pairing, or PAIRINGS=nodaemon" ;;
esac
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
# Neither build reads a remote build cache, and Gradle reads the mirror where one is named: in place of Central, and
# ahead of every repository list a build declares, as the Plugin Portal redirects to Central what it holds there.
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
def declare = { RepositoryHandler repositories ->
    if (mirror && !repositories.findByName('benchmarkMirror')) {
        repositories.maven { name = 'benchmarkMirror'; url = mirror }
    }
}
def prepend = { RepositoryHandler repositories ->
    if (mirror && !repositories.isEmpty() && !repositories.findByName('benchmarkMirror')) {
        def first = repositories.maven { name = 'benchmarkMirror'; url = mirror }
        repositories.remove(first)
        repositories.addFirst(first)
    }
}
beforeSettings { settings ->
    redirect(settings.pluginManagement.repositories)
    if (mirror && settings.pluginManagement.repositories.isEmpty()) {
        settings.pluginManagement.repositories.gradlePluginPortal()
    }
    prepend(settings.pluginManagement.repositories)
    redirect(settings.dependencyResolutionManagement.repositories)
    redirect(settings.buildscript.repositories)
    declare(settings.buildscript.repositories)
}
settingsEvaluated { settings ->
    redirect(settings.dependencyResolutionManagement.repositories)
    prepend(settings.dependencyResolutionManagement.repositories)
    if (settings.buildCache.remote != null) {
        settings.buildCache.remote.enabled = false
    }
}
gradle.lifecycle.beforeProject { project ->
    redirect(project.buildscript.repositories)
    declare(project.buildscript.repositories)
    redirect(project.repositories)
}
gradle.lifecycle.afterProject { project ->
    prepend(project.repositories)
}
EOF

mvn() {
    command "$MAVEN_COMMAND" "${MAVEN_ARGS[@]}" "$@"
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
    return "$code"
}

# discard <pairing> <tool> <round>: marks the rows and logs of a failed round, which the medians leave out.
discard() {
    awk -F'\t' -v OFS='\t' -v p="$1" -v t="$2" -v r="$3" '$1 == p && $2 == t && $4 == r { $4 = r "-discarded" } 1' \
        "$RESULTS" >"$RESULTS.tmp" && mv "$RESULTS.tmp" "$RESULTS"
    local log
    for log in "$LOGS/$1-$2-"*"-$3.log"; do
        [ -e "$log" ] && mv "$log" "${log%.log}-discarded.log"
    done
}

# jenesis_round and old_round <pairing> <round> <attempt>: a full build, the same build again and one after the edit.
jenesis_round() {
    rm -rf target
    measure "$1" jenesis full "$2" jenesis \
        && measure "$1" jenesis again "$2" jenesis \
        && { edit "j${NONCE}$1$2$3" || die "the edit did not apply"; } \
        && measure "$1" jenesis edit "$2" jenesis
    local code=$?
    git checkout -q -- "$EDITED"
    return "$code"
}

old_round() {
    measure "$1" "$OLD" full "$2" old full \
        && measure "$1" "$OLD" again "$2" old again \
        && { edit "o${NONCE}$1$2$3" || die "the edit did not apply"; } \
        && measure "$1" "$OLD" edit "$2" old again
    local code=$?
    git checkout -q -- "$EDITED"
    old again >"$LOGS/$1-$OLD-restore-$2.log" 2>&1
    return "$code"
}

# rounds <tool> <round function>: a round whose build fails, as a project's own test can race, runs once more.
rounds() {
    local round
    for round in $(seq "$ROUNDS"); do
        if ! "$2" "$pairing" "$round" a; then
            discard "$pairing" "$1" "$round"
            say "$1 ($pairing): round $round failed, so it runs once more"
            "$2" "$pairing" "$round" b || die "round $round of $1 failed twice: see $LOGS"
        fi
    done
}

say "Cloning $UPSTREAM at $COMMIT into $PROJECT"
git init -q "$PROJECT" && cd "$PROJECT" || die "cannot create $PROJECT"
git remote add origin "$UPSTREAM"
git fetch -q --depth 1 origin "$COMMIT" || die "cannot fetch $COMMIT from $UPSTREAM"
git checkout -q FETCH_HEAD
git apply --index "$PATCH" || die "the migration patch does not apply to $COMMIT"
git -c user.name=benchmark -c user.email=benchmark@example.invalid commit -q -m "Build with Jenesis"
git worktree add -q --detach "$ORIGINAL" HEAD

# A migration naming its own Maven remotes outranks the variable, so the mirror takes Central's place in that list,
# handed to Jenesis on the command line, which outranks the project's file.
JENESIS_REMOTES=
if [ -n "${MAVEN_MIRROR:-}" ] && [ -f jenesis.properties ]; then
    remotes="$(sed -n 's/^jenesis\.maven\.uri *= *//p' jenesis.properties)"
    if [ -n "$remotes" ]; then
        remotes="${remotes//https:\/\/repo.maven.apache.org\/maven2\//$MAVEN_MIRROR}"
        remotes="${remotes//https:\/\/repo1.maven.org\/maven2\//$MAVEN_MIRROR}"
        JENESIS_REMOTES="-Djenesis.maven.uri=${remotes// /}"
    fi
fi

say "Installing Jenesis at $JENESIS_REF"
curl -fsSL https://get.jenesis.build | JENESIS_MODE=vendor JENESIS_TARGET="$PROJECT" bash -s -- "$JENESIS_REF" \
    || die "cannot install Jenesis at $JENESIS_REF"

printf 'pairing\ttool\tmeasurement\tround\tseconds\texit\n' >"$RESULTS"
for pairing in $PAIRINGS; do
    case "$pairing" in
        nodaemon) JENESIS_MODE="-Djenesis.make.global= -Djenesis.make.mode=compiled $JENESIS_REMOTES" \
            GRADLE_MODE=--no-daemon MAVEN_COMMAND=mvn ;;
        daemon) JENESIS_MODE="-Djenesis.make.global= -Djenesis.make.mode=daemon $JENESIS_REMOTES" GRADLE_MODE=--daemon \
            MAVEN_COMMAND=mvnd ;;
        *) die "PAIRINGS takes nodaemon and daemon, not $pairing" ;;
    esac

    say "Jenesis ($pairing)"
    cd "$PROJECT" || exit 2
    rm -rf target
    measure "$pairing" jenesis warmup 0 jenesis || die "the warmup build failed: see $LOGS"
    rounds jenesis jenesis_round
    [ "$pairing" = daemon ] && java -Djenesis.make.mode=daemon build/jenesis/Make.java --stop >/dev/null 2>&1
    rm -rf target

    say "$OLD ($pairing)"
    cd "$ORIGINAL" || exit 2
    measure "$pairing" "$OLD" warmup 0 old full || die "the warmup build failed: see $LOGS"
    rounds "$OLD" old_round
    [ "$OLD" = gradle ] && ./gradlew --stop >/dev/null 2>&1
    [ "$OLD" = maven ] && [ "$pairing" = daemon ] && mvnd --stop >/dev/null 2>&1
done

cd "$WORK" || exit 2
git -C "$PROJECT" worktree remove --force "$ORIGINAL"
rm -rf "${PROJECT:?}"

say "Medians of $ROUNDS round(s), in seconds"
awk -F'\t' 'NR > 1 && $3 != "warmup" && $6 == 0 && $4 !~ /discarded/ { v[$1 "\t" $2 "\t" $3] = v[$1 "\t" $2 "\t" $3] " " $5 }
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
