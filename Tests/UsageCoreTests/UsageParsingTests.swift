import Foundation
import Testing
@testable import UsageCore

private func json(_ text: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
}

// MARK: - Claude

@Test func claudeReadsAllThreeWindowsIncludingTheScopedModel() throws {
    // Shape taken from a real /api/oauth/usage response.
    let group = ClaudeUsageReader.parse(json("""
    {"five_hour": {"utilization": 16}, "seven_day": {"utilization": 47},
     "limits": [
       {"kind": "session", "percent": 16, "resets_at": "2026-08-28T18:29:59.671181+00:00"},
       {"kind": "weekly_all", "percent": 47, "resets_at": "2026-09-01T22:59:59.671203+00:00"},
       {"kind": "weekly_scoped", "percent": 35, "resets_at": "2026-09-01T22:59:59.671457+00:00",
        "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}}
     ]}
    """), plan: "max")

    let limits = try #require(group?.limits)
    #expect(limits.map(\.title) == ["5-hour limit", "Weekly · all models", "Weekly · Fable"])
    #expect(limits.map(\.percent) == [16, 47, 35])
    #expect(group?.header == "CLAUDE CODE · MAX")
    #expect(limits[0].resetsAt != nil) // fractional-seconds ISO8601 must parse
}

@Test func claudeIgnoresUnknownKindsAndMissingLimits() {
    #expect(ClaudeUsageReader.parse(json(#"{"five_hour": {"utilization": 16}}"#), plan: nil) == nil)
    #expect(ClaudeUsageReader.parse(json(#"{"limits": [{"kind": "mystery", "percent": 5}]}"#), plan: nil) == nil)
}

// MARK: - Codex

@Test func codexNamesWindowsFromTheirDuration() throws {
    let group = ClaudeCodexFixture.parsed()
    let limits = try #require(group?.limits)
    #expect(limits.map(\.title) == ["5-hour limit", "Weekly limit"])
    #expect(limits.map(\.percent) == [81, 29])
    #expect(group?.name == "Codex · someone")
    #expect(group?.plan == "plus")
}

private enum ClaudeCodexFixture {
    static func parsed() -> UsageGroup? {
        CodexUsageReader.parse(json("""
        {"plan_type": "plus",
         "rate_limit": {
           "primary_window": {"used_percent": 81, "limit_window_seconds": 18000, "reset_at": 1787938516},
           "secondary_window": {"used_percent": 29, "limit_window_seconds": 604800, "reset_at": 1788452753}}}
        """), id: "auth.json", account: "someone")
    }
}

@Test func codexDecodesAccountFromJWTNeedingBase64Padding() {
    // Payload length is deliberately not a multiple of 4 once base64url-encoded.
    let payload = Data(#"{"email":"thaitrn007@gmail.com","name":"Trần Thái"}"#.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    #expect(CodexUsageReader.accountLabel("header.\(payload).signature") == "thaitrn007")
    #expect(CodexUsageReader.accountLabel(nil) == nil)
    #expect(CodexUsageReader.accountLabel("not-a-jwt") == nil)
}

// MARK: - Z.AI

@Test func zaiKeepsTheTokenWindowAndDropsMonthlyMcpQuota() throws {
    let group = ZaiUsageReader.parse(json("""
    {"code": 200, "data": {"level": "pro", "limits": [
       {"type": "TIME_LIMIT", "unit": 5, "number": 1, "percentage": 73, "nextResetTime": 1790293689998},
       {"type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 1, "nextResetTime": 1787944247390}]}}
    """))

    let limits = try #require(group?.limits)
    #expect(limits.count == 1)
    #expect(limits[0].title == "5-hour limit")
    #expect(limits[0].percent == 1)
    // nextResetTime is milliseconds, not seconds.
    #expect(limits[0].resetsAt == Date(timeIntervalSince1970: 1_787_944_247.390))
    #expect(group?.plan == "pro")
}

// MARK: - omp / Grok

@Test func ompKeepsOneRowPerWindow() throws {
    let group = OmpUsageReader.parse(json("""
    {"reports": [{"provider": "xai-oauth", "metadata": {"planType": "supergrok"}, "limits": [
       {"id": "xai-oauth:credits:1w", "window": {"id": "1w", "resetsAt": 1788186575511}, "amount": {"usedFraction": 0.06}},
       {"id": "xai-oauth:product:grokbuild:1w", "window": {"id": "1w", "resetsAt": 1788186575511}, "amount": {"usedFraction": 0.03}},
       {"id": "xai-oauth:product:grokchat:1w", "window": {"id": "1w", "resetsAt": 1788186575511}, "amount": {"usedFraction": 0.03}},
       {"id": "xai-oauth:something:1mo", "window": {"id": "1mo"}, "amount": {"usedFraction": 0.5}}]}]}
    """))

    let limits = try #require(group?.limits)
    #expect(limits.count == 1) // three weekly buckets collapse to the aggregate one
    #expect(limits[0].title == "Weekly limit")
    #expect(limits[0].percent == 6) // 0.06 fraction -> percent
    #expect(group?.header == "GROK · SUPERGROK")
}

// MARK: - Shared behaviour

@Test func resetLabelPicksTheCoarsestUsefulUnit() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func label(after seconds: TimeInterval) -> String? {
        UsageLimit(id: "x", title: "x", percent: 0, resetsAt: now.addingTimeInterval(seconds)).resetLabel(now: now)
    }
    #expect(label(after: 4 * 86_400) == "resets 4d")
    #expect(label(after: 3 * 3_600) == "resets 3h")
    #expect(label(after: 30 * 60) == "resets 30m")
    #expect(label(after: 30) == "resets 1m")   // never rounds down to zero
    #expect(label(after: -60) == nil)          // already reset
    #expect(UsageLimit(id: "x", title: "x", percent: 0, resetsAt: nil).resetLabel(now: now) == nil)
}

@Test func severityBoundariesMatchTheAlertThresholds() {
    #expect(Severity(percent: 79) == .normal)
    #expect(Severity(percent: 80) == .warning)
    #expect(Severity(percent: 94) == .warning)
    #expect(Severity(percent: 95) == .critical)
    #expect(Severity(percent: 100) == .critical)
}

@Test func groupSeverityTakesTheWorstLimit() {
    let group = UsageGroup(id: "g", name: "G", plan: nil, limits: [
        UsageLimit(id: "a", title: "a", percent: 10, resetsAt: nil),
        UsageLimit(id: "b", title: "b", percent: 96, resetsAt: nil)
    ])
    #expect(group.severity == .critical)
    #expect([group].severity == .critical)
    #expect([UsageGroup]().severity == .normal)
}
