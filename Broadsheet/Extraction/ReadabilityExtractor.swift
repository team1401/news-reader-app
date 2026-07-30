import Foundation
import WebKit

/// Locates resources inside whichever bundle the app code was loaded from. In a
/// hosted unit-test run that is still the app bundle, so the extractor finds the
/// same JavaScript the shipping app uses.
final class BroadsheetBundleToken {}

enum BroadsheetResources {
    static let bundle = Bundle(for: BroadsheetBundleToken.self)

    static func javaScript(named name: String) -> String? {
        guard let url = bundle.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return source
    }
}

/// What extraction produced. Every field came from the supplied DOM.
public struct ExtractedArticle: Equatable, Sendable {
    public let title: String?
    public let byline: String?
    public let excerpt: String?
    public let siteName: String?
    public let publishedAt: Date?
    public let leadImage: ArticleImage?
    public let blocks: [ArticleBlock]
    public let textLength: Int

    public var paragraphCount: Int {
        blocks.filter { if case .paragraph = $0 { return true } else { return false } }.count
    }
}

public enum ArticleExtractionError: Error, Equatable, LocalizedError {
    case scriptsUnavailable
    case webViewFailed(String)
    case javaScriptFailed(String)
    case timedOut
    case noContent(String)

    public var errorDescription: String? {
        switch self {
        case .scriptsUnavailable:
            return "The bundled extraction scripts are missing from this build."
        case .webViewFailed(let message):
            return "The extraction component could not load the page: \(message)"
        case .javaScriptFailed(let message):
            return "Extraction failed: \(message)"
        case .timedOut:
            return "Extraction took too long and was stopped."
        case .noContent(let message):
            return message
        }
    }
}

/// Runs Mozilla Readability inside a deliberately constrained `WKWebView`.
///
/// The web view is not a browser and must never behave like one:
///
/// - It is handed HTML that Broadsheet already fetched. It never navigates.
/// - A `WKContentRuleList` blocks every subresource load, so no image, script,
///   stylesheet, font, or beacon is fetched while the page is parsed. Trackers
///   that would fire in a browser do not fire here.
/// - The data store is non-persistent and cookies are off, so there is no session
///   to reuse and nothing to accumulate.
/// - It never fills a form, dismisses an overlay, or clicks anything. A page that
///   withholds its content simply extracts to nothing, and the reader gets the
///   feed excerpt and a link to the publisher.
@MainActor
public final class ReadabilityExtractor: NSObject {
    public enum Mode: String, Sendable {
        /// Run Readability across a full publisher page.
        case readability
        /// Normalize a publisher-supplied feed content fragment. Readability is
        /// not involved: the feed already told us this *is* the article.
        case fragment
    }

    public static let extractionTimeout: TimeInterval = 20

    private var webView: WKWebView?
    private var ruleList: WKContentRuleList?
    private var loadContinuation: CheckedContinuation<Void, any Error>?
    /// `loadHTMLString` needs exactly one main-frame `.other` navigation to create
    /// its in-memory document. Every later navigation — including `window.location`
    /// from publisher inline JavaScript — is refused.
    private var isAwaitingInitialDocumentNavigation = false
    private let gate = AsyncGate()

    private lazy var readabilitySource = BroadsheetResources.javaScript(named: "Readability")
    private lazy var bridgeSource = BroadsheetResources.javaScript(named: "broadsheet-extract")

    public override init() {
        super.init()
    }

    /// True when the vendored scripts are actually present in the bundle. Used by
    /// the resolver to report an honest reason rather than a silent fallback.
    public var isAvailable: Bool {
        readabilitySource != nil && bridgeSource != nil
    }

    public func extract(html: String, baseURL: URL, mode: Mode = .readability) async throws -> ExtractedArticle {
        await gate.wait()
        defer { Task { await gate.signal() } }

        guard let readabilitySource, let bridgeSource else {
            throw ArticleExtractionError.scriptsUnavailable
        }

        let webView = try await preparedWebView()
        try await load(html: html, baseURL: baseURL, in: webView)

        if mode == .readability {
            _ = try await evaluate(readabilitySource, in: webView)
        }
        _ = try await evaluate(bridgeSource, in: webView)

        let raw = try await evaluate("window.__broadsheetExtract(\"\(mode.rawValue)\");", in: webView)
        guard let json = raw as? String, let data = json.data(using: .utf8) else {
            throw ArticleExtractionError.javaScriptFailed("The extraction bridge returned no result.")
        }

        let payload: ExtractionPayload
        do {
            payload = try JSONDecoder().decode(ExtractionPayload.self, from: data)
        } catch {
            throw ArticleExtractionError.javaScriptFailed(error.localizedDescription)
        }
        guard payload.ok else {
            throw ArticleExtractionError.noContent(payload.error ?? "No article content was found on the page.")
        }

        return payload.article()
    }

    // MARK: Web view lifecycle

    private func preparedWebView() async throws -> WKWebView {
        if let webView { return webView }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.suppressesIncrementalRendering = true

        if let ruleList = try? await ReadabilityExtractor.blockAllSubresources() {
            self.ruleList = ruleList
            configuration.userContentController.add(ruleList)
        }

        let created = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024), configuration: configuration)
        created.navigationDelegate = self
        created.isInspectable = false
        webView = created
        return created
    }

    /// Blocks every subresource type while still permitting the in-memory document
    /// itself to load.
    static func blockAllSubresources() async throws -> WKContentRuleList? {
        let rules = """
        [{
          "trigger": {
            "url-filter": ".*",
            "resource-type": ["image","style-sheet","script","font","raw","svg-document","media","popup","fetch","websocket","ping","other"]
          },
          "action": { "type": "block" }
        }]
        """
        return try await WKContentRuleListStore.default()?
            .compileContentRuleList(forIdentifier: "broadsheet-block-all", encodedContentRuleList: rules)
    }

    private func load(html: String, baseURL: URL, in webView: WKWebView) async throws {
        isAwaitingInitialDocumentNavigation = true
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    self.loadContinuation = continuation
                    webView.loadHTMLString(html, baseURL: baseURL)
                }
            }
            group.addTask { @MainActor in
                try await Task.sleep(nanoseconds: UInt64(ReadabilityExtractor.extractionTimeout * 1_000_000_000))
                throw ArticleExtractionError.timedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        do {
            return try await webView.evaluateJavaScript(script)
        } catch {
            // WebKit reports "no result" for a script whose last statement is a
            // declaration; that is not a failure.
            let nsError = error as NSError
            if nsError.domain == WKErrorDomain, nsError.code == WKError.javaScriptResultTypeIsUnsupported.rawValue {
                return nil
            }
            throw ArticleExtractionError.javaScriptFailed(nsError.localizedDescription)
        }
    }

    private func finishLoad(_ result: Result<Void, any Error>) {
        isAwaitingInitialDocumentNavigation = false
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        continuation.resume(with: result)
    }
}

extension ReadabilityExtractor: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoad(.success(()))
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finishLoad(.failure(ArticleExtractionError.webViewFailed(error.localizedDescription)))
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        finishLoad(.failure(ArticleExtractionError.webViewFailed(error.localizedDescription)))
    }

    /// The extractor is given HTML directly and must never navigate anywhere. The
    /// first main-frame `.other` action is WebKit creating that in-memory document;
    /// every action after it is refused, regardless of URL or navigation type.
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let isInitialDocument = Self.shouldAllowNavigation(
            isAwaitingInitialDocument: isAwaitingInitialDocumentNavigation,
            isMainFrame: navigationAction.targetFrame?.isMainFrame == true,
            navigationType: navigationAction.navigationType
        )
        if isInitialDocument {
            // Consume the single permit before allowing the action so a re-entrant
            // or immediately scripted navigation cannot reuse it.
            isAwaitingInitialDocumentNavigation = false
        }
        decisionHandler(isInitialDocument ? .allow : .cancel)
    }

    static func shouldAllowNavigation(
        isAwaitingInitialDocument: Bool,
        isMainFrame: Bool,
        navigationType: WKNavigationType
    ) -> Bool {
        isAwaitingInitialDocument && isMainFrame && navigationType == .other
    }
}

/// A one-permit async gate, so only one extraction touches the shared web view at
/// a time even though callers are concurrent.
actor AsyncGate {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

// MARK: - Payload decoding

/// The JSON contract with `broadsheet-extract.js`.
struct ExtractionPayload: Decodable {
    struct Run: Decodable {
        let kind: String
        let text: String
        let url: String?
    }

    struct Block: Decodable {
        let type: String
        let runs: [Run]?
        let text: String?
        let attribution: String?
        let ordered: Bool?
        let items: [[Run]]?
        let url: String?
        let alt: String?
        let caption: String?
        let credit: String?
        let aspectRatio: Double?
    }

    let ok: Bool
    let error: String?
    let title: String?
    let byline: String?
    let excerpt: String?
    let siteName: String?
    let publishedTime: String?
    let leadImage: Block?
    let blocks: [Block]?
    let textLength: Int?

    func article() -> ExtractedArticle {
        ExtractedArticle(
            title: title?.nonEmpty,
            byline: byline?.nonEmpty,
            excerpt: excerpt?.nonEmpty,
            siteName: siteName?.nonEmpty,
            publishedAt: publishedTime.flatMap { FeedDateParser.date(from: $0) },
            leadImage: leadImage.flatMap(ExtractionPayload.image(from:)),
            blocks: (blocks ?? []).compactMap(ExtractionPayload.block(from:)),
            textLength: textLength ?? 0
        )
    }

    static func block(from block: Block) -> ArticleBlock? {
        switch block.type {
        case "paragraph":
            let rich = richText(from: block.runs ?? [])
            return rich.isEmpty ? nil : .paragraph(rich)
        case "heading":
            guard let text = block.text?.nonEmpty else { return nil }
            return .heading(text)
        case "pullQuote":
            guard let text = block.text?.nonEmpty else { return nil }
            return .pullQuote(text: text, attribution: block.attribution?.nonEmpty)
        case "list":
            let items = (block.items ?? []).map(richText(from:)).filter { !$0.isEmpty }
            return items.isEmpty ? nil : .list(ordered: block.ordered ?? false, items: items)
        case "image":
            return image(from: block).map { ArticleBlock.image($0) }
        case "divider":
            return .divider
        default:
            return nil
        }
    }

    static func image(from block: Block) -> ArticleImage? {
        guard let raw = block.url, let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else { return nil }
        let alt = block.alt?.nonEmpty ?? block.caption?.nonEmpty ?? "Publisher photograph"
        return ArticleImage(
            remoteURL: url,
            aspectRatio: block.aspectRatio.flatMap { $0 > 0.2 && $0 < 5 ? $0 : nil } ?? 16.0 / 9.0,
            altText: alt,
            caption: block.caption?.nonEmpty,
            credit: block.credit?.nonEmpty
        )
    }

    static func richText(from runs: [Run]) -> RichText {
        RichText(runs: runs.compactMap { run in
            switch run.kind {
            case "emphasis": return .emphasis(run.text)
            case "strong": return .strong(run.text)
            case "link":
                guard let raw = run.url, let url = URL(string: raw) else { return .plain(run.text) }
                return .link(text: run.text, url: url)
            default: return .plain(run.text)
            }
        })
    }
}

extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
