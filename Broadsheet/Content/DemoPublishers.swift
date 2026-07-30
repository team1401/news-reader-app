import Foundation

/// Publishers used by the bundled demo edition.
///
/// Every name, domain, and rating here is invented for development. All domains
/// use the reserved `.example` TLD so nothing can resolve, and no real newsroom,
/// reporter, wire service, or ratings organisation is named or imitated.
public enum DemoPublishers {
    /// The fictional rating provider shown beside publisher baselines, so the demo
    /// never implies a real organisation rated a real outlet.
    public static let ratingProvider = "Broadsheet demo ratings (fictional)"

    static let ratingDate = Date(timeIntervalSince1970: 1_772_000_000) // 25 Feb 2026

    private static func baseline(_ rating: String) -> PublisherBaseline {
        PublisherBaseline(rating: rating, provider: ratingProvider, asOf: ratingDate)
    }

    public static let meridianWire = Publisher(
        id: "meridianwire.example",
        name: "Meridian Wire",
        domain: "meridianwire.example",
        baseline: baseline("Center")
    )

    public static let deltaReview = Publisher(
        id: "deltareview.example",
        name: "The Delta Review",
        domain: "deltareview.example",
        baseline: baseline("Center-Left")
    )

    public static let northgateJournal = Publisher(
        id: "northgatejournal.example",
        name: "Northgate Journal",
        domain: "northgatejournal.example",
        baseline: baseline("Center-Right")
    )

    public static let basinPublicRadio = Publisher(
        id: "basinpublicradio.example",
        name: "Basin Public Radio",
        domain: "basinpublicradio.example",
        baseline: baseline("Center")
    )

    public static let harborAndMain = Publisher(
        id: "harborandmain.example",
        name: "Harbor & Main",
        domain: "harborandmain.example",
        baseline: baseline("Left")
    )

    public static let ninthStreetDispatch = Publisher(
        id: "ninthstreet.example",
        name: "Ninth Street Dispatch",
        domain: "ninthstreet.example",
        baseline: baseline("Right")
    )

    public static let cascadeLedger = Publisher(
        id: "cascadeledger.example",
        name: "Cascade Ledger",
        domain: "cascadeledger.example",
        baseline: baseline("Center")
    )

    public static let all: [Publisher] = [
        meridianWire, deltaReview, northgateJournal, basinPublicRadio,
        harborAndMain, ninthStreetDispatch, cascadeLedger
    ]
}

/// How a publisher's externally sourced baseline maps onto the coverage strip.
/// Kept separate from ``BiasLabel`` so a source rating is never rendered as, or
/// aggregated with, an article estimate.
public enum BaselineBucket: String, CaseIterable, Sendable {
    case left
    case centerLeft
    case center
    case centerRight
    case right
    case unrated

    public var displayName: String {
        switch self {
        case .left: return "Left"
        case .centerLeft: return "Center-Left"
        case .center: return "Center"
        case .centerRight: return "Center-Right"
        case .right: return "Right"
        case .unrated: return "Not rated"
        }
    }

    public init(rating: String?) {
        switch rating?.lowercased() {
        case "left": self = .left
        case "center-left", "left-center": self = .centerLeft
        case "center", "centre": self = .center
        case "center-right", "right-center": self = .centerRight
        case "right": self = .right
        default: self = .unrated
        }
    }
}
