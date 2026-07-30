import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        return NavigationStack {
            List {
                sourcesSection
                savedSection
                analysisSection
                demoSection
                privacySection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(BSColor.bgBase)
            .navigationTitle("Library")
            .navigationDestination(for: ArticleID.self) { id in
                if let article = model.article(with: id) {
                    ArticleReaderView(article: article)
                }
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .sources:
                    SourcesView()
                }
            }
            .navigationDestination(for: SourceRoute.self) { route in
                if let summary = model.sourceSummaries.first(where: { $0.source.id == route.id }) {
                    SourceDetailView(summary: summary)
                }
            }
        }
    }

    // MARK: Sections

    private var sourcesSection: some View {
        Section("Sources") {
            NavigationLink(value: LibraryRoute.sources) {
                LabeledContent("Manage sources") {
                    Text("\(model.sourceSummaries.count)")
                }
            }
            .accessibilityLabel("Manage sources, \(model.sourceSummaries.count) subscribed")

            ForEach(model.sourceSummaries.prefix(6)) { summary in
                NavigationLink(value: SourceRoute(id: summary.source.id)) {
                    SourceRow(summary: summary)
                }
            }
        }
    }

    @ViewBuilder
    private var savedSection: some View {
        Section("Saved stories") {
            if model.savedArticles.isEmpty {
                VStack(alignment: .leading, spacing: BSSpacing.s2) {
                    Text("Nothing saved yet.")
                        .font(.callout)
                    Text("Tap the bookmark in the reader, or press and hold a story in Today, to keep it here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(model.savedArticles) { article in
                    NavigationLink(value: article.id) {
                        VStack(alignment: .leading, spacing: BSSpacing.s2) {
                            Text(article.title)
                                .font(BSFont.serif(.headline))
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: BSSpacing.s2) {
                                Text(article.publisher.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(BSColor.textSecondary)
                                BiasCapsule(state: model.state(for: article))
                                Text("\(article.readingTimeMinutes) min")
                                    .font(.system(size: 12))
                                    .foregroundStyle(BSColor.textTertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            model.removeSaved(article)
                        } label: {
                            Label("Remove", systemImage: "bookmark.slash")
                        }
                    }
                }
            }
        }
    }

    private var analysisSection: some View {
        Section("On-device analysis") {
            LabeledContent("Apple Foundation Models") {
                Text(model.analysis.isLocalModelAvailable ? "Ready" : "Unavailable")
                    .foregroundStyle(model.analysis.isLocalModelAvailable ? BSColor.accent : .secondary)
            }
            Text(model.analysis.localModelAvailabilityDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Live articles are labelled only by the on-device language model. When it cannot run, Broadsheet says so rather than substituting a rule-based guess.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.analysis.corrections.isEmpty {
                LabeledContent("Your corrections") {
                    Text("\(model.analysis.corrections.count)")
                }
            }
        }
    }

    private var demoSection: some View {
        @Bindable var model = model

        return Section {
            Toggle("Demo edition", isOn: $model.isDemoMode)
                .accessibilityHint("Replaces your sources with bundled fictional stories for previewing the design offline.")
        } header: {
            Text("Preview")
        } footer: {
            Text("The demo edition is bundled fictional journalism on reserved .example domains, labelled by a deterministic rule-based heuristic so screenshots stay reproducible. It never touches the network, it is never mixed with your sources, and nothing you save in it is written to your library.")
        }
    }

    private var privacySection: some View {
        Section("On this device") {
            LabeledContent("Cached stories") { Text("\(model.liveArticles.count)") }
            if let date = model.lastRefreshedAt {
                LabeledContent("Last refresh") {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Text("Broadsheet has no account, no server, and no analytics. Sources, articles, reading state, and analysis results are stored only on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum LibraryRoute: Hashable {
    case sources
}
