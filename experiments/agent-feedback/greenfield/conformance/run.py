import argparse
import importlib.util
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def load(folder):
    suite = unittest.TestSuite()
    path = os.path.join(HERE, folder)
    if not os.path.isdir(path):
        return suite
    for name in sorted(os.listdir(path)):
        if name.startswith("test_") and name.endswith(".py"):
            spec = importlib.util.spec_from_file_location("%s_%s" % (folder, name[:-3]), os.path.join(path, name))
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            suite.addTests(unittest.defaultTestLoader.loadTestsFromModule(module))
    return suite


def flatten(suite):
    for t in suite:
        if isinstance(t, unittest.TestSuite):
            yield from flatten(t)
        else:
            yield t


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base")
    parser.add_argument("--only", choices=["visible", "hidden"])
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()
    os.environ["CONFORMANCE_BASE"] = args.base.rstrip("/")
    import lib
    lib.BASE = args.base.rstrip("/")
    tests = []
    for folder in ["visible", "hidden"]:
        if args.only in (None, folder):
            tests.extend(flatten(load(folder)))
    failed = {}
    for test in tests:
        result = unittest.TestResult()
        test.run(result)
        problems = result.failures + result.errors
        if problems:
            number = getattr(getattr(test, test._testMethodName), "rule", "R?")
            failed.setdefault(number, []).append((test._testMethodName, problems[0][1].strip().splitlines()[-1]))

    def key(r):
        return [int(x) if x.isdigit() else 0 for x in r[1:].split(".")]
    for number in sorted(failed, key=key):
        names = failed[number]
        print("FAILED %s: %s" % (number, ", ".join(n for n, _ in names)))
        if args.verbose:
            for n, why in names:
                print("    %s: %s" % (n, why[:400]))
    passed = len(tests) - sum(len(v) for v in failed.values())
    print("PASSED %d/%d" % (passed, len(tests)))
    return 0 if passed == len(tests) else 1


if __name__ == "__main__":
    sys.exit(main())
