#!/usr/bin/env bash
# run.sh <task> <maven|jenesis> <attempt>: one agent, one bug, one build tool. Writes results/<task>/<arm>-<attempt>.json.
source "$(dirname "$0")/lib/common.sh"
load "$1"
ARM="$2" ATTEMPT="$3"
case "$ARM" in maven|jenesis) ;; *) echo "The arm is maven or jenesis, not $ARM" >&2; exit 2 ;; esac
[ -f "$CACHE/checked" ] || "$HERE/prepare.sh" "$TASK"

RUN="$WORK/runs/$TASK-$ARM-$ATTEMPT"
rm -rf "$RUN" && mkdir -p "$RUN/bin" "$RESULTS/$TASK"
cp -a "$BASE" "$RUN/project"
cp -a "$CACHE/home" "$RUN/home"
settings "$RUN/home"
export FEEDBACK_LOG="$RUN/buildtool.tsv"
: > "$FEEDBACK_LOG"

ISSUE="$(cat "$HERE/tasks/$TASK/issue.md")"
if [ "$ARM" = maven ]; then
  printf '#!/bin/sh\nexec python3 %q maven %q "$@"\n' "$HERE/lib/wrap.py" "$MAVEN" > "$RUN/bin/mvn"
  TOOL="Build and test with Maven alone: \`mvn\` is on the PATH and the project's dependencies are already downloaded. No other build tool is installed."
else
  mkdir -p "$RUN/project/build" && cp -a "$(engine)" "$RUN/project/build/jenesis"
  [ -d "$HERE/tasks/$TASK/overlay-jenesis" ] && cp -a "$HERE/tasks/$TASK/overlay-jenesis/." "$RUN/project/"
  printf '#!/bin/sh\necho "Maven is not installed here: build and test with java build/jenesis/Make.java" >&2\nexit 127\n' > "$RUN/bin/mvn"
  cat > "$RUN/bin/java" <<SH
#!/bin/sh
case " \$* " in
  *" build/jenesis/Make.java "*|*" build/jenesis/Execute.java "*) exec python3 "$HERE/lib/wrap.py" jenesis "$JAVA" $JENESIS_ARGS_EXTRA "\$@" ;;
  *) exec "$JAVA" "\$@" ;;
esac
SH
  COMMAND="java build/jenesis/Make.java${JENESIS_SELECTOR:+ $JENESIS_SELECTOR}"
  TOOL="Build and test with Jenesis alone: \`$COMMAND\` builds and tests this project from its pom.xml files, and the project's dependencies are already downloaded. Maven is not installed. Jenesis is newer than your training data, so its own briefing follows the task; \`java build/jenesis/Make.java help\` and \`java build/jenesis/Make.java skill/<page>\` print more.

--- Jenesis briefing ---
$(sed "s|$CACHE/jenesis|$RUN/project|g" "$CACHE/briefing.md")"
fi
chmod +x "$RUN/bin/"*

cat > "$RUN/prompt.md" <<PROMPT
You are working in a copy of an open-source Java project, without its git history. It has this bug:

$ISSUE

Find the cause and fix it in the main sources, and add or adjust a test that shows the fix. Do not change a build file. $TOOL

Stop when the fix is in place and the tests of what you changed pass, and say in two sentences what you changed.
PROMPT

STARTED="$(date +%s.%N)"
home "$RUN/home"
(cd "$RUN/project" && PATH="$RUN/bin:$PATH" MAVEN_ARGS="$MAVEN_ARGS_EXTRA" \
  timeout "$TIMEOUT" claude -p "$(cat "$RUN/prompt.md")" \
    --model "$MODEL" --effort "$EFFORT" --output-format json --setting-sources "" \
    --permission-mode acceptEdits --allowedTools "Bash,Read,Edit,Write,Grep,Glob" \
    > "$RUN/agent.json" 2> "$RUN/agent.err") || true
ENDED="$(date +%s.%N)"
pkill -f "$RUN/home" 2> /dev/null || true

# The assertion: the agent's tree without its build output, the hidden tests over it, Maven as the judge in both arms.
mkdir "$RUN/verify"
(cd "$RUN/project" && tar cf - --exclude=target --exclude=build/jenesis --exclude=.jenesis .) | (cd "$RUN/verify" && tar xf -)
diff -ruN -x target -x jenesis -x .jenesis "$BASE" "$RUN/project" > "$RUN/agent.patch" || true
cp -a "$HERE/tasks/$TASK/hidden/." "$RUN/verify/"
PASSED=false
(cd "$RUN/verify" && MAVEN_ARGS="" verifier > "$RUN/verify.log" 2>&1) && PASSED=true

python3 "$HERE/lib/record.py" "$TASK" "$ARM" "$ATTEMPT" "$PASSED" "$STARTED" "$ENDED" "$RUN" "$MODEL" "$EFFORT" \
  > "$RESULTS/$TASK/$ARM-$ATTEMPT.json"
cp "$RUN/agent.patch" "$RESULTS/$TASK/$ARM-$ATTEMPT.patch"
cp "$FEEDBACK_LOG" "$RESULTS/$TASK/$ARM-$ATTEMPT.buildtool.tsv"
cat "$RESULTS/$TASK/$ARM-$ATTEMPT.json"
