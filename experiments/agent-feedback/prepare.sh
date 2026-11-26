#!/usr/bin/env bash
# prepare.sh <task>: clones the project at the commit before the fix, drops its history, warms the dependency
# caches of both tools and checks the task against its reference fix. Run once per task; it does nothing twice.
source "$(dirname "$0")/lib/common.sh"
load "$1"

if [ ! -d "$BASE" ]; then
  mkdir -p "$WORK/base"
  git clone --quiet "$REPO" "$BASE.clone"
  git -C "$BASE.clone" checkout --quiet "$COMMIT"
  rm -rf "$BASE.clone/.git"
  for path in $REMOVE; do rm -rf "${BASE:?}.clone/$path"; done
  [ -x "$HERE/tasks/$TASK/prepare.sh" ] && (cd "$BASE.clone" && "$HERE/tasks/$TASK/prepare.sh")
  mv "$BASE.clone" "$BASE"
fi

if [ ! -f "$CACHE/checked" ]; then
  rm -rf "$CACHE" && mkdir -p "$CACHE/home"
  settings "$CACHE/home"
  home "$CACHE/home"
  export MAVEN_ARGS="$MAVEN_ARGS_EXTRA"

  # Maven: the whole project's tests once, as the Jenesis arm's warm-up builds the whole project, which resolves
  # every plugin and dependency the verifier and an agent need.
  cp -a "$BASE" "$CACHE/maven"
  (cd "$CACHE/maven" && "$MAVEN" -B test > "$CACHE/maven.log" 2>&1) || true

  # The hidden tests fail on the commit before the fix and pass with the reference fix.
  cp -r "$HERE/tasks/$TASK/hidden/." "$CACHE/maven/"
  (cd "$HERE/tasks/$TASK/hidden" && find . -type f) | (cd "$CACHE/maven" && xargs touch)
  if (cd "$CACHE/maven" && verifier > "$CACHE/before.log" 2>&1); then
    echo "The hidden tests of $TASK pass without the fix: see $CACHE/before.log" >&2; exit 1
  fi
  (cd "$CACHE/maven" && patch -s -p1 < "$HERE/tasks/$TASK/reference.patch")
  if ! (cd "$CACHE/maven" && verifier > "$CACHE/after.log" 2>&1); then
    echo "The hidden tests of $TASK fail with the reference fix: see $CACHE/after.log" >&2; exit 1
  fi

  # Jenesis: one build of the project as the Jenesis arm holds it, and the briefing that arm is given.
  cp -a "$BASE" "$CACHE/jenesis"
  mkdir -p "$CACHE/jenesis/build" && cp -a "$(engine)" "$CACHE/jenesis/build/jenesis"
  [ -d "$HERE/tasks/$TASK/overlay-jenesis" ] && cp -a "$HERE/tasks/$TASK/overlay-jenesis/." "$CACHE/jenesis/"
  # shellcheck disable=SC2086
  (cd "$CACHE/jenesis" && "$JAVA" $JENESIS_ARGS_EXTRA build/jenesis/Make.java $JENESIS_SELECTOR > "$CACHE/jenesis.log" 2>&1) || true
  (cd "$CACHE/jenesis" && "$JAVA" -Djenesis.make.mode=compiled build/jenesis/Make.java skill/start 2> /dev/null | sed -e 's/\x1b\[[0-9;]*m//g' -e '/^\[[A-Z]* *\]/d' > "$CACHE/briefing.md")
  pkill -f "$CACHE/home" 2> /dev/null || true
  rm -rf "$CACHE/maven" "$CACHE/jenesis"
  touch "$CACHE/checked"
fi
echo "Prepared $TASK: $BASE, caches under $CACHE"
