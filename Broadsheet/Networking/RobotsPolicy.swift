import Foundation

/// The `robots.txt` rules that apply to Broadsheet on one host.
public struct RobotsRules: Equatable, Sendable {
    public struct Rule: Equatable, Sendable {
        public let path: String
        public let allows: Bool
    }

    public let rules: [Rule]
    /// True when the host published no rules that apply to us.
    public let isUnrestricted: Bool

    public static let unrestricted = RobotsRules(rules: [], isUnrestricted: true)
    public static let forbidEverything = RobotsRules(rules: [Rule(path: "/", allows: false)], isUnrestricted: false)

    public init(rules: [Rule], isUnrestricted: Bool) {
        self.rules = rules
        self.isUnrestricted = isUnrestricted
    }

    /// Longest matching prefix wins; `Allow` wins a tie. This is the conventional
    /// resolution order used by the major crawlers.
    public func allows(path: String) -> Bool {
        let target = path.isEmpty ? "/" : path
        var best: Rule?

        for rule in rules where matches(rule.path, target) {
            guard let current = best else { best = rule; continue }
            if rule.path.count > current.path.count {
                best = rule
            } else if rule.path.count == current.path.count, rule.allows {
                best = rule
            }
        }

        return best?.allows ?? true
    }

    /// Supports the `*` wildcard and the `$` end-anchor that the de facto standard
    /// added; anything else is treated as a literal prefix.
    private func matches(_ pattern: String, _ path: String) -> Bool {
        if pattern.isEmpty { return false }

        let anchored = pattern.hasSuffix("$")
        let body = anchored ? String(pattern.dropLast()) : pattern
        let segments = body.components(separatedBy: "*")

        var index = path.startIndex
        for (position, segment) in segments.enumerated() {
            if segment.isEmpty {
                if position == segments.count - 1, anchored { return index == path.endIndex }
                continue
            }
            guard let found = path.range(of: segment, range: index..<path.endIndex) else { return false }
            if position == 0, found.lowerBound != path.startIndex { return false }
            index = found.upperBound
        }

        if anchored, segments.last?.isEmpty == false {
            return index == path.endIndex
        }
        return true
    }

    /// Parses the groups that apply to `userAgentToken`, falling back to `*`.
    public static func parse(_ text: String, userAgentToken: String) -> RobotsRules {
        var currentAgents: [String] = []
        var groups: [String: [Rule]] = [:]
        var startingNewGroup = true

        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine
            if let hash = line.firstIndex(of: "#") { line = String(line[line.startIndex..<hash]) }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, let colon = line.firstIndex(of: ":") else { continue }

            let field = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)

            switch field {
            case "user-agent":
                if !startingNewGroup { currentAgents = [] }
                startingNewGroup = true
                let agent = value.lowercased()
                currentAgents.append(agent)
                if groups[agent] == nil { groups[agent] = [] }
            case "disallow", "allow":
                startingNewGroup = false
                guard !currentAgents.isEmpty else { continue }
                // An empty `Disallow:` is the standard way to permit everything.
                if field == "disallow", value.isEmpty { continue }
                guard !value.isEmpty else { continue }
                for agent in currentAgents {
                    groups[agent, default: []].append(Rule(path: value, allows: field == "allow"))
                }
            default:
                continue
            }
        }

        let token = userAgentToken.lowercased()
        if let specific = groups[token] {
            return RobotsRules(rules: specific, isUnrestricted: specific.isEmpty)
        }
        if let wildcard = groups["*"] {
            return RobotsRules(rules: wildcard, isUnrestricted: wildcard.isEmpty)
        }
        return .unrestricted
    }
}

/// Checks `robots.txt` before Broadsheet fetches an article page.
///
/// A feed the reader subscribed to is fetched because they asked for it. Fetching
/// the *article page* behind a feed item is closer to crawling, so it is gated on
/// the publisher's own stated rules. When `robots.txt` cannot be read at all the
/// answer is "no": treating a failure as permission would be exactly the bypass
/// the product boundary forbids. The reader still gets the feed excerpt and a link.
public actor RobotsPolicy {
    public static let userAgentToken = "Broadsheet"

    private let transport: any HTTPTransport
    private let ttl: TimeInterval
    private var cache: [String: (rules: RobotsRules, fetchedAt: Date)] = [:]
    private var inFlight: [String: Task<RobotsRules, Never>] = [:]

    public init(transport: any HTTPTransport, ttl: TimeInterval = 6 * 60 * 60) {
        self.transport = transport
        self.ttl = ttl
    }

    public func isFetchAllowed(_ url: URL, now: Date = Date()) async -> Bool {
        guard let host = url.host, url.scheme?.lowercased() == "https" else { return false }
        let rules = await self.rules(forHost: host, scheme: "https", now: now)
        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty { path += "?" + query }
        return rules.allows(path: path)
    }

    func rules(forHost host: String, scheme: String, now: Date) async -> RobotsRules {
        if let cached = cache[host], now.timeIntervalSince(cached.fetchedAt) < ttl {
            return cached.rules
        }
        if let existing = inFlight[host] {
            return await existing.value
        }

        let transport = self.transport
        let task = Task<RobotsRules, Never> {
            guard let url = URL(string: "\(scheme)://\(host)/robots.txt") else { return .forbidEverything }
            do {
                let response = try await transport.fetch(url, accept: HTTPAccept.text, limits: .robots)
                return RobotsRules.parse(response.text, userAgentToken: RobotsPolicy.userAgentToken)
            } catch HTTPFetchError.httpStatus(let code, _) where (400..<500).contains(code) {
                // No robots file published: nothing is restricted.
                return .unrestricted
            } catch {
                return .forbidEverything
            }
        }
        inFlight[host] = task
        let rules = await task.value
        inFlight[host] = nil
        cache[host] = (rules, now)
        return rules
    }

    public func removeCachedRules() {
        cache.removeAll()
    }
}
