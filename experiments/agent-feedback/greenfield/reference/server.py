import json
import os
import re
import sys
import threading
from datetime import datetime, timedelta, timezone
from decimal import Decimal as D, ROUND_HALF_EVEN, ROUND_HALF_UP, ROUND_FLOOR
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlsplit, parse_qsl

INITIAL_CLOCK = datetime(2026, 1, 1, tzinfo=timezone.utc)
LOCKS = {
    "K1": ("broad", D("1.85")), "K2": ("broad", D("2.40")), "K3": ("broad", D("0.95")),
    "K4": ("broad", D("3.10")), "K5": ("broad", D("2.05")), "K6": ("broad", D("1.20")),
    "W1": ("narrow", D("1.65")), "W2": ("narrow", D("2.75")), "W3": ("narrow", D("0.80")),
}
LOCK_ORDER = list(LOCKS)
PAIRS = {frozenset(p) for p in [("K1", "K2"), ("K2", "K3"), ("K3", "K4"), ("K4", "K5"), ("K5", "K6"),
                                 ("K3", "W1"), ("W1", "W2"), ("W2", "W3")]}
BASE = {"broad": D("6.40"), "narrow": D("4.15")}
LIFT_RATE = {"NB": D("0.90"), "WB": D("1.35"), "DB": D("1.60"), "TS": D("2.10")}
CARGO = {"NONE": D("0"), "GEN": D("0.025"), "AGG": D("0.04"), "LIV": D("0.075"), "HAZ-B": D("0.13"),
         "HAZ-A": D("0.22")}
TIERS = ["ordinary", "contract", "heritage"]
REASONS = ["MECHANICAL", "WATER_LEVEL", "STAFFING", "OBSTRUCTION"]
STATES = ["LODGED", "ASSESSED", "APPROVED", "SETTLED", "REJECTED", "WITHDRAWN"]
ACTIONS = {"assess": (["LODGED"], "ASSESSED"), "reject": (["ASSESSED"], "REJECTED"),
           "approve": (["ASSESSED"], "APPROVED"), "settle": (["APPROVED"], "SETTLED"),
           "withdraw": (["LODGED", "ASSESSED"], "WITHDRAWN"), "reopen": (["REJECTED"], "LODGED")}
OPERATOR_RE = re.compile(r"[A-Z]{2}-[0-9]{3}")
MARK_RE = re.compile(r"[A-Z0-9]{3,10}")
TONNES_RE = re.compile(r"[0-9]{1,3}(\.[0-9]{1,2})?")
TS_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")
KEY_RE = re.compile(r"[A-Za-z0-9-]{8,64}")
ACTOR_RE = re.compile(r"[a-z][a-z0-9.]{1,31}")
PSG_RE = re.compile(r"PSG-[0-9]{6}")
MONEY_RE = re.compile(r"[0-9]+\.[0-9]{2}")
MIN_TOTAL_RE = re.compile(r"[0-9]+(\.[0-9]{1,2})?")
DIGITS_RE = re.compile(r"[0-9]+")
MONTH_RE = re.compile(r"([0-9]{4})-([0-9]{2})")
ETAG_RE = re.compile(r'"([0-9]+)"')


class ApiError(Exception):
    def __init__(self, status, code, field=None):
        super().__init__(code)
        self.status, self.code, self.field = status, code, field


def q4(x):
    return x.quantize(D("0.0001"), ROUND_HALF_EVEN)


def u2(x):
    return x.quantize(D("0.01"), ROUND_HALF_UP)


def s4(x):
    return str(q4(x))


def s2(x):
    return str(x.quantize(D("0.01")))


def parse_ts(v):
    if not TS_RE.fullmatch(v):
        return None
    try:
        return datetime.strptime(v, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def fmt_ts(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def required(obj, name):
    if name not in obj or obj[name] is None:
        raise ApiError(400, "FIELD_REQUIRED", name)
    return obj[name]


def string(obj, name):
    v = required(obj, name)
    if not isinstance(v, str):
        raise ApiError(400, "FIELD_TYPE", name)
    return v


def integer(obj, name, lo, hi):
    v = required(obj, name)
    if not is_int(v):
        raise ApiError(400, "FIELD_TYPE", name)
    if v < lo or v > hi:
        raise ApiError(400, "FIELD_FORMAT", name)
    return v


def enum(obj, name, values):
    v = string(obj, name)
    if v not in values:
        raise ApiError(400, "FIELD_FORMAT", name)
    return v


def fmt(cond, name):
    if not cond:
        raise ApiError(400, "FIELD_FORMAT", name)


def validate_spec_fields(o):
    spec = {"vesselClass": enum(o, "vesselClass", LIFT_RATE), "lengthDm": integer(o, "lengthDm", 40, 450)}
    t = string(o, "ladenTonnes")
    fmt(TONNES_RE.fullmatch(t) and D(t) <= 400, "ladenTonnes")
    spec["ladenTonnes"] = D(t)
    spec["cargo"] = enum(o, "cargo", CARGO)
    locks = required(o, "locks")
    if not isinstance(locks, list) or not all(isinstance(x, str) for x in locks):
        raise ApiError(400, "FIELD_TYPE", "locks")
    fmt(1 <= len(locks) <= 12 and all(x in LOCKS for x in locks), "locks")
    spec["locks"] = locks
    e = string(o, "enteredAt")
    ts = parse_ts(e)
    fmt(ts is not None, "enteredAt")
    spec["enteredAt"], spec["enteredAtTs"] = e, ts
    return spec


def check_route(s):
    locks = s["locks"]
    if any(frozenset((a, b)) not in PAIRS for a, b in zip(locks, locks[1:])) or \
            any(locks.count(x) > 2 for x in locks):
        raise ApiError(422, "LOCK_SEQUENCE_INVALID", "locks")
    if any(LOCKS[x][0] == "narrow" for x in locks) and (s["vesselClass"] != "NB" or s["lengthDm"] > 220):
        raise ApiError(422, "GAUGE_EXCEEDED", "locks")
    if s["cargo"] == "HAZ-A" and any(LOCKS[x][1] > D("3.00") for x in locks):
        raise ApiError(422, "HAZARD_ROUTE", "locks")
    if (s["cargo"] == "NONE") != (s["ladenTonnes"] == 0):
        raise ApiError(422, "CARGO_MISMATCH", "cargo")


def compute_toll(s, tier):
    cls, length = s["vesselClass"], s["lengthDm"]
    factor = D("1.00") if length <= 210 else D("1.15") if length <= 300 else D("1.32")
    seen, fees = set(), []
    for code in s["locks"]:
        chamber, lift = LOCKS[code]
        repeat = D("0.50") if code in seen else D("1.00")
        seen.add(code)
        fees.append((code, q4((BASE[chamber] + lift * LIFT_RATE[cls]) * factor * repeat)))
    total_fees = sum((f for _, f in fees), D("0"))
    weight = q4(max(D("0"), s["ladenTonnes"] - 30) * D("0.0725") * len(fees))
    cargo = q4((total_fees + weight) * CARGO[s["cargo"]])
    p1 = total_fees + weight + cargo
    ts = s["enteredAtTs"]
    night, weekend = ts.hour >= 22 or ts.hour <= 5, ts.weekday() >= 5
    b = D("0.2508") if night and weekend else D("0.18") if night else D("0.06") if weekend else D("0")
    band = q4(p1 * b)
    p2 = p1 + band
    d = D("0.09") if tier == "contract" else D("0.40") if tier == "heritage" and cls == "NB" else D("0")
    disc = q4(p2 * d)
    total = u2(p2 - disc)
    minimum = total < D("7.50")
    if minimum:
        total = D("7.50")
    return {"lockFees": [{"lock": c, "fee": s4(f)} for c, f in fees], "lockFeeTotal": s4(total_fees),
            "weightCharge": s4(weight), "cargoSurcharge": s4(cargo), "bandSurcharge": s4(band),
            "tierDiscount": s4(disc), "total": s2(total), "minimumApplied": minimum}


def rebate(passage, lock, minutes, reason):
    fee = next(D(x["fee"]) for x in passage["toll"]["lockFees"] if x["lock"] == lock)
    if minutes < 45:
        r = D("0")
    elif minutes < 120:
        r = fee * D("0.25")
    elif minutes < 360:
        r = fee * D("0.60")
    else:
        r = fee + D("0.35") * ((minutes - 360) // 30)
    if reason == "WATER_LEVEL":
        r = r * D("0.5")
    r = min(r, D(passage["toll"]["total"]) * D("0.40"))
    return s2(u2(r))


class Service:
    def __init__(self):
        self.mutex = threading.Lock()
        self.reset()

    def reset(self):
        self.clock = INITIAL_CLOCK
        self.operators, self.passages, self.passage_list = {}, {}, []
        self.marks, self.claims, self.audit, self.idem = set(), {}, {}, {}

    def now(self):
        return fmt_ts(self.clock)

    def validate_passage(self, o, extra_marks=()):
        op = string(o, "operator")
        fmt(OPERATOR_RE.fullmatch(op), "operator")
        mark = string(o, "vesselMark")
        fmt(MARK_RE.fullmatch(mark), "vesselMark")
        s = validate_spec_fields(o)
        if op not in self.operators:
            raise ApiError(422, "UNKNOWN_OPERATOR", "operator")
        check_route(s)
        if s["enteredAtTs"] > self.clock:
            raise ApiError(422, "TIME_IN_FUTURE", "enteredAt")
        if s["enteredAtTs"] < self.clock - timedelta(days=30):
            raise ApiError(422, "STALE_DECLARATION", "enteredAt")
        key = (mark, s["enteredAt"])
        if key in self.marks or key in extra_marks:
            raise ApiError(409, "DUPLICATE_PASSAGE", "vesselMark")
        s["operator"], s["vesselMark"] = op, mark
        return s

    def build_passage(self, s, seq):
        tier = self.operators[s["operator"]]["tier"]
        return {"id": "PSG-%06d" % seq, "operator": s["operator"], "tier": tier, "vesselMark": s["vesselMark"],
                "vesselClass": s["vesselClass"], "lengthDm": s["lengthDm"], "ladenTonnes": s2(s["ladenTonnes"]),
                "cargo": s["cargo"], "locks": list(s["locks"]), "enteredAt": s["enteredAt"],
                "recordedAt": self.now(), "toll": compute_toll(s, tier)}

    def store_passage(self, p):
        self.passages[p["id"]] = p
        self.passage_list.append(p)
        self.marks.add((p["vesselMark"], p["enteredAt"]))

    def idempotent(self, scope, key, body, create):
        if key is not None:
            entry = self.idem.get((scope, key))
            if entry and self.clock < entry["at"] + timedelta(hours=24):
                if entry["body"] == body:
                    return entry["status"], entry["response"], dict(entry["headers"], **{"Idempotent-Replay": "true"})
                raise ApiError(409, "IDEMPOTENCY_CONFLICT", "Idempotency-Key")
        status, response, headers = create()
        if key is not None:
            self.idem[(scope, key)] = {"body": body, "status": status, "response": json.loads(json.dumps(response)),
                                       "headers": headers, "at": self.clock}
        return status, response, headers

    def live_claim_exists(self, passage_id, lock, exclude=None):
        return any(c["passageId"] == passage_id and c["lock"] == lock and c["state"] not in ("REJECTED", "WITHDRAWN")
                   and c["id"] != exclude for c in self.claims.values())

    def add_audit(self, claim, actor, action, before, note=None):
        entries = self.audit.setdefault(claim["id"], [])
        entries.append({"seq": len(entries) + 1, "at": self.now(), "actor": actor, "action": action,
                        "fromState": before, "toState": claim["state"], "version": claim["version"], "note": note})

    # endpoints

    def put_clock(self, req):
        o = req.json_object()
        v = string(o, "now")
        ts = parse_ts(v)
        fmt(ts is not None, "now")
        self.clock = ts
        return 200, {"now": v}

    def post_operator(self, req):
        o = req.json_object()
        code = string(o, "code")
        fmt(OPERATOR_RE.fullmatch(code), "code")
        l1, l2, d1, d2, d3 = ord(code[0]) - 64, ord(code[1]) - 64, int(code[3]), int(code[4]), int(code[5])
        if (3 * l1 + l2 + 7 * d1 + d2) % 10 != d3:
            raise ApiError(400, "CHECK_DIGIT", "code")
        name = string(o, "name").strip(" ")
        fmt(1 <= len(name) <= 60, "name")
        tier = enum(o, "tier", TIERS)
        if code in self.operators:
            raise ApiError(409, "DUPLICATE_OPERATOR", "code")
        self.operators[code] = {"code": code, "name": name, "tier": tier, "registeredAt": self.now()}
        return 201, self.operators[code]

    def get_operator(self, req, code):
        if code not in self.operators:
            raise ApiError(404, "NOT_FOUND")
        return 200, self.operators[code]

    def post_quotes(self, req):
        o = req.json_object()
        items = required(o, "items")
        if not isinstance(items, list):
            raise ApiError(400, "FIELD_TYPE", "items")
        if len(items) > 5000:
            raise ApiError(413, "BATCH_TOO_LARGE", "items")
        results, grand, ok = [], D("0"), 0
        for item in items:
            ref = None
            try:
                if not isinstance(item, dict):
                    raise ApiError(400, "FIELD_TYPE", None)
                r = item.get("ref")
                if isinstance(r, str) and 1 <= len(r) <= 40:
                    ref = r
                r = string(item, "ref")
                fmt(1 <= len(r) <= 40, "ref")
                tier = enum(item, "tier", TIERS)
                s = validate_spec_fields(item)
                check_route(s)
                toll = compute_toll(s, tier)
                grand += D(toll["total"])
                ok += 1
                results.append({"ref": ref, "toll": toll})
            except ApiError as e:
                results.append({"ref": ref, "error": {"code": e.code, "field": e.field}})
        return 200, {"count": len(items), "quoted": ok, "failed": len(items) - ok, "grandTotal": s2(grand),
                     "results": results}

    def post_passage(self, req):
        key = req.idempotency_key()
        o = req.json_object()

        def create():
            s = self.validate_passage(o)
            p = self.build_passage(s, len(self.passage_list) + 1)
            self.store_passage(p)
            return 201, p, {}
        return self.idempotent("passages", key, o, create)

    def get_passage(self, req, pid):
        if pid not in self.passages:
            raise ApiError(404, "NOT_FOUND")
        return 200, self.passages[pid]

    def list_passages(self, req):
        q = req.query
        def param(name, ok):
            if name not in q:
                return None
            v = q[name]
            if not ok(v):
                raise ApiError(400, "INVALID_QUERY", name)
            return v
        op = param("operator", lambda v: v != "")
        cls = param("vesselClass", lambda v: v in LIFT_RATE)
        cargo = param("cargo", lambda v: v in CARGO)
        frm = param("from", lambda v: parse_ts(v) is not None)
        to = param("to", lambda v: parse_ts(v) is not None)
        mt = param("minTotal", lambda v: MIN_TOTAL_RE.fullmatch(v))
        off = param("offset", lambda v: DIGITS_RE.fullmatch(v))
        lim = param("limit", lambda v: DIGITS_RE.fullmatch(v) and 1 <= int(v) <= 200)
        frm_ts, to_ts = frm and parse_ts(frm), to and parse_ts(to)
        if frm_ts and to_ts and frm_ts >= to_ts:
            raise ApiError(400, "INVALID_QUERY", "to")
        off, lim = int(off) if off else 0, int(lim) if lim else 50
        mt = D(mt) if mt else None
        matches = [p for p in self.passage_list
                   if (op is None or p["operator"] == op) and (cls is None or p["vesselClass"] == cls)
                   and (cargo is None or p["cargo"] == cargo)
                   and (frm_ts is None or parse_ts(p["enteredAt"]) >= frm_ts)
                   and (to_ts is None or parse_ts(p["enteredAt"]) < to_ts)
                   and (mt is None or D(p["toll"]["total"]) >= mt)]
        matches.sort(key=lambda p: p["id"])
        matches.sort(key=lambda p: p["enteredAt"], reverse=True)
        nxt = off + lim if off + lim < len(matches) else None
        return 200, {"items": matches[off:off + lim], "total": len(matches), "offset": off, "limit": lim,
                     "nextOffset": nxt}

    def import_passages(self, req):
        atomic = req.query.get("atomic", "false")
        if atomic not in ("true", "false"):
            raise ApiError(400, "INVALID_QUERY", "atomic")
        text = req.body.decode("utf-8", errors="replace")
        lines = text.split("\n")
        if lines and lines[-1] == "":
            lines.pop()
        lines = [(i + 1, l[:-1] if l.endswith("\r") else l) for i, l in enumerate(lines)]
        lines = [(n, l) for n, l in lines if l.strip(" \t") != ""]
        if len(lines) > 10000:
            raise ApiError(413, "BATCH_TOO_LARGE")
        results, pending, marks, rejected = [], [], set(), 0
        seq = len(self.passage_list)
        for n, line in lines:
            try:
                try:
                    o = json.loads(line)
                except ValueError:
                    raise ApiError(400, "MALFORMED_JSON")
                if not isinstance(o, dict):
                    raise ApiError(400, "MALFORMED_JSON")
                s = self.validate_passage(o, marks)
                marks.add((s["vesselMark"], s["enteredAt"]))
                seq += 1
                p = self.build_passage(s, seq)
                pending.append(p)
                results.append({"line": n, "id": p["id"]})
            except ApiError as e:
                rejected += 1
                results.append({"line": n, "error": {"code": e.code, "field": e.field}})
        if atomic == "true" and rejected:
            return 422, {"accepted": 0, "rejected": rejected, "results": [r for r in results if "error" in r]}
        for p in pending:
            self.store_passage(p)
        return 200, {"accepted": len(pending), "rejected": rejected, "results": results}

    def post_claim(self, req):
        key = req.idempotency_key()
        o = req.json_object()

        def create():
            pid = string(o, "passageId")
            fmt(PSG_RE.fullmatch(pid), "passageId")
            lock = enum(o, "lock", LOCKS)
            minutes = integer(o, "delayMinutes", 1, 1440)
            reason = enum(o, "reason", REASONS)
            actor = req.headers.get("X-Actor")
            if actor is None:
                actor = "anonymous"
            elif not ACTOR_RE.fullmatch(actor):
                raise ApiError(400, "FIELD_FORMAT", "X-Actor")
            p = self.passages.get(pid)
            if p is None:
                raise ApiError(422, "UNKNOWN_PASSAGE", "passageId")
            if lock not in p["locks"]:
                raise ApiError(422, "LOCK_NOT_ON_PASSAGE", "lock")
            if self.clock > parse_ts(p["enteredAt"]) + timedelta(days=14):
                raise ApiError(422, "CLAIM_WINDOW_CLOSED")
            if self.live_claim_exists(pid, lock):
                raise ApiError(409, "CLAIM_EXISTS", "lock")
            cid = "CLM-%05d" % (len(self.claims) + 1)
            c = {"id": cid, "passageId": pid, "operator": p["operator"], "lock": lock, "delayMinutes": minutes,
                 "reason": reason, "state": "LODGED", "version": 1, "lodgedAt": self.now(), "updatedAt": self.now(),
                 "eligibleRebate": rebate(p, lock, minutes, reason), "assessedMinutes": None,
                 "assessedRebate": None, "assessedBy": None, "approvedAmount": None, "approvedBy": None,
                 "approvedAt": None, "settlementReference": None, "rejectedAt": None, "reopenCount": 0}
            self.claims[cid] = c
            self.add_audit(c, actor, "lodge", None)
            return 201, c, {"ETag": '"1"'}
        return self.idempotent("claims", key, o, create)

    def get_claim(self, req, cid):
        c = self.claims.get(cid)
        if c is None:
            raise ApiError(404, "NOT_FOUND")
        return 200, c, {"ETag": '"%d"' % c["version"]}

    def transition(self, req, cid):
        c = self.claims.get(cid)
        if c is None:
            raise ApiError(404, "NOT_FOUND")
        im = req.headers.get("If-Match")
        if im is None:
            raise ApiError(428, "VERSION_REQUIRED", "If-Match")
        m = ETAG_RE.fullmatch(im)
        if not m:
            raise ApiError(400, "INVALID_HEADER", "If-Match")
        if int(m.group(1)) != c["version"]:
            raise ApiError(412, "VERSION_MISMATCH", "If-Match")
        o = req.json_object()
        action = enum(o, "action", ACTIONS)
        actor = req.headers.get("X-Actor")
        if actor is None:
            raise ApiError(400, "FIELD_REQUIRED", "X-Actor")
        if not ACTOR_RE.fullmatch(actor):
            raise ApiError(400, "FIELD_FORMAT", "X-Actor")
        sources, target = ACTIONS[action]
        if c["state"] not in sources:
            raise ApiError(409, "TRANSITION_FORBIDDEN", "action")
        p = self.passages[c["passageId"]]
        changes, note = {}, None
        if action == "assess":
            minutes = integer(o, "assessedMinutes", 0, c["delayMinutes"])
            changes = {"assessedMinutes": minutes, "assessedBy": actor,
                       "assessedRebate": rebate(p, c["lock"], minutes, c["reason"])}
        elif action == "reject":
            note = string(o, "note")
            fmt(1 <= len(note) <= 200, "note")
            changes = {"rejectedAt": self.now()}
        elif action == "approve":
            amount = o.get("amount")
            if amount is not None:
                if not isinstance(amount, str):
                    raise ApiError(400, "FIELD_TYPE", "amount")
                fmt(MONEY_RE.fullmatch(amount) and D(amount) > 0, "amount")
            if actor == c["assessedBy"]:
                raise ApiError(403, "SAME_ACTOR", "X-Actor")
            if D(c["assessedRebate"]) == 0:
                raise ApiError(422, "NOTHING_TO_APPROVE")
            if amount is not None and D(amount) > D(c["assessedRebate"]):
                raise ApiError(422, "AMOUNT_EXCEEDS", "amount")
            changes = {"approvedAmount": amount if amount is not None else c["assessedRebate"],
                       "approvedBy": actor, "approvedAt": self.now()}
        elif action == "settle":
            ref = string(o, "reference")
            fmt(re.fullmatch(r"STL-[0-9]{8}", ref), "reference")
            if self.clock < parse_ts(c["approvedAt"]) + timedelta(hours=48):
                raise ApiError(422, "SETTLEMENT_TOO_EARLY")
            changes = {"settlementReference": ref}
        elif action == "reopen":
            if c["reopenCount"] >= 1:
                raise ApiError(409, "REOPEN_LIMIT")
            if self.clock > parse_ts(c["rejectedAt"]) + timedelta(days=7):
                raise ApiError(422, "CLAIM_WINDOW_CLOSED")
            if self.live_claim_exists(c["passageId"], c["lock"], exclude=c["id"]):
                raise ApiError(409, "CLAIM_EXISTS", "lock")
            changes = {"reopenCount": 1, "assessedMinutes": None, "assessedRebate": None, "assessedBy": None,
                       "rejectedAt": None}
        before = c["state"]
        c.update(changes)
        c["state"], c["version"], c["updatedAt"] = target, c["version"] + 1, self.now()
        self.add_audit(c, actor, action, before, note)
        return 200, c, {"ETag": '"%d"' % c["version"]}

    def get_audit(self, req, cid):
        if cid not in self.claims:
            raise ApiError(404, "NOT_FOUND")
        return 200, {"claimId": cid, "entries": self.audit[cid]}

    def statement(self, req):
        op, month = req.query.get("operator"), req.query.get("month")
        if not op:
            raise ApiError(400, "INVALID_QUERY", "operator")
        m = MONTH_RE.fullmatch(month or "")
        if not m or not 1 <= int(m.group(2)) <= 12:
            raise ApiError(400, "INVALID_QUERY", "month")
        if op not in self.operators:
            raise ApiError(404, "NOT_FOUND")
        ps = [p for p in self.passage_list if p["operator"] == op and p["enteredAt"][:7] == month]
        ids = {p["id"] for p in ps}
        toll = sum((D(p["toll"]["total"]) for p in ps), D("0"))
        cargo = {}
        for p in ps:
            n, t = cargo.get(p["cargo"], (0, D("0")))
            cargo[p["cargo"]] = (n + 1, t + D(p["toll"]["total"]))
        by_cargo = sorted(cargo.items(), key=lambda kv: kv[0])
        by_cargo.sort(key=lambda kv: kv[1][1], reverse=True)
        busiest = None
        for lock in LOCK_ORDER:
            n = sum(1 for p in ps if lock in p["locks"])
            if n and (busiest is None or n > busiest["passages"]):
                busiest = {"lock": lock, "passages": n}
        claims = [c for c in self.claims.values() if c["passageId"] in ids]
        counts = {s: sum(1 for c in claims if c["state"] == s) for s in STATES}
        approved = sum((D(c["approvedAmount"]) for c in claims if c["state"] == "APPROVED"), D("0"))
        settled = sum((D(c["approvedAmount"]) for c in claims if c["state"] == "SETTLED"), D("0"))
        return 200, {"operator": op, "month": month, "passages": len(ps), "tollTotal": s2(toll),
                     "byCargo": [{"cargo": k, "passages": n, "tollTotal": s2(t)} for k, (n, t) in by_cargo],
                     "busiestLock": busiest, "claims": counts, "rebatesApproved": s2(approved),
                     "rebatesSettled": s2(settled), "net": s2(toll - settled)}


ROUTES = [
    ("GET", r"/admin/clock", lambda s, r: (200, {"now": s.now()})),
    ("PUT", r"/admin/clock", Service.put_clock),
    ("POST", r"/admin/reset", lambda s, r: (s.reset(), (204, None))[1]),
    ("POST", r"/operators", Service.post_operator),
    ("GET", r"/operators/([^/]+)", Service.get_operator),
    ("POST", r"/tariff/quotes", Service.post_quotes),
    ("POST", r"/passages", Service.post_passage),
    ("GET", r"/passages", Service.list_passages),
    ("POST", r"/passages/import", Service.import_passages),
    ("GET", r"/passages/([^/]+)", Service.get_passage),
    ("POST", r"/claims", Service.post_claim),
    ("GET", r"/claims/([^/]+)", Service.get_claim),
    ("POST", r"/claims/([^/]+)/transitions", Service.transition),
    ("GET", r"/claims/([^/]+)/audit", Service.get_audit),
    ("GET", r"/reports/operator-statement", Service.statement),
]


class Request:
    def __init__(self, headers, body, query):
        self.headers, self.body, self.query = headers, body, query

    def json_object(self):
        try:
            v = json.loads(self.body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            raise ApiError(400, "MALFORMED_JSON")
        if not isinstance(v, dict):
            raise ApiError(400, "MALFORMED_JSON")
        return v

    def idempotency_key(self):
        k = self.headers.get("Idempotency-Key")
        if k is not None and not KEY_RE.fullmatch(k):
            raise ApiError(400, "FIELD_FORMAT", "Idempotency-Key")
        return k


SERVICE = Service()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def handle_any(self):
        parts = urlsplit(self.path)
        query = {}
        for k, v in parse_qsl(parts.query, keep_blank_values=True):
            query.setdefault(k, v)
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        headers = {}
        try:
            for method, pattern, fn in ROUTES:
                m = re.fullmatch(pattern, parts.path)
                if m and method == self.command:
                    with SERVICE.mutex:
                        result = fn(SERVICE, Request(self.headers, body, query), *m.groups())
                    break
            else:
                raise ApiError(404, "ROUTE_NOT_FOUND")
            status, payload = result[0], result[1]
            headers = result[2] if len(result) > 2 else {}
        except ApiError as e:
            status, payload = e.status, {"error": {"code": e.code, "field": e.field, "message": e.code}}
        data = b"" if payload is None else json.dumps(payload).encode("utf-8")
        self.send_response(status)
        for k, v in headers.items():
            self.send_header(k, v)
        if payload is not None:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = do_PUT = do_POST = do_DELETE = do_PATCH = handle_any


if __name__ == "__main__":
    port = int(os.environ.get("PORT") or (sys.argv[1] if len(sys.argv) > 1 else 8080))
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
