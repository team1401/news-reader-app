import SwiftUI

/// Add a source by feed address, or by pasting a publisher's page and letting
/// Broadsheet read the feeds that page advertises.
///
/// Nothing is saved until the address has been fetched and parsed, so the row that
/// appears in Sources is one Broadsheet has already proved it can read.
struct AddSourceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var folder = FeedSource.defaultFolder
    @State private var candidates: [FeedCandidate] = []
    @State private var errorMessage: String?
    @State private var isChecking = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("example.com or example.com/feed.xml", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.search)
                        .focused($addressFocused)
                        .accessibilityLabel("Feed or website address")
                        .onSubmit { Task { await check() } }

                    Button {
                        Task { await check() }
                    } label: {
                        HStack {
                            Text("Find feeds")
                            if isChecking {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isChecking)
                } header: {
                    Text("Address")
                } footer: {
                    Text("Broadsheet fetches the address over HTTPS and parses it before saving anything. A publisher page is scanned for the RSS, Atom, or JSON feeds it advertises.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(BSColor.warning)
                    }
                }

                if !candidates.isEmpty {
                    Section("Folder") {
                        TextField("Folder", text: $folder)
                            .accessibilityLabel("Folder for the new source")
                    }

                    Section("\(candidates.count) \(candidates.count == 1 ? "feed" : "feeds") found") {
                        ForEach(candidates) { candidate in
                            candidateRow(candidate)
                        }
                    }
                }
            }
            .navigationTitle("Add source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { addressFocused = true }
        }
    }

    @ViewBuilder
    private func candidateRow(_ candidate: FeedCandidate) -> some View {
        let alreadyAdded = model.isAlreadySubscribed(candidate)

        Button {
            model.addSource(candidate, folder: folder)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(candidate.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(BSColor.textPrimary)
                    Spacer()
                    if alreadyAdded {
                        Text("Added")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BSColor.textTertiary)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(BSColor.accent)
                    }
                }
                Text(candidate.feedURL.absoluteString)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(BSColor.textTertiary)
                    .lineLimit(2)
                Text("\(candidate.format.displayName) · \(candidate.itemCount) items · \(candidate.carriesFullContent ? "full articles in feed" : "excerpts in feed")")
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.textSecondary)
            }
            .padding(.vertical, 2)
        }
        .disabled(alreadyAdded)
        .accessibilityLabel("\(candidate.title), \(candidate.format.displayName), \(candidate.itemCount) items\(alreadyAdded ? ", already added" : "")")
    }

    private func check() async {
        errorMessage = nil
        candidates = []
        isChecking = true
        defer { isChecking = false }

        do {
            let found = try await model.validateCandidates(for: address)
            candidates = found
            if let first = found.first, folder == FeedSource.defaultFolder, found.count == 1 {
                folder = model.folders.first(where: { $0 == first.title }) ?? folder
            }
        } catch let error as SourceValidationError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
