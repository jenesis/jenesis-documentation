#!/usr/bin/env python3
"""stats.py: per task and tool, each variant against the baseline, with an exact two-sided Mann-Whitney p value.

    stats.py [metric ...]      metrics default to wall_seconds build_seconds build_invocations cost_usd
"""
import glob, itertools, json, os, statistics, sys

HERE = os.path.dirname(os.path.abspath(__file__))


def exact(sample, baseline):
    pooled, size = sample + baseline, len(sample)
    if len(pooled) > 16 or not sample or not baseline:
        return None
    ranks = {}
    ordered = sorted(pooled)
    for value in set(pooled):
        positions = [index + 1 for index, other in enumerate(ordered) if other == value]
        ranks[value] = sum(positions) / len(positions)
    expected = size * (len(pooled) + 1) / 2
    observed = abs(sum(ranks[value] for value in sample) - expected)
    hits = total = 0
    for chosen in itertools.combinations(range(len(pooled)), size):
        total += 1
        hits += abs(sum(ranks[pooled[index]] for index in chosen) - expected) >= observed - 1e-9
    return hits / total


def main():
    metrics = sys.argv[1:] or ["wall_seconds", "build_seconds", "build_invocations", "cost_usd"]
    cells = {}
    for path in glob.glob(os.path.join(HERE, "results", "*", "*.json")):
        record = json.load(open(path))
        tool, _, variant = os.path.basename(path).rsplit("-", 1)[0].partition("+")
        cells.setdefault((record["task"], tool), {}).setdefault(variant or "baseline", []).append(record)
    for (task, tool), variants in sorted(cells.items()):
        if len(variants) < 2:
            continue
        print(f"\n{task} {tool}")
        print(f"  {'variant':<11}{'n':>3}{'pass':>5}" + "".join(f"{metric.replace('_seconds', '').replace('build_invocations', 'calls').replace('_usd', ''):>22}" for metric in metrics))
        for variant in ["baseline"] + sorted(set(variants) - {"baseline"}):
            runs = variants[variant]
            line = f"  {variant:<11}{len(runs):>3}{sum(run['passed'] for run in runs):>5}"
            for metric in metrics:
                values = [run[metric] for run in runs]
                p = None if variant == "baseline" else exact(values, [run[metric] for run in variants.get("baseline", [])])
                line += f"{statistics.median(values):>9.4g} [{min(values):.3g}-{max(values):.3g}]".ljust(0) + (f" p={p:.3f}" if p is not None else "        ")
            print(line)


if __name__ == "__main__":
    main()
