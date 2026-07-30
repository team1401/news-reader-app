import SwiftUI

/// The article-level estimate, shown on every story card and at the top of the
/// reader. It is a control, not decoration: tapping it opens provenance.
public struct BiasCapsule: View {
    public enum Size {
        case compact
        case prominent
    }

    let state: BiasAnalysisState
    var size: Size = .compact

    public init(state: BiasAnalysisState, size: Size = .compact) {
        self.state = state
        self.size = size
    }

    private var label: String {
        switch state {
        case .analyzed(let result): return result.label.displayName
        case .analyzing: return "Analyzing"
        case .pending: return "Queued"
        case .unavailable: return "No estimate"
        }
    }

    private var colors: (foreground: Color, background: Color) {
        switch state {
        case .analyzed(let result): return BSColor.lean(result.label)
        case .analyzing, .pending: return BSColor.lean(.notApplicable)
        case .unavailable: return BSColor.lean(.notApplicable)
        }
    }

    private var symbol: String {
        switch state {
        case .analyzed: return "iphone.gen3"
        case .analyzing, .pending: return "ellipsis"
        case .unavailable: return "exclamationmark.triangle"
        }
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: size == .prominent ? 11 : 9, weight: .bold))
            Text(label.uppercased())
                .font(.system(size: size == .prominent ? 12 : 11, weight: .bold))
                .tracking(0.5)
        }
        .foregroundStyle(colors.foreground)
        .padding(.horizontal, size == .prominent ? 10 : 7)
        .padding(.vertical, size == .prominent ? 5 : 3)
        .background(colors.background, in: RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(colors.foreground.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Shows how this estimate was produced, its evidence, and a correction control.")
    }

    private var accessibilityLabel: String {
        switch state {
        case .analyzed(let result):
            return "On-device article estimate: \(result.label.accessibilityDescription), \(result.confidence.displayName.lowercased()) confidence"
        case .analyzing:
            return "Analyzing this article on this device"
        case .pending:
            return "Article estimate queued"
        case .unavailable:
            return "No on-device article estimate is available"
        }
    }
}

/// The publisher's externally sourced baseline. Deliberately quieter than the
/// article estimate, and never merged with it.
public struct PublisherBaselineChip: View {
    let baseline: PublisherBaseline?

    public init(baseline: PublisherBaseline?) {
        self.baseline = baseline
    }

    public var body: some View {
        if let baseline {
            Text("Pub: \(baseline.rating)")
                .font(.system(size: 11))
                .foregroundStyle(BSColor.textTertiary)
                .accessibilityLabel("Publisher baseline: \(baseline.rating), from \(baseline.provider)")
        }
    }
}

/// Distribution of publisher baselines across a cluster's sources.
public struct CoverageBaselineStrip: View {
    let distribution: [(bucket: BaselineBucket, count: Int)]

    public init(distribution: [(bucket: BaselineBucket, count: Int)]) {
        self.distribution = distribution
    }

    private var total: Int {
        max(1, distribution.reduce(0) { $0 + $1.count })
    }

    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(distribution, id: \.bucket) { entry in
                    BSColor.baseline(entry.bucket)
                        .frame(width: max(3, proxy.size.width * CGFloat(entry.count) / CGFloat(total) - 2))
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let parts = distribution.map { "\($0.count) \($0.bucket.displayName)" }
        return "Coverage by publisher baseline: " + parts.joined(separator: ", ")
    }
}

/// Renders a hero or inline figure with its caption and credit.
///
/// Publisher photography is never tinted or warmed; only the surrounding surface
/// changes with the theme.
public struct ArticleFigure: View {
    let image: ArticleImage
    var showsCaption: Bool = true

    public init(image: ArticleImage, showsCaption: Bool = true) {
        self.image = image
        self.showsCaption = showsCaption
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.s2) {
            artwork
                .aspectRatio(image.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                // The drawing itself is hidden from assistive technology, so the
                // figure republishes it as one element carrying the alt text.
                .accessibilityElement()
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel(image.altText)

            if showsCaption, image.caption != nil || image.credit != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let caption = image.caption {
                        Text(caption)
                            .font(.system(size: 12))
                            .foregroundStyle(BSColor.textSecondary)
                    }
                    if let credit = image.credit {
                        Text(credit)
                            .font(.system(size: 11))
                            .foregroundStyle(BSColor.textTertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let artwork = image.artwork {
            EditorialArtworkView(artwork)
        } else if let remoteURL = image.remoteURL {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let loaded):
                    loaded.resizable().scaledToFill()
                case .failure:
                    placeholder(symbol: "photo.badge.exclamationmark")
                default:
                    placeholder(symbol: "photo")
                }
            }
        } else {
            placeholder(symbol: "photo")
        }
    }

    private func placeholder(symbol: String) -> some View {
        ZStack {
            BSColor.bgSunk
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(BSColor.textTertiary)
        }
    }
}

/// States the app's honest position when extraction was incomplete.
public struct ExtractionNotice: View {
    let status: ExtractionStatus

    public init(status: ExtractionStatus) {
        self.status = status
    }

    public var body: some View {
        if let disclosure = status.disclosure {
            HStack(alignment: .top, spacing: BSSpacing.s2) {
                Image(systemName: "info.circle")
                    .font(.footnote)
                Text(disclosure)
                    .font(.footnote)
            }
            .foregroundStyle(BSColor.textSecondary)
            .padding(BSSpacing.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BSColor.bgSunk, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
