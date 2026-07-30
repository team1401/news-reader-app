import Foundation

/// The app's only outbound network path.
///
/// HTTPS is enforced on the original request *and* on every redirect hop, the body
/// is abandoned mid-stream the moment it exceeds the limit rather than after it has
/// been buffered, and the user agent says plainly what is asking.
public final class URLSessionHTTPTransport: NSObject, HTTPTransport, @unchecked Sendable {
    /// Identifies the client honestly, so a publisher reading their logs sees a
    /// personal reader rather than an anonymous scraper.
    public static let userAgent = "Broadsheet/1.0 (private beta; personal on-device news reader; RSS/Atom/JSON Feed)"

    private let session: URLSession

    public init(configuration: URLSessionConfiguration = URLSessionHTTPTransport.defaultConfiguration()) {
        self.session = URLSession(configuration: configuration)
        super.init()
    }

    public static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadRevalidatingCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.waitsForConnectivity = false
        return configuration
    }

    /// Test seam: the same transport driven through a `URLProtocol` stub.
    public static func forTesting(protocolClasses: [AnyClass]) -> URLSessionHTTPTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = protocolClasses
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSessionHTTPTransport(configuration: configuration)
    }

    public func fetch(_ url: URL, accept: String, limits: HTTPFetchLimits) async throws -> HTTPFetchResult {
        try URLSessionHTTPTransport.validateHTTPS(url)

        var request = URLRequest(url: url, timeoutInterval: limits.timeout)
        request.httpMethod = "GET"
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(URLSessionHTTPTransport.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false

        let collector = ResponseCollector(
            requestedURL: url,
            byteLimit: limits.maximumBytes,
            redirectLimit: limits.maximumRedirects
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                task.delegate = collector
                collector.begin(task: task, continuation: continuation)
            }
        } onCancel: {
            collector.cancel()
        }
    }

    static func validateHTTPS(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased() else {
            throw HTTPFetchError.unsupportedURL(url.absoluteString)
        }
        guard scheme == "https" else {
            throw HTTPFetchError.insecureScheme(scheme: scheme)
        }
        guard let host = url.host, !host.isEmpty else {
            throw HTTPFetchError.unsupportedURL(url.absoluteString)
        }
    }

    static func mapped(_ error: any Error) -> HTTPFetchError {
        if let fetchError = error as? HTTPFetchError { return fetchError }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return .transportFailure(nsError.localizedDescription)
        }
        switch nsError.code {
        case NSURLErrorTimedOut:
            return .timedOut
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed:
            return .notConnected
        case NSURLErrorCancelled:
            return .cancelled
        case NSURLErrorHTTPTooManyRedirects:
            return .tooManyRedirects(limit: 5)
        case NSURLErrorUnsupportedURL, NSURLErrorBadURL:
            return .unsupportedURL(nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String ?? "")
        default:
            return .transportFailure(nsError.localizedDescription)
        }
    }
}

/// Collects one response under a byte cap and a redirect cap.
///
/// Delegate callbacks arrive on the session's serial delegate queue, but the
/// cancellation handler can race them, so the small amount of shared state is
/// locked and the continuation is resumed exactly once.
final class ResponseCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let requestedURL: URL
    private let byteLimit: Int
    private let redirectLimit: Int

    private let lock = NSLock()
    private var data = Data()
    private var response: HTTPURLResponse?
    private var redirectCount = 0
    private var refusal: HTTPFetchError?
    private var continuation: CheckedContinuation<HTTPFetchResult, any Error>?
    private var task: URLSessionTask?
    private var isFinished = false

    init(requestedURL: URL, byteLimit: Int, redirectLimit: Int) {
        self.requestedURL = requestedURL
        self.byteLimit = byteLimit
        self.redirectLimit = redirectLimit
    }

    func begin(task: URLSessionTask, continuation: CheckedContinuation<HTTPFetchResult, any Error>) {
        lock.lock()
        self.task = task
        self.continuation = continuation
        let alreadyCancelled = isFinished
        lock.unlock()

        if alreadyCancelled {
            finish(.failure(HTTPFetchError.cancelled))
        } else {
            task.resume()
        }
    }

    func cancel() {
        lock.lock()
        refusal = refusal ?? .cancelled
        let running = task
        lock.unlock()
        running?.cancel()
    }

    private func finish(_ result: Result<HTTPFetchResult, any Error>) {
        lock.lock()
        guard !isFinished, let continuation else {
            isFinished = true
            lock.unlock()
            return
        }
        isFinished = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }

    // MARK: URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            lock.lock(); refusal = .transportFailure("The server did not return an HTTP response."); lock.unlock()
            completionHandler(.cancel)
            return
        }

        // Refuse an oversized body before reading it when the server declares one.
        if http.expectedContentLength > 0, http.expectedContentLength > Int64(byteLimit) {
            lock.lock(); refusal = .responseTooLarge(limit: byteLimit); lock.unlock()
            completionHandler(.cancel)
            return
        }

        lock.lock(); self.response = http; lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        self.data.append(data)
        let overLimit = self.data.count > byteLimit
        if overLimit { refusal = .responseTooLarge(limit: byteLimit) }
        lock.unlock()

        if overLimit { dataTask.cancel() }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        redirectCount += 1
        let count = redirectCount
        lock.unlock()

        guard count <= redirectLimit else {
            lock.lock(); refusal = .tooManyRedirects(limit: redirectLimit); lock.unlock()
            completionHandler(nil)
            task.cancel()
            return
        }
        guard let url = request.url else {
            lock.lock(); refusal = .unsupportedURL(""); lock.unlock()
            completionHandler(nil)
            task.cancel()
            return
        }
        guard url.scheme?.lowercased() == "https" else {
            lock.lock(); refusal = .insecureRedirect(to: url.absoluteString); lock.unlock()
            completionHandler(nil)
            task.cancel()
            return
        }

        var followed = request
        followed.setValue(URLSessionHTTPTransport.userAgent, forHTTPHeaderField: "User-Agent")
        followed.httpShouldHandleCookies = false
        completionHandler(followed)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        let refusal = self.refusal
        let response = self.response
        let body = self.data
        let redirects = self.redirectCount
        lock.unlock()

        // A refusal is more informative than the cancellation it caused.
        if let refusal {
            finish(.failure(refusal))
            return
        }
        if let error {
            finish(.failure(URLSessionHTTPTransport.mapped(error)))
            return
        }
        guard let response else {
            finish(.failure(HTTPFetchError.transportFailure("The server did not return an HTTP response.")))
            return
        }
        guard (200..<300).contains(response.statusCode) else {
            finish(.failure(HTTPFetchError.httpStatus(
                code: response.statusCode,
                url: (response.url ?? requestedURL).absoluteString
            )))
            return
        }
        guard !body.isEmpty else {
            finish(.failure(HTTPFetchError.emptyResponse))
            return
        }

        finish(.success(HTTPFetchResult(
            data: body,
            finalURL: response.url ?? requestedURL,
            statusCode: response.statusCode,
            mimeType: response.mimeType,
            textEncodingName: response.textEncodingName,
            redirectCount: redirects
        )))
    }
}
