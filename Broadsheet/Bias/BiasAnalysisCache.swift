import Foundation

/// Caches analysis by article identity so a label computed during refresh is the
/// same label the reader shows when the story opens.
///
/// Concurrent requests for the same article share one computation: a second caller
/// awaits the first task rather than starting a duplicate inference.
public actor BiasAnalysisCache {
    public struct Key: Hashable, Sendable {
        public let articleID: ArticleID
        /// Cached results are invalidated when the engine or version changes.
        public let engine: BiasEngine
        public let modelVersion: String

        public init(articleID: ArticleID, engine: BiasEngine, modelVersion: String) {
            self.articleID = articleID
            self.engine = engine
            self.modelVersion = modelVersion
        }
    }

    private var stored: [Key: BiasAnalysisResult] = [:]
    private var inFlight: [Key: Task<BiasAnalysisResult, Error>] = [:]

    public init() {}

    public var count: Int { stored.count }

    public func cachedResult(for key: Key) -> BiasAnalysisResult? {
        stored[key]
    }

    public func insert(_ result: BiasAnalysisResult, for key: Key) {
        stored[key] = result
    }

    public func removeAll() {
        stored.removeAll()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
    }

    /// Returns the cached result, or runs `compute` exactly once for this key.
    public func result(
        for key: Key,
        compute: @Sendable @escaping () async throws -> BiasAnalysisResult
    ) async throws -> BiasAnalysisResult {
        if let stored = stored[key] {
            return stored
        }
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task<BiasAnalysisResult, Error> { try await compute() }
        inFlight[key] = task

        do {
            let result = try await task.value
            inFlight[key] = nil
            stored[key] = result
            return result
        } catch {
            inFlight[key] = nil
            // Failures are not cached: an unavailable model may become available.
            throw error
        }
    }
}
