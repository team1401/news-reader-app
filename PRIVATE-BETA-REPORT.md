# Private Beta Report — Broadsheet

Branch `agent/private-beta`. **Nothing is committed.**

Broadsheet is now a daily-use local-first reader: it seeds four verified sources on
first launch, fetches and parses them over HTTPS, extracts openly published articles
with vendored Mozilla Readability inside a locked-down `WKWebView`, normalizes them
into semantic blocks, stores everything in SwiftData, analyzes live articles with
Apple's on-device model, and renders the result in the Gemini house style on iPhone
and iPad.

## Environment

| | |
|---|---|
| Xcode | 26.6 (17F113) |
| SDK | iphonesimulator26.5 |
| XcodeGen | 2.46.0 |
| Simulators | iPhone 17 (iOS 26.5), iPad Pro 13-inch (M5) |
| Deployment target | iOS/iPadOS 18.0, universal (`TARGETED_DEVICE_FAMILY = 1,2`) |
| Dependencies | None via a package manager. One vendored file set: Mozilla Readability (Apache 2.0), checked into `Broadsheet/Extraction/Vendor/Readability/`. |
| Frameworks | Foundation, SwiftUI, SwiftData, Observation, WebKit, CryptoKit, FoundationModels |
| Size | 9,249 lines of app Swift across 48 files; 4,421 lines of test Swift; 3,330 lines of vendored JavaScript |

## Commands and actual outcomes

### 1. Generate the project

```
xcodegen generate
```
→ `Created project at /Users/helix/.hermes/workspace/news-reader-private-beta/Broadsheet.xcodeproj`

### 2. All unit and UI tests on iPhone 17

```
xcodebuild test -scheme Broadsheet \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```
→ `** TEST SUCCEEDED **`

- `BroadsheetTests`: **256 executed, 0 failures** (final post-review run)
- `BroadsheetUITests`: **12 executed, 0 failures** (final post-review run)

| Suite | Tests | Failures |
|---|---|---|
| `FeedParserTests` | 21 | 0 |
| `PersistenceTests` | 19 | 0 |
| `HTTPTransportTests` | 16 | 0 |
| `DemoEditionTests` | 14 | 0 |
| `JSONFeedParserTests` | 14 | 0 |
| `RefreshPipelineTests` | 14 | 0 |
| `ArticleCanonicalizerTests` | 12 | 0 |
| `ArticleModelTests` | 12 | 0 |
| `SourceValidatorTests` | 12 | 0 |
| `BiasModelInputTests` | 11 | 0 |
| `ReadabilityExtractorTests` | 12 | 0 |
| `AppModelRefreshTests` | 10 | 0 |
| `ArticleSearchIndexTests` | 8 | 0 |
| `DeterministicFixtureBiasAnalyzerTests` | 8 | 0 |
| `FeedDiscoveryTests` | 8 | 0 |
| `AccessGateClassifierTests` | 7 | 0 |
| `BiasLabelTests` | 7 | 0 |
| `EditionBuilderTests` | 7 | 0 |
| `LibraryTests` | 7 | 0 |
| `BiasAnalysisCacheTests` | 6 | 0 |
| `BiasAnalysisServiceTests` | 6 | 0 |
| `FeedDocumentParserTests` | 6 | 0 |
| `RobotsRulesTests` | 6 | 0 |
| `RobotsPolicyTests` | 5 | 0 |
| `FeedURLNormalizerTests` | 4 | 0 |
| `FoundationModelsBiasAnalyzerTests` | 4 | 0 |
| `BroadsheetUITests` (UI) | 12 | 0 |
| **Total** | **268** | **0** |

**The offline suite never touches the network.** Every networking test drives the
real `URLSessionHTTPTransport` through a `URLProtocol` stub; the refresh, resolution,
and app-model tests drive the real pipeline through a bundled fixture transport. The
real-network checks live in a separate target that is not in this scheme's test
action (below), so `xcodebuild test -scheme Broadsheet` passes with Wi-Fi off.

### 3. Builds with code signing disabled

```
xcodebuild clean build -scheme Broadsheet \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```
→ `** BUILD SUCCEEDED **`, no errors, no Swift warnings.

```
xcodebuild build -scheme Broadsheet \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' CODE_SIGNING_ALLOWED=NO
```
→ `** BUILD SUCCEEDED **`

### 4. Real-network smoke refresh against all four verified feeds

```
xcodebuild test -scheme BroadsheetNetworkSmokeTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```
→ `** TEST SUCCEEDED **`, 2 executed, 0 failures.

Actual output from the run at 13:05 on 2026-07-30:

| Source | URL | Status | Bytes | Redirects | Format | Items |
|---|---|---|---|---|---|---|
| BBC News | `https://feeds.bbci.co.uk/news/rss.xml?edition=int` | 200 | 25,794 | 0 | RSS | 33 |
| NPR News | `https://feeds.npr.org/1001/rss.xml` | 200 | 15,181 | 0 | RSS | 10 |
| Ars Technica | `https://feeds.arstechnica.com/arstechnica/index` | 200 | 73,448 | 0 | RSS | 20 |
| ProPublica | `https://www.propublica.org/feeds/propublica/main` | 200 | 511,009 | 0 | RSS | 20 |

All four channel titles came back from the documents themselves (`BBC News`,
`NPR Topics: News`, `Ars Technica - All content`, `ProPublica`). The full pipeline
then ran — fetch, parse, canonicalize, deduplicate, `robots.txt` check, Readability
extraction, persist:

```
SMOKE REFRESH BBC News: succeeded · 33 items · no error
SMOKE REFRESH NPR News: succeeded · 10 items · no error
SMOKE REFRESH Ars Technica: succeeded · 20 items · no error
SMOKE REFRESH ProPublica: succeeded · 20 items · no error
SMOKE EXTRACTION [(excerptOnly, 2), (feedOnly, 7), (full, 72), (paywalled, 1)]
```

82 articles persisted from the 83 feed items. **72 were fully
extracted into semantic blocks.** One page declared itself gated and fell back to the
publisher's excerpt with an honest status. Two could not be read and say why. Seven
were beyond the 25-newest-per-source resolution budget and kept their feed excerpt.

Note that this target is deliberately excluded from the `Broadsheet` scheme:

```yaml
Broadsheet:
  scheme:
    testTargets: [BroadsheetTests, BroadsheetUITests]
```

### 5. Install and launch on the simulator

```
xcrun simctl boot "iPhone 17"
xcrun simctl install booted .../Broadsheet.app
xcrun simctl launch booted com.helix.broadsheet     → com.helix.broadsheet: 10816
xcrun simctl io booted screenshot screenshots/private-beta/simctl-01-iphone-first-launch.png
```

Same sequence on `iPad Pro 13-inch (M5)` → `com.helix.broadsheet: 11400`.

### 6. Real screenshots

`screenshots/private-beta/` contains 18 screenshots. Two (`simctl-*`) are raw
simulator captures of a cold first launch. The rest were taken by the
`BroadsheetScreenshots` target, which drives the **shipping app against the real
network** — real BBC/NPR/Ars/ProPublica feeds, real article pages, real extraction:

```
xcodebuild test -scheme BroadsheetScreenshots \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath /tmp/Shots.xcresult
xcrun xcresulttool export attachments --path /tmp/Shots.xcresult --output-path …
```

| File | What it shows |
|---|---|
| `simctl-01-iphone-first-launch.png` | Cold first launch: masthead, "Nothing downloaded yet", 4 seeded sources |
| `simctl-02-ipad-first-launch.png` | Same on iPad Pro 13-inch |
| `live-01-first-launch.png` | First launch inside the driven run |
| `live-02-sources.png` | Sources screen with the four seeded feeds and their status |
| `live-03-today.png` | Today after a live refresh: BBC lead story with its own image, coverage cluster |
| `live-04-today-river.png` | The river |
| `live-06-reader.png` | Reader with extracted prose and `Read at …` above the hero |
| `live-07-reader-perspective.png` | Reader footer, perspective band, repeated canonical link |
| `live-08-analysis-sheet.png` | On-device analysis sheet |
| `live-09/10/11-*-dark.png` | Today, Library, Search in dark mode |
| `ipad-01…05-*.png` | The same flows on iPad Pro 13-inch with live content |

`ipad-03-today.png` is the clearest single piece of evidence: a real BBC News lead
story with its publisher image, and below it a coverage cluster that grouped BBC News
and NPR News reporting on the same event, built from live feeds by the deduplicator
and edition builder.

## What was built

### Persistence (`Broadsheet/Persistence/`)

`StoredSource`, `StoredArticle`, `StoredAnalysis`, and `StoredPreferences` behind a
`VersionedSchema` (`BroadsheetSchemaV1`, version 1.0.0) and a `SchemaMigrationPlan`
with no stages yet — named now so a future version can migrate rather than reset.
`BroadsheetStore` is the only thing that touches disk; it exposes an in-memory
container for tests and for UI-test runs. Semantic blocks are stored as encoded
`ArticleBlock` values, never as publisher HTML, so raw markup cannot reach the reading
surface from the cache either. Saved/read state, corrections, and analysis outcomes
all survive relaunch (`PersistenceTests` opens a second `ModelContext` over the same
container to prove it rather than reading back its own memory).

### Source registry (`Broadsheet/Sources/`, `Broadsheet/Features/Sources/`)

`FeedSource` keyed by a normalized feed URL that keeps the query — `?edition=int`
selects the edition, and dropping it would silently subscribe the reader to a
different feed. Add by direct URL or by pasting a publisher page, in which case
`FeedDiscovery` reads the `<link rel="alternate">` feeds the publisher advertises
(plus footer anchors that plainly point at a feed) and each candidate is fetched and
parsed before it can be saved. Sources screen supports add, rename, refolder,
enable/disable, refresh-one, and delete, with the last failure's verbatim reason on
the row. Starter seeding is idempotent twice over: a one-shot flag in the store, and
a unique feed-URL key. A deleted starter source never comes back.

### Networking (`Broadsheet/Networking/`)

HTTPS enforced on the original request and on every redirect hop; at most five
redirects; response bodies abandoned mid-stream once they exceed the cap rather than
after buffering; per-request timeouts; cookies off; a descriptive user agent
(`Broadsheet/1.0 (private beta; personal on-device news reader; RSS/Atom/JSON Feed)`);
and a typed `HTTPFetchError` that distinguishes transient failures from permanent
ones so a 503 keeps the cache and a 404 does not retry forever.

`RobotsPolicy` checks `robots.txt` before Broadsheet fetches an *article page*. A feed
the reader subscribed to is fetched because they asked for it; fetching the page
behind a feed item is closer to crawling, so it is gated on the publisher's own rules.
**An unreadable `robots.txt` is treated as "no", not as permission** — the reader
still gets the excerpt and the link.

### Parsing (`Broadsheet/Feeds/`)

JSON Feed 1.1 (and 1.0) added alongside the existing RSS/Atom parser, with format
chosen by sniffing the body rather than trusting the content type. `ArticleCanonicalizer`
provides deterministic canonicalization (tracking parameters, casing, ports, trailing
slashes, fragments) and deduplication: same-publisher reprints under a new URL collapse,
two publishers covering the same story do not. `ArticleCanonicalizerTests` asserts the
output is byte-identical under shuffled input.

### Article resolution (`Broadsheet/Extraction/`)

A fixed order with hard boundaries:

1. **Feed full content** — if the publisher put the article in the feed, that is the
   article and nothing is fetched.
2. **Openly accessible page** — only over HTTPS, only if `robots.txt` permits, only if
   the page does not declare itself gated. Mozilla Readability runs inside a
   `WKWebView` with a non-persistent data store, no cookies, no navigation, and a
   `WKContentRuleList` that blocks *every* subresource load, so no image, script,
   font, or beacon fires while the page is parsed.
3. **Feed excerpt**, with the reason attached and the publisher one tap away.

There is no fourth step. Broadsheet does not log in, accept a cookie wall, reset a
meter, strip an overlay, or read a gated page from a cache. `AccessGateClassifier`
reads schema.org's own `isAccessibleForFree: false`, `article:content_tier`, and
publisher gate markup, and is biased toward stopping: a false "restricted" costs a tap,
a false "open" would render something the publisher did not make free. A test asserts
that reporting *about* subscriptions is not misclassified as gated, and another
asserts a restricted page's fallback contains only the feed's own text.

Readability is vendored byte-for-byte from `mozilla/readability@d7949dc4` with its
Apache 2.0 `LICENSE.md` and a `NOTICE.md`; both are bundled inside the app, and a test
asserts the licence is present in the shipped bundle.

### Analysis

Analyzer selection is a boundary, not a fallback chain. `RefreshPipelineTests`
installs a recording analyzer in each slot and asserts the deterministic fixture
heuristic sees **zero** live articles and that every live result carries
`appleFoundationModels` provenance. Results and failures are both persisted, so after
relaunch the reader sees the same label — or the same honest reason — without
recomputation.

### UI

Today shows persisted live content and falls back to a plain "Nothing downloaded yet"
state rather than pretending. The demo edition is now an explicit toggle in Library,
never refreshed from the network, never written to the library, and labelled on
screen. Source failures surface as a banner with per-source reasons. Library gained
Sources management, cache counts, and a plain statement that there is no account,
server, or analytics. All of it is universal, both appearances, Dynamic Type, and
VoiceOver-labelled; a UI test drives the app at `AccessibilityL` in dark mode and
asserts the primary actions are still hittable.

## Foundation Models: what actually ran

The simulator's model catalog is intermittent. Over six live runs on 2026-07-30 the
same build produced two different worlds, and both are reported here.

**Runs where the model worked (12:52 and 13:05).** `SystemLanguageModel` reported
ready and real guided generation ran against 82 live articles:

```
SMOKE MODEL availability: Apple's on-device system language model is ready.
SMOKE ANALYSIS [(Center, 20), (Left, 2), (Right, 1), (unavailable, 59)]
SMOKE ANALYSIS unavailable ×55: Detected content likely to be unsafe
SMOKE ANALYSIS unavailable ×4:  There was not enough article text to analyze.
```

23 real labels with `appleFoundationModels` provenance, from real BBC, NPR, Ars
Technica, and ProPublica reporting. No fixture result was substituted for any of them.

**Runs after 13:15.** The catalog reported `com.apple.modelcatalog` had "no underlying
assets" (312 such errors in one run's log) while `availability` still said *ready*.
Every article then came back unavailable, and the app said so. The offline suite is
unaffected because it asserts the invariant — either the model ran and the result
carries its provenance, or an explicit error was surfaced — not the environment.

**The finding that matters: Apple's system model refused 55 of 82 live news articles.**
That is not a bug in Broadsheet; it is what the model does when asked to judge
political framing in reporting about conflict, crime, and politics. Two things were
done about it, and only one of them is measured:

- **Shipped.** The session now uses `SystemLanguageModel(guardrails: .permissiveContentTransformations)`,
  Apple's documented configuration for analyzing user-supplied content. Measured
  effect on this corpus: **none** — 55 refusals before, 55 after (52 surfaced as a
  refusal, 3 as an explicit guardrail violation). It is kept because it is the
  correct configuration for the use case, not because it helped here.
- **Not shipped.** Reframing the prompt from "estimate the political leaning" to a
  descriptive text-classification task is the obvious next experiment. It was written,
  and then reverted, because the simulator lost its model assets before it could be
  measured and an unmeasured prompt change is not an improvement. The measured prompt
  is what ships.

Error reporting was improved either way: `guardrailViolation`, `refusal`,
`unsupportedLanguageOrLocale`, `rateLimited`, and `concurrentRequests` now produce
plain sentences instead of "Detected content likely to be unsafe", and a generation
error that arrives bridged as an `NSError` (which the `as` cast misses) is reported
with its domain and code instead of "the operation couldn't be completed".

## Legal and product boundary

Nothing in this build bypasses a publisher's access controls.

- No login, no cookie-wall acceptance, no meter reset, no overlay removal, no
  headless "reader mode" trick against a gated page.
- The extraction `WKWebView` never navigates, never loads a subresource, has no
  persistent store and no cookies, and is handed HTML Broadsheet already fetched.
- `robots.txt` is honoured before any article-page fetch, and an unreadable
  `robots.txt` is treated as a refusal.
- 401 / 402 / 403 / 451 are treated as the publisher's answer, not as an obstacle.
- A restricted or unreadable page falls back to the feed excerpt only. Tests assert
  the fallback body is exactly the feed's text and that no text from behind a gate
  reaches the reader.
- Every article keeps its canonical link, shown above the hero and again in the footer.

## Independent review remediation

An independent Gemini review initially returned **BLOCK** on two findings. Both were fixed before the final test run:

1. The extraction `WKNavigationDelegate` had allowed any `.other` navigation. It now grants exactly one main-frame `.other` navigation for `loadHTMLString` to create the in-memory document, consumes that permit before allowing it, and cancels every subsequent action. Publisher `window.location` code can no longer escape the hidden WebKit document. A regression test covers the single-use permit, subframes, later `.other` actions, and user link navigation.
2. Near-duplicate deduplication previously covered only one incoming refresh batch. `BroadsheetStore` now indexes the persisted cache by the same publisher-domain plus normalized-headline key before every transaction. A republished story at a new URL updates the stable existing row and preserves save/read state, analysis, and manual correction. A two-refresh regression test proves the store remains at one row.

The final post-remediation run passed **256 unit tests and 12 UI tests** with zero failures.

## Honest remaining blockers

**Physical-device signing has not been done and cannot be done here.** Every build in
this report used `CODE_SIGNING_ALLOWED=NO` against the simulator. To put this on
Brian's iPhone and iPad someone must, on a Mac with the hardware attached:

1. Add an Apple Developer team and set `DEVELOPMENT_TEAM` in `project.yml`.
2. Register both devices and let Xcode create a development provisioning profile for
   `com.helix.broadsheet`.
3. Build and run on-device with signing enabled.

None of that is testable from here, and none of it has been claimed.

**On-device model latency has not been benchmarked**, and the simulator numbers are
not a substitute. `ARTICLE-BIAS-ENGINE.md` requires eager analysis to finish before the
card appears; whether it does depends entirely on hardware inference speed. The 82
-article refresh above took 105 s wall-clock in the simulator *including* network and
extraction, which tells you nothing useful about an A19.

**The refusal rate is the real product risk.** With the measured prompt, roughly
two thirds of live articles get no estimate. `PRODUCT.md` calls the article-level
label a core function. Either the prompt has to be reframed and re-measured on
hardware, or the bundled Core ML classifier from `ARTICLE-BIAS-ENGINE.md` has to
land — it is the part of the architecture that is still missing, and it is also what
would cover devices without Apple Intelligence.

**Other limitations, unchanged or new:**

- **No Core ML relevance gate or lean classifier.** Only the Foundation Models judge
  and the demo-only fixture heuristic exist. Devices without Apple Intelligence report
  analysis unavailable for live articles.
- **Confidence is not calibrated** and no publisher-held-out evaluation has been run.
- **Resolution is capped at the 25 newest items per source per refresh.** Older items
  keep their feed excerpt. BBC's 33-item feed is why 7 articles show as feed-only above.
- **No iPad three-column `NavigationSplitView`.** The app is universal and constrains
  the reading measure to 700 pt, but the sidebar/list/reader layout from the shape
  brief is not built.
- **Publisher baselines are absent for live sources.** `FeedArticleMapper` leaves the
  baseline `nil` because Broadsheet has no rating data for an arbitrary URL, so the
  coverage strip shows live sources as unrated. The demo edition's baselines remain
  fictional.
- **A publisher's own future-dated `pubDate` can lead the edition.** BBC schedules some
  items ahead; Broadsheet renders the publisher's timestamp rather than second-guessing
  it, so such an item sorts to the top.
- **UI-test fixture content ships in the app binary** (`Broadsheet/Testing/`), reachable
  only behind a launch argument the test runner passes. It is compiled into the release
  binary today and should move to a test-only target before any real distribution.
- **The UI suite takes about 200 s** because it drives real scrolling, real refreshes,
  and real WebKit extraction.

## Files

New: `Broadsheet/Persistence/`, `Broadsheet/Networking/`, `Broadsheet/Sources/`,
`Broadsheet/Extraction/`, `Broadsheet/Refresh/`, `Broadsheet/Testing/`,
`Broadsheet/Features/Sources/`, `Broadsheet/Content/EditionBuilder.swift`,
`Broadsheet/Feeds/JSONFeedParser.swift`, `Broadsheet/Feeds/ArticleCanonicalizer.swift`,
`BroadsheetNetworkSmokeTests/`, `BroadsheetScreenshots/`, and seven new test files
plus shared test support.

Modified: the app entry point, `AppModel`, `BiasAnalysisService`,
`FoundationModelsBiasAnalyzer`, `ExtractionStatus`, `FeedParser`/`FeedArticleMapper`,
Today/Library/Search/Reader, the theme, and `project.yml`.
