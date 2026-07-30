import SwiftUI

struct ArticleReaderView: View {
    let article: ArticleDocument

    @Environment(AppModel.self) private var model
    @State private var showsAnalysis = false
    @State private var showsBaseline = false

    private var state: BiasAnalysisState {
        model.state(for: article)
    }

    private var settings: ReaderSettings { model.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSSpacing.s5) {
                perspectiveHeader
                headline
                byline

                // The canonical-source action sits above the first body block, and
                // is repeated in the footer.
                readAtPublisherButton(prominent: true)

                if let hero = article.heroImage {
                    ArticleFigure(image: hero)
                }

                ExtractionNotice(status: article.extraction)

                body(for: article.blocks)

                perspectiveSection
                footer
            }
            .padding(.horizontal, BSSpacing.gutter)
            .padding(.bottom, BSSpacing.s7)
            .readingColumn()
        }
        .background(BSColor.bgBase)
        .dynamicTypeSize(settings.textSize)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(article.publisher.domain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BSColor.textSecondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.toggleSaved(article)
                } label: {
                    Image(systemName: model.isSaved(article) ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(model.isSaved(article) ? "Remove from Library" : "Save to Library")
            }
            ToolbarItem(placement: .topBarTrailing) {
                readingSettingsMenu
            }
        }
        .sheet(isPresented: $showsAnalysis) {
            PerspectiveDetailSheet(article: article, state: state)
                .environment(model)
        }
        .sheet(isPresented: $showsBaseline) {
            BaselineProvenanceSheet(publisher: article.publisher)
        }
        .task {
            await model.analysis.analyze(article)
        }
    }

    // MARK: Header

    private var perspectiveHeader: some View {
        VStack(alignment: .leading, spacing: BSSpacing.s2) {
            HStack(spacing: BSSpacing.s2) {
                Button {
                    showsAnalysis = true
                } label: {
                    BiasCapsule(state: state, size: .prominent)
                }
                .buttonStyle(.plain)

                Text("On-device estimate")
                    .font(.system(size: 13))
                    .foregroundStyle(BSColor.textSecondary)
            }

            if article.publisher.baseline != nil {
                Button {
                    showsBaseline = true
                } label: {
                    HStack(spacing: 4) {
                        PublisherBaselineChip(baseline: article.publisher.baseline)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(BSColor.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, BSSpacing.s3)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: BSSpacing.s3) {
            if let kicker = article.kicker {
                Kicker(text: kicker)
            }
            Text(article.title)
                .font(BSFont.serif(.largeTitle, weight: .bold))
                .foregroundStyle(BSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let dek = article.dek {
                Text(dek)
                    .font(BSFont.serif(.title3))
                    .foregroundStyle(BSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var byline: some View {
        VStack(alignment: .leading, spacing: BSSpacing.s2) {
            HStack(spacing: BSSpacing.s1) {
                if let author = article.author {
                    Text("By ").foregroundStyle(BSColor.textTertiary)
                        + Text(author).foregroundStyle(BSColor.textSecondary).bold()
                    Text("·").foregroundStyle(BSColor.textTertiary)
                }
                Text(article.publishedAt.formatted(date: .long, time: .shortened))
                    .foregroundStyle(BSColor.textTertiary)
                Text("·").foregroundStyle(BSColor.textTertiary)
                Text("\(article.readingTimeMinutes) min read")
                    .foregroundStyle(BSColor.textTertiary)
            }
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)

            BSDivider()
        }
    }

    // MARK: Body

    @ViewBuilder
    private func body(for blocks: [ArticleBlock]) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.s5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: ArticleBlock) -> some View {
        switch block {
        case .paragraph(let rich):
            RichTextView(rich, font: settings.bodyFont(.body))

        case .heading(let text):
            Text(text)
                .font(BSFont.serif(.title3, weight: .bold))
                .foregroundStyle(BSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, BSSpacing.s2)

        case .image(let image):
            ArticleFigure(image: image)

        case .pullQuote(let text, let attribution):
            VStack(alignment: .leading, spacing: BSSpacing.s2) {
                Text(text)
                    .font(BSFont.serif(.title3))
                    .italic()
                    .foregroundStyle(BSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let attribution {
                    Text("— \(attribution)")
                        .font(.system(size: 13))
                        .foregroundStyle(BSColor.textSecondary)
                }
            }
            .padding(.leading, BSSpacing.s4)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(BSColor.accent)
                    .frame(width: 3)
            }

        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: BSSpacing.s3) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: BSSpacing.s3) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(settings.bodyFont(.body))
                            .foregroundStyle(BSColor.accent)
                            .frame(minWidth: 16, alignment: .leading)
                        RichTextView(item, font: settings.bodyFont(.body))
                    }
                }
            }

        case .divider:
            BSDivider()
                .padding(.vertical, BSSpacing.s2)
        }
    }

    // MARK: Perspective and footer

    private var perspectiveSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.s3) {
            BSDivider()
            BandLabel("Perspective")

            switch state {
            case .analyzed(let result):
                HStack(spacing: BSSpacing.s2) {
                    BiasCapsule(state: state, size: .prominent)
                    Text("\(result.confidence.displayName) confidence")
                        .font(.system(size: 13))
                        .foregroundStyle(BSColor.textSecondary)
                }
                Text(result.rationale)
                    .font(.system(size: 14))
                    .foregroundStyle(BSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(result.provenance.engine.disclosure)
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

            case .analyzing, .pending:
                Text("Analyzing locally…")
                    .font(.system(size: 14))
                    .foregroundStyle(BSColor.textSecondary)

            case .unavailable(let reason):
                Text(reason)
                    .font(.system(size: 14))
                    .foregroundStyle(BSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showsAnalysis = true
            } label: {
                Label("Analysis details and correction", systemImage: "chevron.right.circle")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(BSColor.accent)

            if let baseline = article.publisher.baseline {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Publisher baseline: \(baseline.rating)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BSColor.textSecondary)
                    Text("\(baseline.provider) · \(baseline.asOf.formatted(date: .abbreviated, time: .omitted)). Sourced separately from the article estimate above.")
                        .font(.system(size: 12))
                        .foregroundStyle(BSColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, BSSpacing.s1)
            }
        }
        .padding(.top, BSSpacing.s5)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: BSSpacing.s3) {
            BSDivider()
            readAtPublisherButton(prominent: true, label: "Read the original at \(article.publisher.name)")
            Text("\(article.publisher.name) reported and published this story. Broadsheet reformats it for reading and always links back to the source.")
                .font(.system(size: 12))
                .foregroundStyle(BSColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, BSSpacing.s5)
    }

    @ViewBuilder
    private func readAtPublisherButton(prominent: Bool, label: String? = nil) -> some View {
        if let url = article.canonicalURL {
            Link(destination: url) {
                Label(label ?? "Read at \(article.publisher.name)", systemImage: "arrow.up.forward.square")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BSColor.bgRaised)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BSSpacing.s3)
                    .background(BSColor.accent, in: RoundedRectangle(cornerRadius: 8))
            }
        } else {
            Text("This story has no canonical link, so it cannot be opened at the publisher.")
                .font(.system(size: 13))
                .foregroundStyle(BSColor.textSecondary)
        }
    }

    private var readingSettingsMenu: some View {
        Menu {
            Picker("Body text", selection: Binding(
                get: { settings.bodyFace },
                set: { settings.bodyFace = $0 }
            )) {
                ForEach(ReaderSettings.BodyFace.allCases) { face in
                    Text(face.displayName).tag(face)
                }
            }
            Button {
                settings.decreaseTextSize()
            } label: {
                Label("Smaller text", systemImage: "textformat.size.smaller")
            }
            Button {
                settings.increaseTextSize()
            } label: {
                Label("Larger text", systemImage: "textformat.size.larger")
            }
        } label: {
            Image(systemName: "textformat.size")
        }
        .accessibilityLabel("Reading settings")
    }
}

#Preview {
    let model = AppModel()
    return NavigationStack {
        ArticleReaderView(article: model.edition.lead)
    }
    .environment(model)
}
