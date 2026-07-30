# Broadsheet Private Beta Plan

**Goal:** Turn the verified native MVP into a daily-use, local-first private beta that loads real news, persists state, renders accessible article content in Broadsheet's house style, and precomputes article-level local bias estimates.

## Binding boundaries
- Preserve publisher access controls. Do not bypass authentication, subscriptions, metered access, overlays, robots restrictions, or technical access controls.
- Use full-content feeds, openly accessible article HTML, official APIs, and publisher-permitted content.
- When content is unavailable or restricted, retain the feed excerpt and prominently offer the original publisher page.
- No cloud AI, analytics, advertising, accounts, or server backend.

## Task 1: Persistent local store
**Files:** `Broadsheet/Persistence/**`, app bootstrap, tests
1. Add SwiftData entities for sources, cached articles, saved/read state, user corrections, and analysis results.
2. Store semantic `ArticleDocument` data without losing original-source metadata.
3. Add in-memory test configuration and migration-safe schema versioning.
4. Prove state survives a fresh model-context fetch.

## Task 2: Source registry and management
**Files:** `Broadsheet/Sources/**`, Library/source-management UI, tests
1. Add `FeedSource` with title, feed URL, site URL, folder, enabled state, and last-refresh status.
2. Add source by direct RSS/Atom/JSON Feed URL or discover `<link rel="alternate">` feeds from a publisher page.
3. Validate HTTPS URLs, response types, redirects, size limits, and parser compatibility before saving.
4. Seed four verified, editable starter sources on first launch: BBC News, NPR News, Ars Technica, and ProPublica.
5. Provide add, edit, enable/disable, folder, refresh, and delete controls.

## Task 3: Live refresh pipeline
**Files:** networking, RSS/Atom/JSON Feed parsers, refresh coordinator, tests
1. Fetch enabled feeds with bounded concurrency, timeouts, redirect limits, and a clear user agent.
2. Add JSON Feed 1.1 parsing.
3. Canonicalize and deduplicate articles across refreshes.
4. Persist refresh outcomes and article cache atomically.
5. Keep prior content available when a refresh fails.

## Task 4: Accessible article resolution
**Files:** extraction/resolution pipeline, semantic normalization, fixtures/tests
1. Prefer full article content supplied directly by feeds.
2. For openly accessible pages, use a vendored, licensed Mozilla Readability extraction path in WebKit and preserve its license.
3. Normalize headline, dek, author, date, paragraphs, headings, images, captions, quotes, lists, and relevant links into `ArticleDocument`.
4. Detect inaccessible/restricted/insufficient pages conservatively and fall back to the feed excerpt plus original-source action.
5. Never automate login, cookie-wall acceptance, subscription prompts, meter resets, overlay removal, or access-control evasion.

## Task 5: Eager local analysis
**Files:** refresh pipeline, bias service, persistence, tests
1. Sanitize extracted article text before analysis.
2. Schedule Foundation Models analysis after extraction and cache its result before display when possible.
3. Surface unavailable/error states honestly; never run the fixture heuristic on live reporting.
4. Persist labels, confidence, rationale, verified evidence, engine version, and corrections.
5. Keep the publisher baseline independent from the article estimate.

## Task 6: Daily-use UI
**Files:** Today, Library, Search, source settings, status components, UI tests
1. Replace the normal demo edition with cached live articles; keep the demo as an explicit offline preview only.
2. Show refresh progress and source-level failures without losing the editorial hierarchy.
3. Add source and folder management in Library.
4. Search persisted live content and saved stories.
5. Verify light/dark mode, dynamic type, VoiceOver, iPhone, and universal iPad layout.

## Verification
- Run parser, persistence, discovery, networking-fixture, extraction-fixture, deduplication, analysis-cache, and UI tests.
- Build with code signing disabled on iPhone and iPad simulators.
- Exercise first launch, starter-source refresh, add-source, offline relaunch, save/search, article reader, and restricted-content fallback.
- Capture actual simulator screenshots and write `PRIVATE-BETA-REPORT.md` with real outcomes and remaining physical-device/signing work.
