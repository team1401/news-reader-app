import SwiftData
import XCTest
@testable import Broadsheet

/// A real-network smoke check against the four verified starter feeds.
///
/// This target is deliberately **not** part of the `Broadsheet` scheme's test
/// action, so the offline suite never depends on four publishers being up. Run it
/// on purpose:
///
/// ```
/// xcodebuild test -scheme BroadsheetNetworkSmokeTests \
///   -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
/// ```
///
/// It asserts only what a live feed can honestly guarantee: that it is reachable
/// over HTTPS, that it parses, and that it yields items with titles and links.
/// It never asserts on a headline, because the news changes.
final class LiveFeedSmokeTests: XCTestCase {

    func testEveryStarterFeedIsReachableAndParses() async throws {
        let transport = URLSessionHTTPTransport()

        for starter in StarterSources.all {
            let response: HTTPFetchResult
            do {
                response = try await transport.fetch(starter.feedURL, accept: HTTPAccept.feed, limits: .feed)
            } catch {
                XCTFail("\(starter.title) (\(starter.feedURL)) could not be fetched: \(error)")
                continue
            }

            XCTAssertEqual(response.statusCode, 200, "\(starter.title)")
            XCTAssertEqual(response.finalURL.scheme, "https", "\(starter.title) must stay on HTTPS")

            let feed: ParsedFeed
            do {
                feed = try FeedDocumentParser.parse(
                    response.data,
                    contentType: response.mimeType,
                    feedURL: response.finalURL
                )
            } catch {
                XCTFail("\(starter.title) did not parse: \(error)")
                continue
            }

            XCTAssertFalse(feed.items.isEmpty, "\(starter.title) returned no items")
            XCTAssertFalse(feed.channelTitle.isEmpty, "\(starter.title) has no channel title")
            XCTAssertTrue(
                feed.items.allSatisfy { !$0.title.isEmpty },
                "\(starter.title) returned an item with no title"
            )
            XCTAssertGreaterThan(
                feed.items.filter { $0.link != nil }.count,
                feed.items.count / 2,
                "\(starter.title) returned mostly unlinked items"
            )

            print("""
            SMOKE \(starter.title)
              url: \(starter.feedURL.absoluteString)
              status: \(response.statusCode) · \(response.data.count) bytes · \(response.redirectCount) redirects
              format: \(feed.format.displayName)
              channel: \(feed.channelTitle)
              items: \(feed.items.count)
              first: \(feed.items.first?.title ?? "—")
              firstLink: \(feed.items.first?.link?.absoluteString ?? "—")
            """)
        }
    }

    /// The whole pipeline against the live feeds: fetch, parse, canonicalize,
    /// deduplicate, resolve (honouring robots.txt), and persist.
    @MainActor
    func testLiveRefreshPersistsArticlesFromAllFourStarterSources() async throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let store = BroadsheetStore(container: container)
        store.seedStarterSourcesIfNeeded()

        let transport = URLSessionHTTPTransport()
        let analysis = BiasAnalysisService()
        let service = FeedRefreshService(
            store: store,
            transport: transport,
            resolver: ArticleResolver(transport: transport, robots: RobotsPolicy(transport: transport)),
            analysis: analysis
        )

        let report = await service.refresh(sources: store.enabledSources())

        for outcome in report.outcomes {
            print("SMOKE REFRESH \(outcome.sourceTitle): \(outcome.status.rawValue) · \(outcome.itemCount) items · \(outcome.errorMessage ?? "no error")")
        }

        XCTAssertEqual(report.outcomes.count, 4)
        XCTAssertTrue(report.failures.isEmpty, "Failures: \(report.failures.map { "\($0.sourceTitle): \($0.errorMessage ?? "")" })")
        XCTAssertGreaterThan(store.articleCount(), 0)

        var statusCounts: [String: Int] = [:]
        for article in store.articles() {
            XCTAssertEqual(article.contentSource, .liveFeed)
            XCTAssertFalse(article.title.isEmpty)
            let key: String
            switch article.extraction {
            case .full: key = "full"
            case .partial: key = "partial"
            case .feedOnly: key = "feedOnly"
            case .excerptOnly: key = "excerptOnly"
            case .paywalled: key = "paywalled"
            case .failed: key = "failed"
            }
            statusCounts[key, default: 0] += 1
        }
        print("SMOKE EXTRACTION \(statusCounts.sorted { $0.key < $1.key })")

        // Live analysis provenance: whatever the on-device model did, it must not
        // have been the fixture heuristic.
        var analysisCounts: [String: Int] = [:]
        var unavailableReasons: [String: Int] = [:]
        for article in store.articles() {
            switch analysis.state(for: article) {
            case .analyzed(let result):
                XCTAssertEqual(result.provenance.engine, .appleFoundationModels)
                analysisCounts[result.label.displayName, default: 0] += 1
            case .unavailable(let reason):
                analysisCounts["unavailable", default: 0] += 1
                unavailableReasons[String(reason.prefix(90)), default: 0] += 1
            case .pending, .analyzing:
                analysisCounts["pending", default: 0] += 1
            }
        }
        print("SMOKE MODEL availability: \(analysis.localModelAvailabilityDescription)")
        print("SMOKE ANALYSIS \(analysisCounts.sorted { $0.key < $1.key })")
        for (reason, count) in unavailableReasons.sorted(by: { $0.value > $1.value }) {
            print("SMOKE ANALYSIS unavailable ×\(count): \(reason)")
        }
    }
}
