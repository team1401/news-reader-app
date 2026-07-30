import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var labelFilter: BiasLabel?

    private var results: [ArticleSearchResult] {
        let matches = ArticleSearchIndex.search(query, in: model.allArticles)
        guard let labelFilter else { return matches }
        return matches.filter { model.state(for: $0.article).result?.label == labelFilter }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    emptyState
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    resultsList
                }
            }
            .background(BSColor.bgBase)
            .navigationTitle("Search")
            .navigationDestination(for: ArticleID.self) { id in
                if let article = model.article(with: id) {
                    ArticleReaderView(article: article)
                }
            }
        }
        .searchable(text: $query, prompt: "Search stories on this device")
    }

    private var resultsList: some View {
        List {
            Section {
                Picker("Filter by estimate", selection: $labelFilter) {
                    Text("All").tag(BiasLabel?.none)
                    ForEach(BiasLabel.allCases, id: \.self) { label in
                        Text(label.displayName).tag(BiasLabel?.some(label))
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section("\(results.count) \(results.count == 1 ? "story" : "stories")") {
                ForEach(results) { result in
                    NavigationLink(value: result.article.id) {
                        VStack(alignment: .leading, spacing: BSSpacing.s2) {
                            Text(result.article.title)
                                .font(BSFont.serif(.headline))
                                .foregroundStyle(BSColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(result.snippet)
                                .font(.system(size: 13))
                                .foregroundStyle(BSColor.textSecondary)
                                .lineLimit(3)
                            HStack(spacing: BSSpacing.s2) {
                                Text(result.article.publisher.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(BSColor.textSecondary)
                                BiasCapsule(state: model.state(for: result.article))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSSpacing.s4) {
                Text("Search runs on this device across the \(model.allArticles.count) stories you already have. Nothing is sent anywhere and no query is recorded.")
                    .font(.callout)
                    .foregroundStyle(BSColor.textSecondary)

                BandLabel("Try")
                ForEach(["water allocation", "reserve margin", "licensing", "kelp"], id: \.self) { suggestion in
                    Button {
                        query = suggestion
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text(suggestion)
                            Spacer()
                        }
                        .font(.callout)
                        .foregroundStyle(BSColor.accent)
                        .padding(.vertical, BSSpacing.s2)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .padding(BSSpacing.gutter)
            .readingColumn()
        }
    }
}

#Preview {
    SearchView()
        .environment(AppModel.preview())
}
