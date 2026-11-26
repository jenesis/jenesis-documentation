#!/usr/bin/env python3
"""calls.py <maven|jenesis>: what the agents of one arm asked their build tool for, over every recorded run."""
import collections
import glob
import os
import statistics
import sys

arm = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
calls = []
for path in glob.glob(os.path.join(here, "*", "*", arm + "-*.buildtool.tsv")):
    with open(path) as file:
        for line in file:
            _, _, seconds, code, written, arguments = line.rstrip("\n").split("\t", 5)
            calls.append((path, float(seconds), int(code), int(written), arguments.split()))
runs = collections.Counter(call[0] for call in calls)
print("%d runs, %d calls, %s per run at the median" % (len(runs), len(calls), statistics.median(runs.values())))
used = collections.Counter()
for _, _, _, _, arguments in calls:
    seen = set()
    for index, argument in enumerate(arguments):
        if argument.startswith("-D"):
            seen.add(argument.split("=")[0])
        elif argument.startswith("-") or argument.startswith("+"):
            seen.add("+<module>" if argument.startswith("+") else argument)
        elif not argument.endswith(".java") and (index == 0 or arguments[index - 1] not in ("-pl", "-f")):
            seen.add("goal or selector " + argument)
    used.update(seen)
for argument, count in used.most_common(20):
    print("%4d  %3.0f%%  %s" % (count, 100 * count / len(calls), argument))
for name, chosen in (("naming tests", True), ("naming no test", False)):
    part = [call for call in calls if any(a.startswith(("-Dtest=", "-Djenesis.test.filter=")) for a in call[4]) == chosen]
    if part:
        print("%s: %d calls, %.0f s and %.0f bytes at the median, %d ended in failure" % (
            name, len(part), statistics.median(c[1] for c in part), statistics.median(c[3] for c in part),
            sum(1 for c in part if c[2])))
