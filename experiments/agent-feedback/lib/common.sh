# Sourced by prepare.sh and run.sh. Settings, as environment variables:
#   WORK             where clones, caches and runs are kept (default: ./work, which git ignores)
#   RESULTS          where a run's record is written (default: ./results)
#   MODEL, EFFORT    the model and reasoning effort of the agent (default: claude-opus-5-5, medium)
#   TIMEOUT          seconds after which an agent that has not stopped is ended (default: 3600)
#   JENESIS_REF      the Jenesis commit, tag or branch the Jenesis arm vendors (default: main)
#   JENESIS_SOURCES  a checkout of jenesis/jenesis whose sources/build/jenesis is copied in place of JENESIS_REF
#   MAVEN            the Maven the Maven arm and the verifier run (default: the mvn on the PATH)
#   MAVEN_MIRROR     a mirror of Maven Central for both tools (default: none)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$HERE/work}"
RESULTS="${RESULTS:-$HERE/results}"
MODEL="${MODEL:-claude-opus-5-5}"
EFFORT="${EFFORT:-medium}"
TIMEOUT="${TIMEOUT:-3600}"
JENESIS_REF="${JENESIS_REF:-main}"
MAVEN="${MAVEN:-$(command -v mvn)}"
JAVA="$(command -v java)"

load() {
  TASK="$1"
  [ -f "$HERE/tasks/$TASK/task.env" ] || { echo "No task $TASK under $HERE/tasks" >&2; exit 2; }
  MODULES="" TESTS="" MAVEN_ARGS_EXTRA="" JENESIS_ARGS_EXTRA="" JENESIS_SELECTOR="" REMOVE=""
  # shellcheck disable=SC1090
  source "$HERE/tasks/$TASK/task.env"
  BASE="$WORK/base/$TASK"
  CACHE="$WORK/cache/$TASK"
}

# A JVM takes its home from the user database and not from HOME, so both are named: every cache of both tools
# then lies in the folder given.
TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-}"
home() {
  export HOME="$1" JAVA_TOOL_OPTIONS="$TOOL_OPTIONS -Duser.home=$1"
}

settings() {
  mkdir -p "$1/.m2"
  if [ -n "${MAVEN_MIRROR:-}" ]; then
    cat > "$1/.m2/settings.xml" <<XML
<settings><mirrors><mirror><id>mirror</id><mirrorOf>central</mirrorOf><url>$MAVEN_MIRROR</url></mirror></mirrors></settings>
XML
    export MAVEN_REPOSITORY_URI="$MAVEN_MIRROR,https://repo1.maven.org/maven2/"
  fi
}

# The verifier: Maven over the task's modules and hidden tests, in the folder it is run in.
verifier() {
  # shellcheck disable=SC2086
  "$MAVEN" -o -B $MAVEN_ARGS_EXTRA -pl "$MODULES" -am test "-Dtest=$TESTS" -Dsurefire.failIfNoSpecifiedTests=false
}

engine() {
  if [ -n "${JENESIS_SOURCES:-}" ]; then
    echo "$JENESIS_SOURCES/sources/build/jenesis"
    return
  fi
  if [ ! -d "$WORK/jenesis" ]; then
    git clone --quiet https://github.com/jenesis/jenesis "$WORK/jenesis"
    git -C "$WORK/jenesis" checkout --quiet "$JENESIS_REF"
  fi
  echo "$WORK/jenesis/sources/build/jenesis"
}
