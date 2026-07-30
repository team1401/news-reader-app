import SwiftUI

enum ArticleTimeFormat {
    static func string(for date: Date, relativeTo now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 * 60 * 12 {
            return date.formatted(.relative(presentation: .named))
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Publisher, article estimate, publisher baseline, time, reading time.
///
/// The article estimate is a button; the baseline is quieter text with its own
/// provenance sheet. They are never combined into a single score.
struct ArticleMetaRow: View {
    let article: ArticleDocument
    let state: BiasAnalysisState
    var showsReadingTime: Bool = true

    @State private var showsAnalysis = false
    @State private var showsBaseline = false
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.s1) {
            HStack(spacing: BSSpacing.s2) {
                Text(article.publisher.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BSColor.textSecondary)

                Button {
                    showsAnalysis = true
                } label: {
                    BiasCapsule(state: state)
                }
                .buttonStyle(.plain)

                Button {
                    showsBaseline = true
                } label: {
                    PublisherBaselineChip(baseline: article.publisher.baseline)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: BSSpacing.s1) {
                Text(ArticleTimeFormat.string(for: article.publishedAt))
                if showsReadingTime {
                    Text("·")
                    Text("\(article.readingTimeMinutes) min read")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(BSColor.textTertiary)
        }
        .sheet(isPresented: $showsAnalysis) {
            PerspectiveDetailSheet(article: article, state: state)
                .environment(model)
        }
        .sheet(isPresented: $showsBaseline) {
            BaselineProvenanceSheet(publisher: article.publisher)
        }
    }
}

struct Kicker: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(BSColor.accent)
    }
}

/// The lead: full-width art, then the story, with varied hierarchy rather than a
/// card identical to everything below it.
struct LeadStoryCard: View {
    let article: ArticleDocument
    let state: BiasAnalysisState

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.s3) {
            if let hero = article.heroImage {
                ArticleFigure(image: hero, showsCaption: false)
            }

            if let kicker = article.kicker {
                Kicker(text: kicker)
            }

            Text(article.title)
                .font(BSFont.leadHeadline)
                .foregroundStyle(BSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let dek = article.dek {
                Text(dek)
                    .font(BSFont.dek)
                    .foregroundStyle(BSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ArticleMetaRow(article: article, state: state)
        }
    }
}

/// River rows alternate between three shapes so the feed reads as an editorial
/// river rather than a stack of identical cards.
struct RiverItemRow: View {
    enum Layout {
        case split
        case textOnly
        case fullWidthImage
    }

    let article: ArticleDocument
    let state: BiasAnalysisState
    let layout: Layout

    var body: some View {
        switch layout {
        case .split:
            HStack(alignment: .top, spacing: BSSpacing.s4) {
                VStack(alignment: .leading, spacing: BSSpacing.s2) {
                    header
                    ArticleMetaRow(article: article, state: state)
                }
                if let hero = article.heroImage {
                    ArticleFigure(image: hero, showsCaption: false)
                        .frame(width: 96)
                }
            }
        case .textOnly:
            VStack(alignment: .leading, spacing: BSSpacing.s2) {
                header
                dek
                ArticleMetaRow(article: article, state: state)
            }
        case .fullWidthImage:
            VStack(alignment: .leading, spacing: BSSpacing.s3) {
                if let hero = article.heroImage {
                    ArticleFigure(image: hero, showsCaption: false)
                }
                header
                dek
                ArticleMetaRow(article: article, state: state)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BSSpacing.s1) {
            if let kicker = article.kicker {
                Kicker(text: kicker)
            }
            Text(article.title)
                .font(BSFont.riverHeadline)
                .foregroundStyle(BSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var dek: some View {
        if let dek = article.dek {
            Text(dek)
                .font(BSFont.dek)
                .foregroundStyle(BSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
