# Broadsheet MVP Implementation Plan

**Goal:** Build a runnable private iPhone/iPad SwiftUI vertical slice using the selected Gemini visual direction, native article rendering, configurable RSS/Atom sources, and immediately visible article-level on-device Left/Center/Right/N/A analysis.

**Assumptions**
- Working product name is `Broadsheet`; bundle ID and signing team remain replaceable.
- Minimum deployment target is iOS/iPadOS 18. Foundation Models support is enabled conditionally on iOS 26+ and falls back to an explicit local-analysis-unavailable state until a compact Core ML model is bundled.
- The first runnable slice uses bundled fixtures for deterministic UI/tests and can ingest user-supplied RSS/Atom URLs. It does not bypass paywalls or republish content.
- No cloud backend, analytics, account, or remote AI.

## Architecture
- SwiftUI app generated with XcodeGen.
- Feature-oriented source tree with models, services, bias engine, design system, and screens.
- Semantic `ArticleDocument` blocks drive the native reader.
- `FeedParser` handles RSS and Atom using `XMLParser`.
- `BiasAnalyzing` protocol has an Apple Foundation Models implementation and deterministic fixture implementation for previews/tests.
- Analysis is scheduled during ingestion and cached with article state so the badge is ready before display.

## Task 1: Scaffold and compile
**Files:** `project.yml`, `Broadsheet/**`, `BroadsheetTests/**`
1. Create XcodeGen project and app/test targets.
2. Add app entry point and design tokens.
3. Generate the Xcode project.
4. Build for an available iPhone simulator.

## Task 2: Models and feed ingestion (TDD)
**Files:** models, feed parser/service, XML fixtures, parser tests
1. Write failing RSS and Atom parser tests.
2. Implement the smallest parser that passes.
3. Add canonical URL and stable article identity handling.
4. Rerun targeted tests.

## Task 3: Semantic reader (TDD where functional)
**Files:** `ArticleDocument`, sample fixtures, `ArticleReaderView`
1. Define headline metadata and semantic content blocks.
2. Render paragraphs, headings, images, captions, quotes, lists, and links natively.
3. Place source attribution and `Read at [Publisher]` above the hero and in the footer.
4. Verify light/dark layouts in previews/simulator.

## Task 4: Local bias analysis
**Files:** bias models/analyzers/pipeline/tests
1. Write tests for label parsing, N/A abstention, and source-identity removal.
2. Implement `BiasAnalyzing` and cached analysis pipeline.
3. Add Foundation Models structured-generation implementation behind availability checks.
4. Ensure model input excludes publisher, domain, author, and source baseline.
5. Expose label, confidence, rationale, evidence, model provenance, and correction UI.

## Task 5: Selected Gemini UI
**Files:** Today, article, library, search, shared components
1. Recreate the approved editorial hierarchy in native SwiftUI rather than embedding HTML.
2. Keep article bias labels visible on every story card and at the top of the reader.
3. Keep publisher baseline secondary and separately attributed.
4. Include Today, Library, and Search tabs; support iPad layout.

## Task 6: Verification
1. Generate project with `xcodegen generate`.
2. Run unit tests with `xcodebuild test` on an available simulator.
3. Build app with `xcodebuild build` and no code signing.
4. Install and launch on a simulator, capture screenshots, and inspect visual output.
5. Run an independent code/design review and fix blocking findings.
