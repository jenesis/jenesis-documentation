from lib import Case, call, rule, MISSING, NOW


class Clock(Case):
    @rule("R2.1")
    def test_clock_starts_at_new_year_after_reset(self):
        self.ok(call("POST", "/admin/reset"), 204)
        self.assertEqual(self.ok(call("GET", "/admin/clock"), 200), {"now": "2026-01-01T00:00:00Z"})

    @rule("R2.2")
    def test_invalid_clock_values(self):
        self.error(call("PUT", "/admin/clock", {"now": "yesterday"}), 400, "FIELD_FORMAT", "now")
        self.error(call("PUT", "/admin/clock", {}), 400, "FIELD_REQUIRED", "now")
        self.error(call("PUT", "/admin/clock", {"now": 1773964800}), 400, "FIELD_TYPE", "now")
        self.assertEqual(self.ok(call("GET", "/admin/clock"), 200), {"now": NOW})

    @rule("R2.2")
    def test_clock_may_move_backwards(self):
        self.clock("2025-12-25T00:00:00Z")
        self.assertEqual(self.ok(call("GET", "/admin/clock"), 200), {"now": "2025-12-25T00:00:00Z"})

    @rule("R2.4")
    def test_recorded_at_is_the_service_clock(self):
        self.clock("2026-03-21T07:45:10Z")
        self.assertEqual(self.passage()["recordedAt"], "2026-03-21T07:45:10Z")


class Operators(Case):
    @rule("R3.1")
    def test_check_digit_examples(self):
        self.ok(call("POST", "/operators", {"code": "QD-737", "name": "Q", "tier": "ordinary"}), 201)
        self.error(call("POST", "/operators", {"code": "QD-736", "name": "Q", "tier": "ordinary"}),
                   400, "CHECK_DIGIT", "code")
        self.ok(call("POST", "/operators", {"code": "ZZ-996", "name": "Z", "tier": "ordinary"}), 201)

    @rule("R3.1")
    def test_check_digit_is_part_of_the_code_check(self):
        self.error(call("POST", "/operators", {"code": "KV-205", "tier": "nobody"}), 400, "CHECK_DIGIT", "code")

    @rule("R3.1")
    def test_code_pattern(self):
        for bad in ["kv-209", "KV209", "KVX-209", "KV-2090", "K1-209"]:
            self.error(call("POST", "/operators", {"code": bad, "name": "X", "tier": "ordinary"}),
                       400, "FIELD_FORMAT", "code")

    @rule("R3.3")
    def test_name_and_tier_rules(self):
        self.error(call("POST", "/operators", {"code": "QD-737", "name": "    ", "tier": "ordinary"}),
                   400, "FIELD_FORMAT", "name")
        self.error(call("POST", "/operators", {"code": "QD-737", "name": "x" * 61, "tier": "ordinary"}),
                   400, "FIELD_FORMAT", "name")
        self.ok(call("POST", "/operators", {"code": "QD-737", "name": " " + "x" * 60 + " ", "tier": "heritage"}),
                201)
        self.error(call("POST", "/operators", {"code": "ZZ-996", "name": "x", "tier": "Ordinary"}),
                   400, "FIELD_FORMAT", "tier")

    @rule("R3.4")
    def test_get_operator(self):
        self.error(call("GET", "/operators/QD-737"), 404, "NOT_FOUND", None)
        self.assertEqual(self.ok(call("GET", "/operators/AB-102"), 200)["tier"], "contract")
