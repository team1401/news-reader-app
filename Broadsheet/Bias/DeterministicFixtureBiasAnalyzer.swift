import Foundation

/// A deterministic, rule-based lean heuristic — **not** a machine-learning model
/// and never to be described as one.
///
/// It exists so bundled demo journalism, SwiftUI previews, and tests produce the
/// same label every run on every machine, including simulators where Apple
/// Intelligence is unavailable. It is only ever applied to
/// ``ContentSource/bundledFixture`` articles; live feed articles are analyzed by a
/// real local model or reported as unavailable.
public struct DeterministicFixtureBiasAnalyzer: BiasAnalyzing {
    public static let version = "fixture-heuristic-1.0"

    public var engine: BiasEngine { .deterministicFixture }
    public var isAvailable: Bool { true }
    public var availabilityDescription: String {
        "Deterministic fixture heuristic. Always available; used for bundled demo journalism only."
    }

    public init() {}

    // MARK: Lexicons

    /// Terms that indicate the article is about civic power at all. Without enough
    /// of these the article is N/A rather than being assigned an ideology.
    static let civicTerms: [String] = [
        "congress", "senate", "house", "lawmakers", "legislature", "legislation",
        "governor", "mayor", "council", "agency", "regulator", "regulators",
        "federal", "state", "policy", "bill", "statute", "rule", "rulemaking",
        "court", "ruling", "judge", "commission", "election", "ballot", "voters",
        "administration", "department", "budget", "hearing", "subsidy", "tax",
        "campaign", "party", "democrats", "republicans", "committee"
    ]

    static let leftFramingTerms: [String] = [
        "working families", "corporate polluters", "tax breaks for the wealthy",
        "income inequality", "inequality", "living wage", "climate crisis",
        "frontline communities", "affordable housing", "public option",
        "corporate accountability", "price gouging", "social safety net",
        "labor union", "unionized", "collective bargaining", "underfunded",
        "systemic", "marginalized", "public investment", "corporate profits",
        "watchdogs warn", "deregulation", "gutted", "windfall profits",
        "environmental justice", "wage theft", "billionaires"
    ]

    static let rightFramingTerms: [String] = [
        "government overreach", "regulatory burden", "tax burden", "job creators",
        "fiscal responsibility", "runaway spending", "red tape", "free market",
        "small business owners", "entitlement spending", "law and order",
        "border security", "parental rights", "school choice", "judicial activism",
        "unelected bureaucrats", "federal mandate", "compliance costs",
        "taxpayer dollars", "burdensome", "heavy-handed", "onerous",
        "energy independence", "government mandate", "bureaucracy", "overregulation"
    ]

    // MARK: Analysis

    public func analyze(_ input: BiasModelInput) async throws -> BiasAnalysisResult {
        Self.result(for: input)
    }

    /// Synchronous entry point so previews and tests can score without `await`.
    public static func result(for input: BiasModelInput) -> BiasAnalysisResult {
        let provenance = BiasProvenance(engine: .deterministicFixture, modelVersion: version)

        guard input.hasSufficientContent else {
            return BiasAnalysisResult(
                label: .notApplicable,
                confidenceScore: 0.55,
                rationale: "Only \(input.wordCount) words of article text were available, which is not enough to estimate political framing.",
                evidence: [],
                provenance: provenance
            )
        }

        let emphasized = [input.headline, input.dek ?? ""].joined(separator: " ")
        let body = input.bodyText

        let leftMatches = matches(of: leftFramingTerms, emphasized: emphasized, body: body)
        let rightMatches = matches(of: rightFramingTerms, emphasized: emphasized, body: body)
        let civicMatches = matches(of: civicTerms, emphasized: emphasized, body: body)

        let relevance = leftMatches.weight + rightMatches.weight + civicMatches.weight

        guard relevance >= 3.0 else {
            return BiasAnalysisResult(
                label: .notApplicable,
                confidenceScore: 0.85,
                rationale: "The article does not carry substantive political framing, so no left/right estimate is offered.",
                evidence: [],
                provenance: provenance
            )
        }

        let partisanWeight = leftMatches.weight + rightMatches.weight
        let lean = partisanWeight > 0
            ? (rightMatches.weight - leftMatches.weight) / partisanWeight
            : 0

        let label: BiasLabel
        if abs(lean) <= 0.34 {
            label = .center
        } else {
            label = lean > 0 ? .right : .left
        }

        let lengthBonus = min(0.08, Double(input.wordCount) / 6_000)
        let confidenceScore: Double
        switch label {
        case .center:
            confidenceScore = min(0.88, 0.55 + (1 - abs(lean)) * 0.22 + lengthBonus)
        default:
            confidenceScore = min(0.92, 0.52 + abs(lean) * 0.32 + lengthBonus)
        }

        let cueTerms = label == .left
            ? leftMatches.terms
            : (label == .right ? rightMatches.terms : leftMatches.terms + rightMatches.terms)

        return BiasAnalysisResult(
            label: label,
            confidenceScore: confidenceScore,
            rationale: rationale(
                label: label,
                leftWeight: leftMatches.weight,
                rightWeight: rightMatches.weight
            ),
            evidence: evidence(for: cueTerms.isEmpty ? civicMatches.terms : cueTerms, in: input),
            provenance: provenance
        )
    }

    // MARK: Scoring helpers

    struct MatchSummary {
        var weight: Double = 0
        var terms: [String] = []
    }

    /// Headline and dek carry 2.5× weight, per the weighting described in the
    /// bias-engine architecture.
    static func matches(of terms: [String], emphasized: String, body: String) -> MatchSummary {
        var summary = MatchSummary()
        for term in terms {
            let emphasizedHits = occurrences(of: term, in: emphasized)
            let bodyHits = occurrences(of: term, in: body)
            guard emphasizedHits + bodyHits > 0 else { continue }
            summary.weight += Double(emphasizedHits) * 2.5 + Double(bodyHits)
            summary.terms.append(term)
        }
        return summary
    }

    /// Word-boundary aware so `union` does not match `communion`.
    static func occurrences(of term: String, in text: String) -> Int {
        guard !term.isEmpty, !text.isEmpty else { return 0 }
        var count = 0
        var searchRange = text.startIndex..<text.endIndex

        while let found = text.range(of: term, options: [.caseInsensitive], range: searchRange) {
            let precededByLetter = found.lowerBound > text.startIndex
                && text[text.index(before: found.lowerBound)].isLetter
            let followedByLetter = found.upperBound < text.endIndex
                && text[found.upperBound].isLetter
            if !precededByLetter && !followedByLetter {
                count += 1
            }
            searchRange = found.upperBound..<text.endIndex
        }

        return count
    }

    static func rationale(label: BiasLabel, leftWeight: Double, rightWeight: Double) -> String {
        let left = String(format: "%.1f", leftWeight)
        let right = String(format: "%.1f", rightWeight)
        switch label {
        case .left:
            return "Framing weight favours language associated with left-of-centre coverage (\(left) versus \(right))."
        case .right:
            return "Framing weight favours language associated with right-of-centre coverage (\(right) versus \(left))."
        case .center:
            guard leftWeight + rightWeight > 0 else {
                return "The article covers political subject matter without using framing language associated with either side."
            }
            return "Political subject matter is present, but left- and right-associated framing are balanced (\(left) versus \(right))."
        case .notApplicable:
            return "No political framing was detected."
        }
    }

    static func evidence(for terms: [String], in input: BiasModelInput) -> [BiasEvidence] {
        let sentences = self.sentences(in: input)
        var selected: [String] = []

        for term in terms {
            guard let sentence = sentences.first(where: {
                occurrences(of: term, in: $0) > 0 && !selected.contains($0)
            }) else { continue }
            selected.append(sentence)
            if selected.count == 3 { break }
        }

        return selected.map { BiasEvidence(excerpt: trimmed($0)) }
    }

    static func sentences(in input: BiasModelInput) -> [String] {
        let text = [input.headline, input.dek ?? "", input.bodyText]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")

        return text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.split(separator: " ").count >= 5 }
    }

    private static func trimmed(_ sentence: String) -> String {
        guard sentence.count > 220 else { return sentence }
        return String(sentence.prefix(217)) + "…"
    }
}
