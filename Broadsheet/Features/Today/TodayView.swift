import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showsBaselineExplainer = false
    @State private var showsCompare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    masthead
                    BSDivider()

                    band("Lead story") {
                        storyLink(model.edition.lead) {
                            LeadStoryCard(article: model.edition.lead, state: model.state(for: model.edition.lead))
                        }
                    }

                    BSDivider()
                    clusterSection
                    BSDivider()

                    band("The river") {
                        VStack(alignment: .leading, spacing: BSSpacing.s6) {
                            ForEach(Array(model.edition.river.enumerated()), id: \.element.id) { index, article in
                                storyLink(article) {
                                    RiverItemRow(
                                        article: article,
                                        state: model.state(for: article),
                                        layout: layout(for: index, article: article)
                                    )
                                }
                                if index < model.edition.river.count - 1 {
                                    BSDivider()
                                }
                            }
                        }
                    }

                    footer
                }
                .readingColumn()
            }
            .background(BSColor.bgBase)
            .refreshable {
                await model.refresh()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ArticleID.self) { id in
                if let article = model.article(with: id) {
                    ArticleReaderView(article: article)
                }
            }
        }
        .sheet(isPresented: $showsBaselineExplainer) {
            BaselineExplainerSheet()
        }
        .sheet(isPresented: $showsCompare) {
            CompareHeadlinesSheet(cluster: model.edition.cluster)
                .environment(model)
        }
    }

    // MARK: Sections

    private var masthead: some View {
        VStack(alignment: .leading, spacing: BSSpacing.s1) {
            Text("BROADSHEET")
                .font(BSFont.masthead)
                .tracking(2)
                .foregroundStyle(BSColor.accent)

            Text(model.edition.editionDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(BSFont.editionDate)
                .foregroundStyle(BSColor.textPrimary)

            HStack(alignment: .firstTextBaseline) {
                Text(updatedLine)
                    .font(BSFont.meta)
                    .foregroundStyle(BSColor.textSecondary)
                Spacer(minLength: BSSpacing.s3)
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(BSColor.accent)
                .disabled(model.isRefreshing)
            }
            .padding(.top, BSSpacing.s1)
        }
        .padding(.horizontal, BSSpacing.gutter)
        .padding(.top, BSSpacing.s4)
        .padding(.bottom, BSSpacing.s4)
    }

    private var updatedLine: String {
        let time = model.lastRefreshedAt.formatted(date: .omitted, time: .shortened)
        return "Updated \(time) · \(model.sources.count) sources connected"
    }

    private var clusterSection: some View {
        let cluster = model.edition.cluster
        return VStack(alignment: .leading, spacing: BSSpacing.s3) {
            BandLabel("\(cluster.articles.count) sources covering this")

            Text(cluster.title)
                .font(BSFont.riverHeadline)
                .foregroundStyle(BSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            CoverageBaselineStrip(distribution: cluster.baselineDistribution)

            HStack {
                Text("Coverage by source baseline")
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.textTertiary)
                Spacer()
                Button {
                    showsBaselineExplainer = true
                } label: {
                    Label("About baselines", systemImage: "info.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(BSColor.accent)
            }

            VStack(alignment: .leading, spacing: BSSpacing.s4) {
                ForEach(cluster.articles) { article in
                    storyLink(article) {
                        VStack(alignment: .leading, spacing: BSSpacing.s2) {
                            Text(article.title)
                                .font(BSFont.clusterItemHeadline)
                                .foregroundStyle(BSColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            ArticleMetaRow(article: article, state: model.state(for: article), showsReadingTime: false)
                        }
                    }
                }
            }
            .padding(.top, BSSpacing.s1)

            Button {
                showsCompare = true
            } label: {
                Label("Compare headlines", systemImage: "text.alignleft")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BSSpacing.s3)
                    .background(BSColor.bgSunk, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .foregroundStyle(BSColor.textPrimary)
        }
        .padding(.horizontal, BSSpacing.gutter)
        .padding(.vertical, BSSpacing.s5)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: BSSpacing.s2) {
            BSDivider()
            Text(DemoEdition.disclosure)
                .font(.system(size: 12))
                .foregroundStyle(BSColor.textTertiary)
            Text("Publishers provide the journalism. Broadsheet provides the reading experience, and every story links back to its source.")
                .font(.system(size: 12))
                .foregroundStyle(BSColor.textTertiary)
        }
        .padding(.horizontal, BSSpacing.gutter)
        .padding(.top, BSSpacing.s6)
        .padding(.bottom, BSSpacing.s7)
    }

    // MARK: Helpers

    private func band<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.s3) {
            BandLabel(title)
            content()
        }
        .padding(.horizontal, BSSpacing.gutter)
        .padding(.vertical, BSSpacing.s5)
    }

    private func storyLink<Content: View>(_ article: ArticleDocument, @ViewBuilder content: () -> Content) -> some View {
        NavigationLink(value: article.id) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                model.toggleSaved(article)
            } label: {
                Label(
                    model.isSaved(article) ? "Remove from Library" : "Save to Library",
                    systemImage: model.isSaved(article) ? "bookmark.slash" : "bookmark"
                )
            }
            if let url = article.canonicalURL {
                Link(destination: url) {
                    Label("Read at \(article.publisher.name)", systemImage: "safari")
                }
            }
        }
    }

    private func layout(for index: Int, article: ArticleDocument) -> RiverItemRow.Layout {
        guard article.heroImage != nil else { return .textOnly }
        return index % 3 == 0 ? .split : .fullWidthImage
    }
}

#Preview {
    TodayView()
        .environment(AppModel())
}
