#!/usr/bin/env bash
# run.sh <task> <maven|jenesis> <attempt>: one agent, one bug, one build tool. Writes results/<task>/<arm>-<attempt>.json.
# VARIANT changes one property of a run and leaves the rest as it is; its record is <arm>+<variant>-<attempt>.json:
#   nodaemon    Jenesis without its daemon, each call a JVM of its own running the compiled engine
#   rebuild     Jenesis without its incremental build, every call building everything again
#   verbose     Jenesis printing a line per step and per test class, whatever the agent asks for
#   nobriefing  Jenesis without its briefing in the prompt: AGENTS.md names the command that prints it
#   briefed     Maven with a paragraph in AGENTS.md on building one module and running one test class
#   mvnd        Maven through its daemon
#   parallel    Maven building the modules of a reactor side by side (-T 1C)
#   cache       Maven with its build cache extension, which restores a module whose inputs did not change
#   longshell   either tool, with a shell call allowed to run for half an hour in the foreground
#   sonnet      either tool, with claude-sonnet-5-5 as the agent
#   low         either tool, with the agent at low effort
source "$(dirname "$0")/lib/common.sh"
load "$1"
ARM="$2" ATTEMPT="$3"
case "$ARM" in maven|jenesis) ;; *) echo "The arm is maven or jenesis, not $ARM" >&2; exit 2 ;; esac
VARIANT="${VARIANT:-}"
LABEL="$ARM${VARIANT:++$VARIANT}"
FILTER=""
case "$ARM+$VARIANT" in
  *+) ;;
  jenesis+nodaemon) JENESIS_ARGS_EXTRA="$JENESIS_ARGS_EXTRA -Djenesis.make.mode=compiled" ;;
  jenesis+rebuild) JENESIS_ARGS_EXTRA="$JENESIS_ARGS_EXTRA -Djenesis.executor.rebuild=true" ;;
  jenesis+verbose) FILTER='for a do shift; case "$a" in -Djenesis.print.progress=*|-Djenesis.test.summary*) ;; *) set -- "$@" "$a" ;; esac; done' ;;
  jenesis+nobriefing|maven+briefed|maven+cache) ;;
  maven+mvnd) MAVEN="${MVND:?The variant mvnd needs MVND, the path of the mvnd to run}" ;;
  maven+parallel) MAVEN_ARGS_EXTRA="$MAVEN_ARGS_EXTRA -T 1C" ;;
  *+longshell) export BASH_DEFAULT_TIMEOUT_MS=1800000 BASH_MAX_TIMEOUT_MS=1800000 ;;
  *+sonnet) MODEL=claude-sonnet-5-5 ;;
  *+low) EFFORT=low ;;
  *) echo "The $ARM arm has no variant $VARIANT" >&2; exit 2 ;;
esac
JUDGE="$(command -v mvn)"
[ -f "$CACHE/checked" ] || "$HERE/prepare.sh" "$TASK"

# A folder and a home of its own per run, so that no run reads what another one built or cached.
RUN="$WORK/runs/$TASK-$LABEL-$ATTEMPT"
rm -rf "$RUN" && mkdir -p "$RUN/bin" "$RESULTS/$TASK"
cp -a "$BASE" "$RUN/project"
cp -a "$CACHE/home" "$RUN/home"
settings "$RUN/home"
export FEEDBACK_LOG="$RUN/buildtool.tsv"
: > "$FEEDBACK_LOG"

ISSUE="$(cat "$HERE/tasks/$TASK/issue.md")"
BRIEFING=""
# The arms differ in the tool on the path and in the AGENTS.md that names it, and in nothing else: the project's
# own instructions for agents are removed, as they would advise one arm only. Each tool is reached through a
# wrapper that times its calls, and the Jenesis arm's mvn refuses, so that a run measures one tool.
if [ "$ARM" = maven ]; then
  printf '#!/bin/sh\nexec python3 %q maven %q "$@"\n' "$HERE/lib/wrap.py" "$MAVEN" > "$RUN/bin/mvn"
  cp "$HERE/lib/agents-maven.md" "$RUN/project/AGENTS.md"
  [ "$VARIANT" = briefed ] && cat "$HERE/lib/agents-maven-briefed.md" >> "$RUN/project/AGENTS.md"
  [ "$VARIANT" = cache ] && mkdir -p "$RUN/project/.mvn" && cp "$HERE/lib/extensions.xml" "$RUN/project/.mvn/extensions.xml"
else
  mkdir -p "$RUN/project/build" && cp -a "$(engine)" "$RUN/project/build/jenesis"
  [ -d "$HERE/tasks/$TASK/overlay-jenesis" ] && cp -a "$HERE/tasks/$TASK/overlay-jenesis/." "$RUN/project/"
  printf '#!/bin/sh\necho "Maven is not installed here: AGENTS.md says how this project is built" >&2\nexit 127\n' > "$RUN/bin/mvn"
  cat > "$RUN/bin/java" <<SH
#!/bin/sh
$FILTER
case " \$* " in
  *" build/jenesis/Make.java "*|*" build/jenesis/Execute.java "*) exec python3 "$HERE/lib/wrap.py" jenesis "$JAVA" $JENESIS_ARGS_EXTRA "\$@" ;;
  *) exec "$JAVA" "\$@" ;;
esac
SH
  cp "$HERE/lib/agents-jenesis.md" "$RUN/project/AGENTS.md"
  # The model knows Maven from its training and Jenesis from nowhere. The briefing Jenesis prints for an agent is
  # therefore part of what this arm is told before the clock starts, as the training is for the other arm.
  [ "$VARIANT" = nobriefing ] || BRIEFING="
This is what \`java build/jenesis/Make.java skill/start\` prints, the tool's briefing for a coding agent:

$(sed "s|$CACHE/jenesis|$RUN/project|g" "$CACHE/briefing.md")
"
fi
chmod +x "$RUN/bin/"*
# Claude Code reads CLAUDE.md, which hands on to the file any agent reads.
printf '@AGENTS.md\n' > "$RUN/project/CLAUDE.md"

cat > "$RUN/prompt.md" <<PROMPT
You are working in a copy of an open-source Java project, without its git history. It has this bug:

$ISSUE

Find the cause and fix it in the main sources, and add or adjust a test that shows the fix. AGENTS.md in the project root names the tool this project is built and tested with; build and test with that tool alone.
$BRIEFING
Before you stop, run once every test of every module your change reaches - the modules you changed and the modules that depend on them - and see them pass. Then say in two sentences what you changed.
PROMPT

# The agent sees no settings or instructions of the user: what it knows of the task is the prompt.
STARTED="$(date +%s.%N)"
home "$RUN/home"
(cd "$RUN/project" && PATH="$RUN/bin:$PATH" MAVEN_ARGS="$MAVEN_ARGS_EXTRA" \
  timeout "$TIMEOUT" claude -p "$(cat "$RUN/prompt.md")" \
    --model "$MODEL" --effort "$EFFORT" --output-format json --setting-sources "" \
    --permission-mode acceptEdits --allowedTools "Bash,Read,Edit,Write,Grep,Glob" \
    > "$RUN/agent.json" 2> "$RUN/agent.err") || true
ENDED="$(date +%s.%N)"
pkill -f "$RUN/home" 2> /dev/null || true

# An agent that was refused, as by a usage limit, did no work: the run leaves no record and can be started again.
if ! python3 - "$RUN/agent.json" <<'PY'
import json, sys
try:
    agent = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    sys.exit(1)
refused = agent.get("is_error") or "usage limit" in str(agent.get("result", "")).lower() or "hit your" in str(agent.get("result", "")).lower()
sys.exit(1 if refused or not agent.get("num_turns") else 0)
PY
then
  echo "The agent of $TASK $LABEL $ATTEMPT did not run: see $RUN/agent.json and $RUN/agent.err" >&2
  exit 3
fi

# The assertion: the agent's tree without its build output, the hidden tests over it, Maven as the judge in both arms.
mkdir "$RUN/verify"
(cd "$RUN/project" && tar cf - --exclude=target --exclude=build/jenesis --exclude=.jenesis --exclude=./AGENTS.md --exclude=./CLAUDE.md .) | (cd "$RUN/verify" && tar xf -)
diff -ruN -x target -x jenesis -x .jenesis -x AGENTS.md -x CLAUDE.md -x extensions.xml "$BASE" "$RUN/project" > "$RUN/agent.patch" || true
# What the Jenesis arm was handed beside the project is no part of the project that is judged.
if [ -d "$HERE/tasks/$TASK/overlay-jenesis" ]; then
  (cd "$HERE/tasks/$TASK/overlay-jenesis" && find . -type f) | (cd "$RUN/verify" && xargs rm -f)
fi
rm -f "$RUN/verify/.mvn/extensions.xml"
cp -r "$HERE/tasks/$TASK/hidden/." "$RUN/verify/"
PASSED=false
(cd "$RUN/verify" && MAVEN="$JUDGE" MAVEN_ARGS="" verifier > "$RUN/verify.log" 2>&1) && PASSED=true

python3 "$HERE/lib/record.py" "$TASK" "$LABEL" "$ATTEMPT" "$PASSED" "$STARTED" "$ENDED" "$RUN" "$MODEL" "$EFFORT" \
  > "$RESULTS/$TASK/$LABEL-$ATTEMPT.json"
cp "$RUN/agent.patch" "$RESULTS/$TASK/$LABEL-$ATTEMPT.patch"
cp "$FEEDBACK_LOG" "$RESULTS/$TASK/$LABEL-$ATTEMPT.buildtool.tsv"
cat "$RESULTS/$TASK/$LABEL-$ATTEMPT.json"
