import collections, json, sys
def outputs(path):
    dec, text, i = json.JSONDecoder(), open(path).read(), 0
    res = collections.defaultdict(set)
    while True:
        while i < len(text) and text[i].isspace(): i += 1
        if i >= len(text): return res
        spawn, i = dec.raw_decode(text, i)
        for o in spawn.get("actualOutputs", []):
            res[o["path"]].add(o["digest"]["hash"])
a, b = outputs(sys.argv[1]), outputs(sys.argv[2])
common = set(a) & set(b)
only = sorted(set(a) ^ set(b))
diff = sorted(p for p in common if a[p] != b[p])
print(f"{len(common)} output paths compared, {len(diff)} differ, {len(only)} produced by only one build")
for p in only: print("  ONLY ONE:", p)
for p in diff: print("  DIFFERS:", p)
sys.exit(1 if diff or only else 0)
