import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Guided-generation schema for the on-device system language model.
///
/// The leaning is constrained with `anyOf`, so decoding is limited to the four
/// permitted answers instead of relying on the model to format free text.
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "An article-level political leaning estimate derived only from the supplied text.")
struct GeneratedLeanEstimate {
    @Guide(description: "The political leaning of the supplied article text.", .anyOf(["left", "center", "right", "notApplicable"]))
    var leaning: String

    @Guide(description: "Confidence in the leaning, from 0.0 for a guess to 1.0 for certain.", .range(0.0...1.0))
    var confidence: Double

    @Guide(description: "One or two sentences explaining the estimate, referring only to the supplied text.")
    var rationale: String

    @Guide(description: "Short verbatim excerpts copied from the supplied text that support the estimate.", .count(1...3))
    var evidence: [String]
}
#endif

/// Runs Apple's on-device system language model as a local article-lean judge.
///
/// It never fabricates a result. If the framework is missing at compile time, the
/// OS is older than iOS 26, or the system model reports itself unavailable, it
/// throws ``BiasAnalysisError/localModelUnavailable(reason:)`` and the UI says the
/// analysis could not run.
public struct FoundationModelsBiasAnalyzer: BiasAnalyzing {
    public static let version = "apple-system-lm+broadsheet-prompt-1.0"

    /// The prompt that has actually been measured against live reporting.
    ///
    /// A reframing — asking for a description of how a passage is written rather
    /// than for a political judgement — is the obvious next experiment, because in
    /// the measured run the system model refused 55 of 82 live articles. It is not
    /// shipped here: the simulator lost its model assets before it could be
    /// measured, and an unmeasured prompt change is not an improvement.
    private static let instructions = """
    You are a media-analysis function that estimates the political leaning of a \
    single news article from its text alone.

    Rules:
    - Judge only the supplied text. You are never told the publisher, outlet, \
      domain, author, or any source rating, and you must not guess them.
    - Answer "left" or "right" only when the article's own framing, word choice, \
      or selection of voices leans that way.
    - Answer "center" when political subject matter is covered without a \
      discernible lean.
    - Answer "notApplicable" when the text is not political, or there is too \
      little of it to judge.
    - Quote evidence verbatim from the supplied text. Never invent a quotation.
    - This is an estimate of framing, not a verdict about truth or quality.
    """

    public init() {}

    public var engine: BiasEngine { .appleFoundationModels }

    #if canImport(FoundationModels)
    /// The model configured for content transformation.
    ///
    /// News is about conflict, crime, disaster, and politics, so the default
    /// guardrail rejects most real reporting outright — in one live run against the
    /// four starter feeds it refused 55 of 82 articles. Apple provides
    /// `permissiveContentTransformations` for exactly this shape of work: text the
    /// user chose to bring into the app, being analyzed rather than generated. It
    /// changes what the model will *read*, not what Broadsheet will *show*: output
    /// is still constrained to four labels, evidence is still checked verbatim
    /// against the supplied text, and nothing is written that the article did not
    /// say.
    @available(iOS 26.0, macOS 26.0, *)
    private static var model: SystemLanguageModel {
        SystemLanguageModel(guardrails: .permissiveContentTransformations)
    }
    #endif

    public var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return Self.model.availability == .available
        }
        return false
        #else
        return false
        #endif
    }

    public var availabilityDescription: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch Self.model.availability {
            case .available:
                return "Apple's on-device system language model is ready."
            case .unavailable(.deviceNotEligible):
                return "This device does not support Apple Intelligence, so the on-device language model cannot run."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence is turned off. Enable it in Settings to analyze articles with the on-device language model."
            case .unavailable(.modelNotReady):
                return "The on-device language model is still downloading or preparing. Analysis will resume once it is ready."
            case .unavailable:
                return "The on-device language model is unavailable for an unrecognized reason."
            }
        }
        return "The on-device language model requires iOS 26 or later. This device is running an earlier version."
        #else
        return "This build was compiled without the Foundation Models framework, so no on-device language model is available."
        #endif
    }

    public func analyze(_ input: BiasModelInput) async throws -> BiasAnalysisResult {
        guard input.hasSufficientContent else {
            throw BiasAnalysisError.insufficientArticleContent
        }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw BiasAnalysisError.localModelUnavailable(reason: availabilityDescription)
        }
        guard Self.model.availability == .available else {
            throw BiasAnalysisError.localModelUnavailable(reason: availabilityDescription)
        }
        return try await runSystemModel(input)
        #else
        throw BiasAnalysisError.localModelUnavailable(reason: availabilityDescription)
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func runSystemModel(_ input: BiasModelInput) async throws -> BiasAnalysisResult {
        let session = LanguageModelSession(model: Self.model, instructions: Self.instructions)
        let options = GenerationOptions(temperature: 0.0)

        let prompt = """
        Estimate the political leaning of the following article text.

        <article>
        \(input.promptText)
        </article>
        """

        let estimate: GeneratedLeanEstimate
        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedLeanEstimate.self,
                options: options
            )
            estimate = response.content
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .assetsUnavailable:
                throw BiasAnalysisError.localModelUnavailable(reason: availabilityDescription)
            case .exceededContextWindowSize:
                throw BiasAnalysisError.generationFailed(
                    reason: "The article was too long for the on-device model's context window."
                )
            case .guardrailViolation:
                // Said plainly, because "detected content likely to be unsafe" tells
                // the reader nothing about their own newspaper.
                throw BiasAnalysisError.generationFailed(
                    reason: "Apple's on-device model declined to analyze this article's subject matter, so Broadsheet has no estimate for it."
                )
            case .unsupportedLanguageOrLocale:
                throw BiasAnalysisError.generationFailed(
                    reason: "The on-device model does not support this article's language."
                )
            case .refusal:
                throw BiasAnalysisError.generationFailed(
                    reason: "Apple's on-device model declined to classify this article, so Broadsheet has no estimate for it."
                )
            case .rateLimited, .concurrentRequests:
                throw BiasAnalysisError.generationFailed(
                    reason: "The on-device model was busy. Analysis will be retried on the next refresh."
                )
            default:
                // `GenerationError` does not always carry a useful description, and
                // "the operation couldn't be completed" is not a diagnosis. Name the
                // case so a failure is at least traceable.
                throw BiasAnalysisError.generationFailed(
                    reason: "The on-device model could not complete the analysis (\(Self.caseName(of: error)))."
                )
            }
        } catch {
            // The framework sometimes surfaces a generation failure as a bridged
            // `NSError` whose domain is the Swift type name, in which case the
            // `as` cast above misses it and `localizedDescription` is the useless
            // "the operation couldn't be completed". Report something traceable.
            let nsError = error as NSError
            if nsError.domain.contains("GenerationError") {
                throw BiasAnalysisError.generationFailed(
                    reason: "Apple's on-device model could not complete the analysis on this device (\(nsError.domain.components(separatedBy: ".").last ?? nsError.domain) \(nsError.code))."
                )
            }
            throw BiasAnalysisError.generationFailed(reason: error.localizedDescription)
        }

        // A label we cannot decode is an abstention, not a guess.
        let label = BiasLabel(modelToken: estimate.leaning) ?? .notApplicable

        // Evidence must be quoted from the text we supplied. Anything else is
        // dropped rather than shown to the reader as an article excerpt.
        let verified = estimate.evidence
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && Self.appearsVerbatim($0, in: input.promptText) }
            .map { BiasEvidence(excerpt: $0) }

        return BiasAnalysisResult(
            label: label,
            confidenceScore: estimate.confidence,
            rationale: estimate.rationale.trimmingCharacters(in: .whitespacesAndNewlines),
            evidence: verified,
            provenance: BiasProvenance(
                engine: .appleFoundationModels,
                modelVersion: Self.version
            )
        )
    }
    #endif

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    static func caseName(of error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize: return "context window exceeded"
        case .assetsUnavailable: return "model assets unavailable"
        case .guardrailViolation: return "guardrail violation"
        case .unsupportedGuide: return "unsupported guide"
        case .unsupportedLanguageOrLocale: return "unsupported language"
        case .decodingFailure: return "decoding failure"
        case .rateLimited: return "rate limited"
        case .concurrentRequests: return "concurrent requests"
        case .refusal: return "model refusal"
        @unknown default: return "unrecognised error"
        }
    }
    #endif

    /// Compares on collapsed whitespace so a model that reflows a quotation still
    /// matches, while an invented quotation does not.
    static func appearsVerbatim(_ excerpt: String, in source: String) -> Bool {
        let normalizedExcerpt = HTMLTextNormalizer.collapseWhitespace(in: excerpt)
            .trimmingCharacters(in: CharacterSet(charactersIn: "“”\"' "))
        guard normalizedExcerpt.count >= 12 else { return false }
        let normalizedSource = HTMLTextNormalizer.collapseWhitespace(in: source)
        return normalizedSource.range(of: normalizedExcerpt, options: [.caseInsensitive]) != nil
    }
}
