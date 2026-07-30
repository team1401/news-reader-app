# Build Report — Broadsheet iOS vertical slice

Branch `agent/ios-mvp`. Nothing is committed.

## Environment

| | |
|---|---|
| Xcode | 26.6 (17F113) |
| SDK | iphonesimulator26.5 |
| Simulator | iPhone 17, iOS 26.5 |
| XcodeGen | 2.46.0 |
| Deployment target | iOS/iPadOS 18.0, universal (`TARGETED_DEVICE_FAMILY = 1,2`) |
| Dependencies | None. Foundation, SwiftUI, Observation, and FoundationModels only. |

## Commands and outcomes

1. **Generate the project**
   `xcodegen generate`
   → `Created project at /Users/helix/.hermes/workspace/news-reader-app-ios/Broadsheet.xcodeproj`

2. **Clean build, code signing disabled**
   `xcodebuild clean -scheme Broadsheet -destination 'platform=iOS Simulator,name=iPhone 17'`
   `xcodebuild build -scheme Broadsheet -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`
   → `** BUILD SUCCEEDED **`, no compiler errors or warnings. (The only console line is
   `appintentsmetadataprocessor … No AppIntents.framework dependency found`, which is expected
   for an app that vends no App Intents.)

3. **All tests**
   `xcodebuild test -scheme Broadsheet -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`
   → `** TEST SUCCEEDED **`
   - `BroadsheetTests`: **104 executed, 0 failures**
   - `BroadsheetUITests`: **6 executed, 0 failures**

   | Suite | Tests |
   |---|---|
   | `FeedParserTests` | 21 |
   | `BiasEngineTests` (labels, fixture analyzer, Foundation Models analyzer) | 19 |
   | `LibraryAndSearchTests` | 15 |
   | `DemoEditionTests` | 14 |
   | `ArticleModelTests` | 12 |
   | `BiasPipelineTests` (cache + service) | 12 |
   | `BiasModelInputTests` | 11 |
   | `BroadsheetUITests` | 6 |

4. **Installed and driven on the simulator**
   `xcrun simctl install booted …/Broadsheet.app && xcrun simctl launch booted com.helix.broadsheet`
   The UI test target drives the real app — Today → reader → analysis sheet → Library → Search — and
   attaches a screenshot at each step to the result bundle. Dark mode was checked separately with
   `xcrun simctl ui booted appearance dark`.

## Foundation Models: what actually ran

`FoundationModelsBiasAnalyzer` calls Apple's on-device system language model through
`LanguageModelSession` with guided generation (`@Generable` / `@Guide`, the label constrained by
`.anyOf(["left","center","right","notApplicable"])`). Availability is read from
`SystemLanguageModel.default.availability`; every unavailable reason is surfaced verbatim and the
analyzer throws `BiasAnalysisError.localModelUnavailable` rather than returning anything.

The analyzer test records its actual outcome in the result bundle. During one implementation run,
the simulator reported the model ready and the real structured-generation path returned:

```
availability: Apple's on-device system language model is ready.
outcome: the on-device system model ran
label: Center
confidence: 0.9
rationale: The article focuses on the procedural aspect of the appeals court vacating the water
           allocation rule, without expressing any strong political opinion or bias.
verified evidence spans: 3
```

During Hermes' independent verification run, the simulator's model catalog had no underlying
assets. The same test therefore exercised the explicit unavailable/error path and still passed.
No fixture or hard-coded result was substituted. This is an honest simulator limitation; inference
must be benchmarked again on the physical target device. Evidence returned when the model does run
is checked against the supplied text and dropped if it is not verbatim, so a fabricated quotation
cannot reach the reader.

The test asserts the invariant rather than the environment: either the model ran and the result
carries `appleFoundationModels` provenance, or an explicit unavailable error was thrown. It passes
on hardware without Apple Intelligence too.

## Remediation findings

1. **Simulated Foundation Models result** — removed. The analyzer performs real guided generation
   and otherwise throws a typed unavailable error carrying Apple's own reason.
2. **Source-sanitized model input** — `BiasModelInputBuilder` produces `BiasModelInput`, which is
   the *only* type `BiasAnalyzing` accepts, so an analyzer has no field from which to read publisher
   identity. It includes title, dek, and article blocks, and redacts publisher name, domain, bare
   domain label, canonical URL, author (including bare surname), and the baseline rating and
   provider, replacing each with `[source]`. Captions and credits are excluded entirely. Eleven
   tests cover this, including one that sweeps every bundled article.
3. **Feed parsing** — rewritten. RSS 2.0 and Atom 1.0, channel identity read from the document,
   RFC 822 and ISO 8601 dates (unparseable dates stay `nil` rather than becoming "now"), Atom
   `rel="alternate"` link selection and nested `<author><name>`, CDATA, `content:encoded`,
   `dc:creator`, enclosure/`media:` images, HTML summaries normalized to plain text, and typed
   `FeedParsingError` cases for empty, malformed, and non-feed documents. Malformed links become
   `nil`; no placeholder host is ever substituted.
4. **UI** — rebuilt natively against the Gemini prototype: `BROADSHEET` masthead with the serif
   edition date and source count, `LEAD STORY` band with vector art, a four-source coverage cluster
   with a baseline distribution strip and Compare Headlines, `THE RIVER` with three alternating row
   layouts, warm neutral palette with an evergreen accent, strong lean capsules, full dark mode, and
   Today/Library/Search tabs.
5. **Demo content** — ten fictional articles across seven fictional publishers, all on reserved
   `.example` domains. Illustrations are drawn natively in SwiftUI and credited as Broadsheet demo
   art; there are no photographs and no wire-service or agency credits. Today carries a visible
   "Demo edition" disclosure. Tests assert the `.example` domains, the absence of real agency
   credits, block-type variety, and that articles are substantial rather than placeholders.
6. **Reader** — renders paragraphs with inline links, headings, hero and inline figures with caption
   and credit, pull quotes with attribution, ordered and unordered lists, and dividers.
   `Read at [Publisher]` sits above the hero and is repeated full-width in the footer; a UI test
   asserts the ordering against the hero's frame.
7. **Bias detail** — provenance, confidence, rationale, verbatim evidence spans, methodology, a
   correction picker, and the publisher baseline in its own section with provider and date. The
   estimate and the baseline are never combined. The capsule opens this sheet from the feed as well
   as the reader; a UI test confirms the feed capsule opens analysis without opening the story.
8. **Cached pipeline** — `BiasAnalysisCache` is an actor keyed by article identity plus engine and
   version, with single-flight de-duplication for concurrent callers and no caching of failures.
   `BiasAnalysisService` analyzes eagerly during refresh and publishes per-article state.
9. **Tests** — 104 unit tests plus 5 UI tests, all with deterministic fixtures.
10. **Library and Search** — Library lists saved stories with swipe-to-remove, sources with their
    baselines and story counts, and an honest on-device analysis status. Search is a local weighted
    index over title, dek, body, and publisher with AND semantics, snippets, and a label filter.

## Honest limitations

- **Saved stories and corrections are in memory only.** They do not survive relaunch. Durable
  storage was explicitly out of scope for this slice; GRDB/SQLite and FTS5 replace both the store
  and the search index later.
- **No live feed fetching in the UI.** The parser, mapper, and typed errors are implemented and
  tested, but there is no add-source flow or network refresh yet, so `ContentSource.liveFeed` is
  exercised by tests rather than by the running app. Pull-to-refresh rebuilds the bundled edition.
- **No Core ML classifier.** The bias-engine architecture calls for a bundled relevance gate and
  lean classifier alongside the system model, with a calibrated aggregator. Only the Foundation
  Models judge and the deterministic fixture heuristic exist. Devices without Apple Intelligence
  will report analysis unavailable for live articles rather than falling back to a local model.
- **The fixture heuristic is a lexicon, not a classifier.** It is deterministic and clearly labelled
  as "not machine learning" everywhere it appears, and it is applied only to bundled demo content.
  Its labels are a demonstration of the surface, not a measurement of anything.
- **No iPad three-column layout.** The app is universal and constrains reading measure to 700 pt,
  but the `NavigationSplitView` sidebar/list/reader layout from the shape brief is not built.
- **No drop cap** on the reader's first paragraph, unlike the prototype. Everything else in the
  reader anatomy is present.
- **Publisher baselines are fictional demo data**, attributed to "Broadsheet demo ratings
  (fictional)". No real rating provider is named or implied.
- **Confidence is not calibrated.** Both engines report a number; neither has been evaluated
  against a held-out set, and the publisher-held-out evaluation the architecture requires has not
  been run.
- The UI test suite takes roughly 100 seconds because it drives real scrolling.
