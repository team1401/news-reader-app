import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showsBaselineExplainer = false
    @State private var showsCompare = false
    @State private var showsFailures = false

    private var edition: EditionContent? { model.displayedEdition }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    masthead
                    BSDivider()

                    if model.isDemoMode {
                        demoBanner
                    }
                    if !model.lastReport.failures.isEmpty && !model.isDemoMode {
                        failureBanner
                    }

                    if let edition {
                        band("Lead story") {
                            storyLink(edition.lead) {
                                LeadStoryCard(article: edition.lead, state: model.state(for: edition.lead))
                            }
                        }

                        if let cluster = edition.cluster {
                            BSDivider()
                            clusterSection(cluster)
                        }

                        if !edition.river.isEmpty {
                            BSDivider()
                            band("The river") {
                                VStack(alignment: .leading, spacing: BSSpacing.s6) {
                                    ForEach(Array(edition.river.enumerated()), id: \.element.id) { index, article in
                                        storyLink(article) {
                                            RiverItemRow(
                                                article: article,
                                                state: model.state(for: article),
                                                layout: layout(for: index, article: article)
                                            )
                                        }
                                        if index < edition.river.count - 1 {
                                            BSDivider()
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        emptyEdition
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
            if let cluster = edition?.cluster {
                CompareHeadlinesSheet(cluster: cluster)
                    .environment(model)
            }
        }
        .sheet(isPresented: $showsFailures) {
            RefreshFailureSheet(report: model.lastReport)
        }
    }

    // MARK: Sections

    private var masthead: some View {
        VStack(alignment: .leading, spacing: BSSpacing.s1) {
            Text("BROADSHEET")
                .font(BSFont.masthead)
                .tracking(2)
                .foregroundStyle(BSColor.accent)

            Text((edition?.editionDate ?? Date()).formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(BSFont.editionDate)
                .foregroundStyle(BSColor.textPrimary)

            HStack(alignment: .firstTextBaseline) {
                Text(updatedLine)
                    .font(BSFont.meta)
                    .foregroundStyle(BSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: BSSpacing.s3)
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing")
                } else {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.canRefresh ? BSColor.accent : BSColor.textTertiary)
                    .disabled(!model.canRefresh)
                }
            }
            .padding(.top, BSSpacing.s1)
        }
        .padding(.horizontal, BSSpacing.gutter)
        .padding(.top, BSSpacing.s4)
        .padding(.bottom, BSSpacing.s4)
    }

    private var updatedLine: String {
        if model.isDemoMode {
            return "Demo edition · offline preview"
        }
        let sources = "\(model.enabledSourceCount) \(model.enabledSourceCount == 1 ? "source" : "sources") connected"
        guard let date = model.lastRefreshedAt else {
            return "Not refreshed yet · \(sources)"
        }
        return "Updated \(date.formatted(date: .omitted, time: .shortened)) · \(sources)"
    }

    private var demoBanner: some View {
        banner(
            symbol: "theatermasks",
            tint: BSColor.accent,
            title: "Demo edition",
            detail: DemoEdition.disclosure + " Turn it off in Library to read your sources."
        )
    }

    private var failureBanner: some View {
        Button {
            showsFailures = true
        } label: {
            banner(
                symbol: "exclamationmark.triangle",
                tint: BSColor.warning,
                title: "\(model.lastReport.failures.count) \(model.lastReport.failures.count == 1 ? "source" : "sources") failed to refresh",
                detail: "Their previously downloaded stories are still here. Tap for details."
            )
        }
        .buttonStyle(.plain)
    }

    private func banner(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: BSSpacing.s3) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BSColor.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(BSSpacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, BSSpacing.gutter)
        .padding(.top, BSSpacing.s4)
        .accessibilityElement(children: .combine)
    }

    private var emptyEdition: some View {
        VStack(alignment: .leading, spacing: BSSpacing.s4) {
            Text(model.enabledSourceCount == 0 ? "No sources are enabled" : "Nothing downloaded yet")
                .font(BSFont.leadHeadline)
                .foregroundStyle(BSColor.textPrimary)

            Text(model.enabledSourceCount == 0
                 ? "Add a feed in Library → Sources, or re-enable one you turned off."
                 : "Pull down to refresh, and Broadsheet will fetch your \(model.enabledSourceCount) enabled \(model.enabledSourceCount == 1 ? "source" : "sources"). Everything it downloads stays on this device.")
                .font(BSFont.dek)
                .foregroundStyle(BSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.canRefresh {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BSColor.bgRaised)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BSSpacing.s3)
                        .background(BSColor.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(model.isRefreshing)
            }
        }
        .padding(.horizontal, BSSpacing.gutter)
        .padding(.vertical, BSSpacing.s7)
    }

    private func clusterSection(_ cluster: CoverageCluster) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.s3) {
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
            if model.isDemoMode {
                Text(DemoEdition.disclosure)
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.textTertiary)
            }
            Text("Publishers provide the journalism. Broadsheet provides the reading experience, and every story links back to its source.")
                .font(.system(size: 12))
                .foregroundStyle(BSColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
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

/// Why each source failed, verbatim. A refresh failure is diagnosable per source,
/// which the product brief calls for explicitly.
struct RefreshFailureSheet: View {
    let report: RefreshReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Your previously downloaded stories from these sources are still on the device and still readable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(report.failures) { failure in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(failure.sourceTitle)
                            .font(.system(size: 15, weight: .semibold))
                        Text(failure.errorMessage ?? "No reason was reported.")
                            .font(.footnote)
                            .foregroundStyle(BSColor.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Refresh problems")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
