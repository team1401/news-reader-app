import SwiftUI

/// Provenance and methodology for the article-level estimate.
///
/// Article estimate and publisher baseline are kept in separate sections with
/// separate headings, because their disagreement is useful information rather than
/// something to average away.
struct PerspectiveDetailSheet: View {
    let article: ArticleDocument
    let state: BiasAnalysisState

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                switch state {
                case .analyzed(let result):
                    estimateSection(result)
                    rationaleSection(result)
                    evidenceSection(result)
                    methodologySection
                case .analyzing, .pending:
                    Section {
                        Label("Analyzing locally…", systemImage: "hourglass")
                    }
                    methodologySection
                case .unavailable(let reason):
                    unavailableSection(reason)
                    methodologySection
                }

                baselineSection
                correctionSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("On-device analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Article estimate

    private func estimateSection(_ result: BiasAnalysisResult) -> some View {
        Section("Article estimate") {
            LabeledContent("Estimate") {
                BiasCapsule(state: state, size: .prominent)
            }
            LabeledContent("Confidence") {
                Text("\(result.confidence.displayName) (\(Int((result.confidenceScore * 100).rounded()))%)")
            }
            LabeledContent("Engine") {
                Text(result.provenance.engine.displayName)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Version") {
                Text(result.provenance.modelVersion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            Label(result.provenance.engine.disclosure, systemImage: "iphone.gen3")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func rationaleSection(_ result: BiasAnalysisResult) -> some View {
        Section("Rationale") {
            Text(result.rationale)
                .font(.callout)
        }
    }

    @ViewBuilder
    private func evidenceSection(_ result: BiasAnalysisResult) -> some View {
        Section("Evidence from the article") {
            if result.evidence.isEmpty {
                Text("No supporting excerpt was identified for this estimate.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(result.evidence) { evidence in
                    HStack(alignment: .top, spacing: BSSpacing.s3) {
                        Rectangle()
                            .fill(BSColor.accent)
                            .frame(width: 3)
                        Text(evidence.excerpt)
                            .font(BSFont.serif(.callout))
                            .italic()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func unavailableSection(_ reason: String) -> some View {
        Section("Article estimate") {
            Label("No estimate available", systemImage: "exclamationmark.triangle")
                .foregroundStyle(BSColor.textPrimary)
            Text(reason)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Broadsheet does not substitute a guess when local analysis cannot run.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var methodologySection: some View {
        Section("Methodology") {
            Text("Analysis runs entirely on this device. Before the article is analyzed, the publisher name, domain, canonical URL, author, and the publisher's baseline rating are removed from the text, so the estimate reflects the article's own framing rather than which outlet published it.")
                .font(.footnote)
            Text("This is an estimate of framing, not a verdict about accuracy or quality.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Publisher baseline (separate)

    @ViewBuilder
    private var baselineSection: some View {
        Section("Publisher baseline — sourced separately") {
            if let baseline = article.publisher.baseline {
                LabeledContent("Baseline") { Text(baseline.rating) }
                LabeledContent("Provider") {
                    Text(baseline.provider).multilineTextAlignment(.trailing)
                }
                LabeledContent("As of") {
                    Text(baseline.asOf.formatted(date: .abbreviated, time: .omitted))
                }
                Text("This describes \(article.publisher.name) as a source. It is not part of the article estimate above and the two are never combined.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No baseline rating is on file for \(article.publisher.name).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Correction

    private var correctionSection: some View {
        Section("Your correction") {
            Picker("Correct this estimate", selection: Binding(
                get: { model.analysis.correction(for: article) },
                set: { model.analysis.recordCorrection($0, for: article) }
            )) {
                Text("No correction").tag(BiasLabel?.none)
                ForEach(BiasLabel.allCases, id: \.self) { label in
                    Text(label.displayName).tag(BiasLabel?.some(label))
                }
            }
            .pickerStyle(.menu)

            if let correction = model.analysis.correction(for: article) {
                Label("You marked this article as \(correction.displayName).", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(BSColor.accent)
            }

            Text("Corrections stay on this device and are kept for evaluation. They do not overwrite the estimate shown above.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Provenance for a *publisher* baseline, deliberately its own surface.
struct BaselineProvenanceSheet: View {
    let publisher: Publisher

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(publisher.name) {
                    if let baseline = publisher.baseline {
                        LabeledContent("Baseline") { Text(baseline.rating) }
                        LabeledContent("Provider") {
                            Text(baseline.provider).multilineTextAlignment(.trailing)
                        }
                        LabeledContent("As of") {
                            Text(baseline.asOf.formatted(date: .abbreviated, time: .omitted))
                        }
                    } else {
                        Text("No baseline rating is on file.")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Domain") { Text(publisher.domain) }
                }

                Section {
                    Text("A publisher baseline describes a source's general orientation over time. It comes from an outside rating provider, not from Broadsheet, and it says nothing about the specific article you are reading.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Baseline provenance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct BaselineExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("What the strip shows") {
                    Text("The coverage strip counts the publisher baselines of the sources reporting this story. It describes who is covering it, not what any single article says.")
                        .font(.callout)
                }
                Section("What it does not show") {
                    Text("It is not an average of the article-level estimates, and it is not a measure of accuracy. An article from a left-baseline publisher can be estimated Center, and that disagreement is kept visible rather than resolved.")
                        .font(.callout)
                }
                Section("Ratings in this build") {
                    Text("Baselines shown in the demo edition come from \(DemoPublishers.ratingProvider) and describe fictional publishers created for development.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About source baselines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Headlines from every source in a cluster, side by side, so wording differences
/// are legible without any scoring layer.
struct CompareHeadlinesSheet: View {
    let cluster: CoverageCluster

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(cluster.articles) { article in
                    VStack(alignment: .leading, spacing: BSSpacing.s2) {
                        HStack(spacing: BSSpacing.s2) {
                            Text(article.publisher.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BSColor.textSecondary)
                            BiasCapsule(state: model.state(for: article))
                            PublisherBaselineChip(baseline: article.publisher.baseline)
                        }
                        Text(article.title)
                            .font(BSFont.serif(.headline))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Compare headlines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
