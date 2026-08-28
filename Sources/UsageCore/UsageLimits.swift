import Foundation
import Security

/// How close a limit is to being exhausted. One place decides the thresholds so
/// the bar colour, the menu bar icon and the notifications never disagree.
public enum Severity: Int, Comparable, Sendable {
    case normal, warning, critical

    public static let warningPercent = 80
    public static let criticalPercent = 95

    public init(percent: Int) {
        if percent >= Self.criticalPercent { self = .critical }
        else if percent >= Self.warningPercent { self = .warning }
        else { self = .normal }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One rate-limit window from a CLI subscription (5-hour, weekly, …).
public struct UsageLimit: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let percent: Int
    public let resetsAt: Date?

    public init(id: String, title: String, percent: Int, resetsAt: Date?) {
        self.id = id
        self.title = title
        self.percent = percent
        self.resetsAt = resetsAt
    }

    public var severity: Severity { Severity(percent: percent) }

    /// "resets 4d" / "resets 3h" — same shorthand the Claude menu uses.
    public var resetLabel: String? { resetLabel(now: Date()) }

    /// Injectable clock so the boundaries are testable.
    public func resetLabel(now: Date) -> String? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let hours = Int(seconds / 3_600)
        if hours >= 24 { return "resets \(hours / 24)d" }
        if hours >= 1 { return "resets \(hours)h" }
        return "resets \(max(1, Int(seconds / 60)))m"
    }
}

/// Subscription limits for one CLI, rendered as its own menu section.
public struct UsageGroup: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let plan: String?
    public let limits: [UsageLimit]

    public init(id: String, name: String, plan: String?, limits: [UsageLimit]) {
        self.id = id
        self.name = name
        self.plan = plan
        self.limits = limits
    }

    /// "CLAUDE CODE · MAX"
    public var header: String {
        [name, plan].compactMap { $0 }.joined(separator: " · ").uppercased()
    }

    public var severity: Severity { limits.map(\.severity).max() ?? .normal }
}

public extension Collection<UsageGroup> {
    /// Worst state across every agent, for the menu bar icon.
    var severity: Severity { map(\.severity).max() ?? .normal }
}

/// Turns a rolling-window length into the label the vendors use.
public func windowTitle(seconds: Int) -> String {
    switch seconds {
    case 18_000: "5-hour limit"
    case 604_800: "Weekly limit"
    case 86_400: "Daily limit"
    default: "\(seconds / 3_600)-hour limit"
    }
}

/// Claude Code: OAuth token from the Keychain item the CLI writes, then
/// GET /api/oauth/usage — the same source the Claude menu bar shows.
public enum ClaudeUsageReader {
    private static let credentialService = "Claude Code-credentials"
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public static func load() async -> UsageGroup? {
        guard let credentials = credentials(),
              let token = credentials["accessToken"] as? String else { return nil }
        let plan = (credentials["subscriptionType"] as? String) ?? (credentials["rateLimitTier"] as? String)

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parse(object, plan: plan)
    }

    /// The `limits` array is what the Claude menu renders: a session window, the
    /// all-model weekly window, and a weekly window scoped to one model.
    public static func parse(_ object: [String: Any], plan: String?) -> UsageGroup? {
        guard let entries = object["limits"] as? [[String: Any]] else { return nil }
        let limits: [UsageLimit] = entries.enumerated().compactMap { index, entry in
            guard let kind = entry["kind"] as? String,
                  let percent = (entry["percent"] as? NSNumber)?.intValue else { return nil }
            let title: String
            switch kind {
            case "session": title = "5-hour limit"
            case "weekly_all": title = "Weekly · all models"
            case "weekly_scoped":
                let scope = entry["scope"] as? [String: Any]
                let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
                title = model.map { "Weekly · \($0)" } ?? "Weekly · scoped"
            default: return nil
            }
            return UsageLimit(id: "claude-\(kind)-\(index)", title: title, percent: percent,
                              resetsAt: isoDate(entry["resets_at"] as? String))
        }
        guard !limits.isEmpty else { return nil }
        return UsageGroup(id: "claude", name: "Claude Code", plan: plan, limits: limits)
    }

    /// Keychain item is written by the Claude Code CLI; first read prompts for access.
    private static func credentials() -> [String: Any]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["claudeAiOauth"] as? [String: Any]
    }
}

/// Codex: ChatGPT OAuth tokens live in ~/.codex/auth.json (auth_mode "chatgpt"),
/// and usage comes from the same backend endpoint the CLI polls.
public enum CodexUsageReader {
    private static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    /// Codex keeps the active login in ~/.codex/auth.json. Extra accounts are picked
    /// up from sibling copies (auth.work.json, auth.personal.json, …).
    public static func loadAll() async -> [UsageGroup] {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path())) ?? [])
            .filter { $0.hasPrefix("auth") && $0.hasSuffix(".json") }
            .sorted()
        var groups: [UsageGroup] = []
        for file in files {
            if let group = await load(authFile: directory.appending(path: file)) { groups.append(group) }
        }
        return groups
    }

    private static func load(authFile: URL) async -> UsageGroup? {
        guard let data = try? Data(contentsOf: authFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String,
              let accountID = tokens["account_id"] as? String else { return nil }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        // Endpoint 403s without the CLI's originator header.
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (body, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return parse(object, id: authFile.lastPathComponent, account: accountLabel(tokens["id_token"] as? String))
    }

    public static func parse(_ object: [String: Any], id: String, account: String?) -> UsageGroup? {
        let rateLimit = object["rate_limit"] as? [String: Any]
        let limits: [UsageLimit] = ["primary_window", "secondary_window"].compactMap { key in
            guard let window = rateLimit?[key] as? [String: Any],
                  let percent = (window["used_percent"] as? NSNumber)?.intValue else { return nil }
            let seconds = (window["limit_window_seconds"] as? NSNumber)?.intValue ?? 0
            let resetsAt = (window["reset_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return UsageLimit(id: "\(id)-\(key)", title: windowTitle(seconds: seconds), percent: percent, resetsAt: resetsAt)
        }
        guard !limits.isEmpty else { return nil }
        let label = (object["email"] as? String) ?? account
        let name = label.map { "Codex · \($0)" } ?? "Codex"
        return UsageGroup(id: "codex-\(id)", name: name, plan: object["plan_type"] as? String, limits: limits)
    }

    /// Account label from the id_token so several Codex logins stay distinguishable.
    public static func accountLabel(_ idToken: String?) -> String? {
        guard let segment = idToken?.split(separator: ".").dropFirst().first else { return nil }
        var base64 = String(segment).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let email = claims["email"] as? String { return email.split(separator: "@").first.map(String.init) }
        return claims["name"] as? String
    }
}

/// Z.AI / GLM coding plan: key from the shell environment, quota from the
/// same monitor endpoint the official usage plugin calls.
public enum ZaiUsageReader {
    public static func load() async -> UsageGroup? {
        guard let key = apiKey() else { return nil }
        let host = ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"]
            .flatMap { URL(string: $0)?.host } ?? "api.z.ai"
        guard let url = URL(string: "https://\(host)/api/monitor/usage/quota/limit") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(key, forHTTPHeaderField: "Authorization") // raw token, not Bearer
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parse(object)
    }

    /// TOKENS_LIMIT is the rolling token window; TIME_LIMIT is monthly MCP calls, not shown.
    public static func parse(_ object: [String: Any]) -> UsageGroup? {
        guard let payload = object["data"] as? [String: Any],
              let entries = payload["limits"] as? [[String: Any]] else { return nil }
        let limits: [UsageLimit] = entries.compactMap { entry in
            guard entry["type"] as? String == "TOKENS_LIMIT",
                  let percent = (entry["percentage"] as? NSNumber)?.intValue else { return nil }
            let hours = (entry["number"] as? NSNumber)?.intValue ?? 5
            let resetsAt = (entry["nextResetTime"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1_000) }
            return UsageLimit(id: "zai-tokens", title: windowTitle(seconds: hours * 3_600), percent: percent, resetsAt: resetsAt)
        }
        guard !limits.isEmpty else { return nil }
        return UsageGroup(id: "zai", name: "Z.AI", plan: payload["level"] as? String, limits: limits)
    }

    /// Menu bar apps launched from Finder get no shell env, so fall back to the rc file.
    private static func apiKey() -> String? {
        let environment = ProcessInfo.processInfo.environment
        for name in ["GLM_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ZAI_API_KEY"] {
            if let value = environment[name], !value.isEmpty { return value }
        }
        let rc = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".zshrc")
        guard let text = try? String(contentsOf: rc, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.contains("GLM_API_KEY=") {
            guard let value = line.split(separator: "=", maxSplits: 1).last else { continue }
            let key = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            if !key.isEmpty { return key }
        }
        return nil
    }
}

/// Grok / xAI: no public quota API, but the `omp` CLI already brokers the
/// SuperGrok OAuth login and reports its limits, so shell out to that.
public enum OmpUsageReader {
    private static let candidatePaths = ["\(NSHomeDirectory())/.bun/bin/omp", "/opt/homebrew/bin/omp", "/usr/local/bin/omp"]

    public static func loadGrok() async -> UsageGroup? {
        guard let binary = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
              let data = run(binary, ["usage", "--json", "--provider", "xai-oauth"]),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parse(object)
    }

    /// omp lists several weekly buckets; the aggregate credits one comes first
    /// and is the limit that actually bites, so only the first per window is kept.
    public static func parse(_ object: [String: Any]) -> UsageGroup? {
        guard let reports = object["reports"] as? [[String: Any]],
              let report = reports.first,
              let entries = report["limits"] as? [[String: Any]] else { return nil }

        var seenWindows = Set<String>()
        let limits: [UsageLimit] = entries.compactMap { entry in
            guard let window = entry["window"] as? [String: Any],
                  let windowID = window["id"] as? String,
                  ["5h", "1w", "7d"].contains(windowID),
                  seenWindows.insert(windowID).inserted,
                  let amount = entry["amount"] as? [String: Any],
                  let fraction = (amount["usedFraction"] as? NSNumber)?.doubleValue else { return nil }
            let resetsAt = (window["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1_000) }
            let title = windowID == "5h" ? "5-hour limit" : "Weekly limit"
            return UsageLimit(id: "grok-\(windowID)", title: title, percent: Int((fraction * 100).rounded()), resetsAt: resetsAt)
        }
        guard !limits.isEmpty else { return nil }
        let plan = (report["metadata"] as? [String: Any])?["planType"] as? String
        return UsageGroup(id: "grok", name: "Grok", plan: plan, limits: limits)
    }

    private static func run(_ binary: String, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        // omp is a bun shebang script, so it needs the runtime on PATH.
        var environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        environment["PATH"] = "\(home)/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}

private func isoDate(_ text: String?) -> Date? {
    guard let text else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}
