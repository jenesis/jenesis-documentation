#!/usr/bin/env python3
"""Runs a build tool, passes its output through and appends one line per invocation to $FEEDBACK_LOG."""
import os
import subprocess
import sys
import threading
import time

kind, real, arguments = sys.argv[1], sys.argv[2], sys.argv[3:]
written = [0]


def forward(source, target):
    for chunk in iter(lambda: source.read1(65536), b""):
        written[0] += len(chunk)
        target.write(chunk)
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
