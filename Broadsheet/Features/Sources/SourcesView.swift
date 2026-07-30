import SwiftUI

/// Manage the feeds Broadsheet reads.
///
/// Everything the plan requires is here and reachable: add, rename, refolder,
/// enable or disable, refresh one source, and delete. The four starter feeds are
/// ordinary rows with no special protection.
struct SourcesView: View {
    @Environment(AppModel.self) private var model
    @State private var showsAddSource = false
    @State private var refreshingSourceID: String?

    private var grouped: [(folder: String, sources: [SourceSummary])] {
        Dictionary(grouping: model.sourceSummaries, by: { $0.source.folder })
            .map { (folder: $0.key, sources: $0.value.sorted { $0.source.sortIndex < $1.source.sortIndex }) }
            .sorted { $0.folder < $1.folder }
    }

    var body: some View {
        List {
            if model.sourceSummaries.isEmpty {
                ContentUnavailableView {
                    Label("No sources", systemImage: "antenna.radiowaves.left.and.right.slash")
                } description: {
                    Text("Add an RSS, Atom, or JSON feed to start reading.")
                }
            }

            ForEach(grouped, id: \.folder) { group in
                Section(group.folder) {
                    ForEach(group.sources) { summary in
                        NavigationLink(value: SourceRoute(id: summary.source.id)) {
                            SourceRow(summary: summary, isRefreshing: refreshingSourceID == summary.source.id)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                model.deleteSource(id: summary.source.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                model.setSourceEnabled(!summary.source.isEnabled, id: summary.source.id)
                            } label: {
                                Label(
                                    summary.source.isEnabled ? "Disable" : "Enable",
                                    systemImage: summary.source.isEnabled ? "pause.circle" : "play.circle"
                                )
                            }
                            .tint(BSColor.accent)
                        }
                    }
                }
            }

            Section {
                Text("Broadsheet fetches these feeds over HTTPS with a descriptive user agent, follows at most five redirects, and stops any response larger than 8 MB. It never signs in and never works around a publisher's access controls.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sources")
        .navigationDestination(for: SourceRoute.self) { route in
            if let summary = model.sourceSummaries.first(where: { $0.source.id == route.id }) {
                SourceDetailView(summary: summary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsAddSource = true
                } label: {
                    Label("Add source", systemImage: "plus")
                }
                .accessibilityLabel("Add source")
            }
        }
        .sheet(isPresented: $showsAddSource) {
            AddSourceView()
                .environment(model)
        }
    }
}

struct SourceRoute: Hashable {
    let id: String
}

struct SourceRow: View {
    let summary: SourceSummary
    var isRefreshing = false

    private var source: FeedSource { summary.source }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: BSSpacing.s2) {
                Text(source.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(source.isEnabled ? BSColor.textPrimary : BSColor.textTertiary)
                if !source.isEnabled {
                    Text("Off")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BSColor.bgSunk, in: Capsule())
                        .foregroundStyle(BSColor.textTertiary)
                }
                Spacer()
                if isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }

            Text(source.feedURL.host ?? source.feedURL.absoluteString)
                .font(.system(size: 12))
                .foregroundStyle(BSColor.textTertiary)
                .lineLimit(1)

            HStack(spacing: BSSpacing.s2) {
                SourceStatusChip(source: source)
                Text("\(summary.articleCount) cached")
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.textTertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [source.title, source.isEnabled ? "enabled" : "disabled"]
        switch source.lastStatus {
        case .never: parts.append("not refreshed yet")
        case .succeeded: parts.append("last refresh succeeded")
        case .failed: parts.append("last refresh failed: \(source.lastErrorMessage ?? "unknown reason")")
        }
        parts.append("\(summary.articleCount) cached stories")
        return parts.joined(separator: ", ")
    }
}

struct SourceStatusChip: View {
    let source: FeedSource

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private var symbol: String {
        switch source.lastStatus {
        case .never: return "clock"
        case .succeeded: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var text: String {
        switch source.lastStatus {
        case .never: return "Never refreshed"
        case .succeeded:
            guard let date = source.lastRefreshedAt else { return "OK" }
            return date.formatted(date: .omitted, time: .shortened)
        case .failed: return "Failed"
        }
    }

    private var tint: Color {
        switch source.lastStatus {
        case .never: return BSColor.textTertiary
        case .succeeded: return BSColor.accent
        case .failed: return BSColor.warning
        }
    }
}

/// Edit one source, see why its last refresh failed, and refresh it on its own.
struct SourceDetailView: View {
    let summary: SourceSummary

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var folder = ""
    @State private var isEnabled = true
    @State private var isRefreshing = false
    @State private var didLoad = false

    private var source: FeedSource { summary.source }

    var body: some View {
        Form {
            Section("Source") {
                TextField("Title", text: $title)
                    .accessibilityLabel("Source title")
                TextField("Folder", text: $folder)
                    .accessibilityLabel("Folder")
                Toggle("Enabled", isOn: $isEnabled)
            }

            Section("Feed") {
                LabeledContent("Address") {
                    Text(source.feedURL.absoluteString)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                if let siteURL = source.siteURL {
                    Link(destination: siteURL) {
                        Label("Open \(siteURL.host ?? "website")", systemImage: "safari")
                    }
                }
                LabeledContent("Cached stories") { Text("\(summary.articleCount)") }
                LabeledContent("Items last refresh") { Text("\(source.lastItemCount)") }
            }

            Section("Last refresh") {
                LabeledContent("Status") {
                    Text(source.lastStatus.displayName)
                        .foregroundStyle(source.lastStatus == .failed ? BSColor.warning : .secondary)
                }
                if let date = source.lastRefreshedAt {
                    LabeledContent("When") { Text(date.formatted(date: .abbreviated, time: .shortened)) }
                }
                if let error = source.lastErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(BSColor.warning)
                }
                Button {
                    Task {
                        isRefreshing = true
                        await model.refreshSource(id: source.id)
                        isRefreshing = false
                    }
                } label: {
                    HStack {
                        Label("Refresh this source", systemImage: "arrow.clockwise")
                        if isRefreshing {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(isRefreshing || model.isDemoMode)
            }

            Section {
                Button(role: .destructive) {
                    model.deleteSource(id: source.id)
                    dismiss()
                } label: {
                    Label("Delete source", systemImage: "trash")
                }
            } footer: {
                Text("Deleting a source removes its cached stories from this device. It never comes back on its own, even if it was one of the starter sources.")
            }
        }
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            title = source.title
            folder = source.folder
            isEnabled = source.isEnabled
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        var updated = source
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmedTitle.isEmpty ? source.title : trimmedTitle
        let trimmedFolder = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.folder = trimmedFolder.isEmpty ? FeedSource.defaultFolder : trimmedFolder
        updated.isEnabled = isEnabled
        guard updated != source else { return }
        model.update(updated)
    }
}
