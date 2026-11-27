#!/usr/bin/env python3
"""Runs a build tool, passes its output through and appends one line per invocation to $FEEDBACK_LOG."""
import os
import subprocess
import sys
import threading
import time

kind, real, arguments = sys.argv[1], sys.argv[2], sys.argv[3:]
written = [0]


# The harness gives each run a home of its own through JAVA_TOOL_OPTIONS, which every JVM announces with a line
# that no project of the agent's own would print. It is left out in both arms.
def forward(source, target):
    for line in iter(source.readline, b""):
        if line.startswith(b"Picked up JAVA_TOOL_OPTIONS:"):
            continue
        written[0] += len(line)
        target.write(line)
        target.flush()


started = time.time()
process = subprocess.Popen([real, *arguments], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
threads = [
    threading.Thread(target=forward, args=(process.stdout, sys.stdout.buffer)),
    threading.Thread(target=forward, args=(process.stderr, sys.stderr.buffer)),
]
for thread in threads:
    thread.start()
code = process.wait()
for thread in threads:
    thread.join()
with open(os.environ["FEEDBACK_LOG"], "a") as log:
    log.write("\t".join([
        kind,
        "%.3f" % started,
        "%.3f" % (time.time() - started),
        str(code),
        str(written[0]),
        " ".join(arguments).replace("\t", " ").replace("\n", " "),
    ]) + "\n")
sys.exit(code)
