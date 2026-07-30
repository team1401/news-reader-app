import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                savedSection
                sourcesSection
                analysisSection
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

    private var sourcesSection: some View {
        Section("Sources") {
            ForEach(model.sources) { publisher in
                let count = model.allArticles.filter { $0.publisher.id == publisher.id }.count
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(publisher.name)
                            .font(.system(size: 15, weight: .medium))
                        Spacer()
                        Text("\(count) \(count == 1 ? "story" : "stories")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: BSSpacing.s2) {
                        Text(publisher.domain)
                            .font(.system(size: 12))
                            .foregroundStyle(BSColor.textTertiary)
                        PublisherBaselineChip(baseline: publisher.baseline)
                    }
                }
                .padding(.vertical, 2)
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
            Text("Stories in the bundled demo edition are labelled by a deterministic fixture heuristic so screenshots and tests stay reproducible. It is clearly identified as such in every analysis sheet and is never presented as a model.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !model.analysis.corrections.isEmpty {
                LabeledContent("Your corrections") {
                    Text("\(model.analysis.corrections.count)")
                }
            }
        }
    }
}

#Preview {
    LibraryView()
        .environment(AppModel())
}
