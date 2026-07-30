import Foundation

/// The article-level estimate. `N/A` is a first-class answer covering nonpolitical
/// reporting, insufficient text, and calibrated abstention — never a placeholder.
public enum BiasLabel: String, Codable, Equatable, Sendable, CaseIterable {
    case left
    case center
    case right
    case notApplicable

    public var displayName: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        case .notApplicable: return "N/A"
        }
    }

    public var accessibilityDescription: String {
        switch self {
        case .left: return "Left leaning"
        case .center: return "Center"
        case .right: return "Right leaning"
        case .notApplicable: return "Not applicable"
        }
    }

    /// Tolerant parse for model output, which may answer `Left`, `not_applicable`,
    /// or `N/A` regardless of the schema it was given.
    public init?(modelToken: String) {
        let normalized = modelToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "left", "leftleaning", "leftofcenter": self = .left
        case "center", "centre", "neutral", "balanced": self = .center
        case "right", "rightleaning", "rightofcenter": self = .right
        case "notapplicable", "na", "n/a", "none", "nonpolitical", "unknown": self = .notApplicable
        default: return nil
        }
    }
}

public enum BiasConfidence: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high

    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    public init(score: Double) {
        switch score {
        case ..<0.5: self = .low
        case ..<0.75: self = .medium
        default: self = .high
        }
    }
}

/// A verbatim span from the sanitized model input that supports the estimate.
public struct BiasEvidence: Codable, Equatable, Sendable, Identifiable {
    public let excerpt: String
    public var id: String { excerpt }

    public init(excerpt: String) {
        self.excerpt = excerpt
    }
}

/// Which local engine produced an estimate. This is never inferred or assumed:
/// an analyzer sets it only after it has actually run.
public enum BiasEngine: String, Codable, Equatable, Sendable {
    /// Apple's on-device system language model via the Foundation Models framework.
    case appleFoundationModels
    /// A deterministic, rule-based heuristic used for bundled demo journalism,
    /// previews, and tests. It is not machine learning and must never be
    /// presented as such.
    case deterministicFixture

    public var displayName: String {
        switch self {
        case .appleFoundationModels: return "Apple Foundation Models"
        case .deterministicFixture: return "Broadsheet fixture heuristic"
        }
    }

    public var disclosure: String {
        switch self {
        case .appleFoundationModels:
            return "Analyzed privately on this device by Apple's on-device system language model. Nothing was sent to a server."
        case .deterministicFixture:
            return "Computed on this device by a deterministic rule-based heuristic used for bundled demo journalism. This is not machine learning and not an AI judgement."
        }
    }

    public var isMachineLearning: Bool {
        self == .appleFoundationModels
    }
}

public struct BiasProvenance: Codable, Equatable, Sendable {
    public let engine: BiasEngine
    public let modelVersion: String
    /// Always true. Broadsheet has no remote inference path; the field exists so the
    /// reader can state it rather than the UI asserting it independently.
    public let analyzedOnDevice: Bool

    public init(engine: BiasEngine, modelVersion: String, analyzedOnDevice: Bool = true) {
        self.engine = engine
        self.modelVersion = modelVersion
        self.analyzedOnDevice = analyzedOnDevice
    }
}

public struct BiasAnalysisResult: Codable, Equatable, Sendable {
    public let label: BiasLabel
    public let confidenceScore: Double
    public let rationale: String
    public let evidence: [BiasEvidence]
    public let provenance: BiasProvenance

    public init(
        label: BiasLabel,
        confidenceScore: Double,
        rationale: String,
        evidence: [BiasEvidence],
        provenance: BiasProvenance
    ) {
        self.label = label
        self.confidenceScore = min(max(confidenceScore, 0), 1)
        self.rationale = rationale
        self.evidence = evidence
        self.provenance = provenance
    }

    public var confidence: BiasConfidence {
        BiasConfidence(score: confidenceScore)
    }
}

public enum BiasAnalysisError: Error, Equatable, LocalizedError {
    /// The local model could not run. The reason is surfaced verbatim; the app
    /// never substitutes a fabricated estimate.
    case localModelUnavailable(reason: String)
    case insufficientArticleContent
    case generationFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .localModelUnavailable(let reason):
            return reason
        case .insufficientArticleContent:
            return "There was not enough article text to analyze."
        case .generationFailed(let reason):
            return reason
        }
    }
}

/// What the feed and reader show while eager analysis is in flight or has failed.
public enum BiasAnalysisState: Equatable, Sendable {
    case pending
    case analyzing
    case analyzed(BiasAnalysisResult)
    case unavailable(reason: String)

    public var result: BiasAnalysisResult? {
        if case .analyzed(let result) = self { return result }
        return nil
    }
}
