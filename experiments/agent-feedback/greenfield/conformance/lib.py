import itertools
import json
import os
import unittest
import urllib.error
import urllib.request

BASE = os.environ.get("CONFORMANCE_BASE", "http://localhost:8080")
NOW = "2026-03-20T12:00:00Z"
ENTERED = "2026-03-17T10:00:00Z"
_MISSING = object()
_marks = itertools.count(1)


def rule(number):
    def mark(fn):
        fn.rule = number
        return fn
    return mark


class Resp:
    def __init__(self, status, headers, data):
        self.status = status
        self.headers = {k.lower(): v for k, v in headers.items()}
        self.text = data.decode("utf-8", errors="replace")
        try:
            self.body = json.loads(self.text) if self.text else None
        except ValueError:
            self.body = None

    def header(self, name):
        return self.headers.get(name.lower())

    def __repr__(self):
        return "<%d %s>" % (self.status, self.text[:300])


def call(method, path, body=_MISSING, headers=None, raw=None):
    data = raw if raw is not None else (None if body is _MISSING else json.dumps(body).encode("utf-8"))
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if data is not None:
        req.add_header("Content-Type", "application/x-ndjson" if raw is not None else "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return Resp(r.status, dict(r.headers), r.read())
    except urllib.error.HTTPError as e:
        return Resp(e.code, dict(e.headers), e.read())


class Case(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        r = call("POST", "/admin/reset", {})
        self.assertEqual(r.status, 204, "reset must answer 204: %r" % r)
        self.clock(NOW)
        for code, name, tier in [("KV-209", "Kestle Haulage", "ordinary"), ("AB-102", "Ashby Contract Carriers",
                                 "contract"), ("MX-445", "Mere Heritage Trust", "heritage")]:
            self.ok(call("POST", "/operators", {"code": code, "name": name, "tier": tier}), 201)

    def clock(self, now):
        self.ok(call("PUT", "/admin/clock", {"now": now}), 200)

    def ok(self, resp, status):
        self.assertEqual(resp.status, status, "expected %d, got %r" % (status, resp))
        return resp.body

    def error(self, resp, status, code, field=_MISSING):
        self.assertEqual(resp.status, status, "expected %d %s, got %r" % (status, code, resp))
        self.assertIsInstance(resp.body, dict, "error body must be JSON: %r" % resp)
        err = resp.body.get("error") or {}
        self.assertEqual(err.get("code"), code, "wrong error code: %r" % resp)
        if field is not _MISSING:
            self.assertIn("field", err, "error must carry field: %r" % resp)
            self.assertEqual(err.get("field"), field, "wrong error field: %r" % resp)

    def body(self, **overrides):
        b = {"operator": "KV-209", "vesselMark": "V%05d" % next(_marks), "vesselClass": "NB", "lengthDm": 180,
             "ladenTonnes": "12.00", "cargo": "GEN", "locks": ["K1", "K2", "K3"], "enteredAt": ENTERED}
        for k, v in overrides.items():
            if v is _MISSING:
                b.pop(k, None)
            else:
                b[k] = v
        return b

    def spec(self, **overrides):
        b = self.body(**overrides)
        b.pop("operator")
        b.pop("vesselMark")
        b.setdefault("ref", "q")
        b.setdefault("tier", "ordinary")
        return b

    def passage(self, **overrides):
        return self.ok(call("POST", "/passages", self.body(**overrides)), 201)

    def claim(self, pid, lock="K2", minutes=90, reason="MECHANICAL", headers=None):
        return self.ok(call("POST", "/claims", {"passageId": pid, "lock": lock, "delayMinutes": minutes,
                                                "reason": reason}, headers), 201)

    def move(self, cid, version, action, actor="clerk.ann", **fields):
        h = {"If-Match": '"%d"' % version}
        if actor is not None:
            h["X-Actor"] = actor
        return call("POST", "/claims/%s/transitions" % cid, dict(fields, action=action), h)

    def moved(self, cid, version, action, actor="clerk.ann", **fields):
        return self.ok(self.move(cid, version, action, actor, **fields), 200)

    def quote(self, *items):
        return self.ok(call("POST", "/tariff/quotes", {"items": list(items)}), 200)

    def fees(self, toll):
        return [x["fee"] for x in toll["lockFees"]]


MISSING = _MISSING
