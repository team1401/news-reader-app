# Product: Private Native News Reader

**Working title:** Broadsheet (temporary)
**Register:** Product
**Primary user:** Brian, a technically sophisticated full-time traveler who reads on iPhone and iPad and wants a calm, premium news experience without ads, sponsored content, subscriptions to an aggregator, or opaque engagement algorithms.

## Product purpose

Publishers provide the journalism. This app provides the reading experience. It collects explicitly chosen sources, extracts legitimate article content, converts it to a semantic document, and renders every story in one consistent native design. Every article clearly credits and links to its original publisher.

## Non-negotiable requirements

- Private native Apple app, iPhone and iPad first.
- SwiftUI reading surface, not publisher HTML or CSS.
- Configurable RSS, Atom, JSON Feed, and website feed discovery.
- Native house formatting for headline, dek, byline, dates, paragraphs, headings, figures, captions, lists, quotations, links, and supported embeds.
- Remove advertising, sponsored modules, newsletter nags, trackers, navigation, and unrelated recommendation widgets from the reading surface.
- Original publisher attribution and canonical link above the article and again in its footer.
- Never bypass paywalls or access controls. When content is unavailable, show the legitimate excerpt and hand off to the publisher.
- An immediately visible **article-level bias label** is a core function, not optional metadata. The app must examine each extracted article locally and classify it as Left, Center, Right, or N/A before or as it becomes readable. The article estimate and the publisher's separate source baseline must never be conflated. Every estimate needs an on-device-analysis provenance indicator, confidence, model version, and an explanation surface.
- No engagement ranking, social layer, public profiles, advertising, sponsored placement, telemetry, or recurring app subscription.
- Local-first storage. Optional sync later should include sources and reading state, not publisher article bodies.

## Product principles

1. One house design across every article.
2. Preserve reporting semantics, discard publisher chrome.
3. Bias is context, not a verdict.
4. The publisher is always visible and one tap away.
5. Explicit curation beats behavioral personalization.
6. Quiet, fast, accessible, and useful offline.
7. Extraction quality is a visible product metric, not a hidden implementation detail.

## Primary surfaces

- **Today:** Editorial river plus multi-source story clusters when confidence is high.
- **Library:** Sources, folders, saved stories, history, downloaded items, and source health.
- **Search:** Local full-text search and add-source discovery.
- **Article reader:** The core product, fully native and consistently typeset.
- **Perspective details:** Provenance and methodology for political labels.

## Technical direction established by research

- SwiftUI app targeting current iOS/iPadOS.
- GRDB/SQLite and FTS5 for durable unique constraints, deduplication, migrations, and local search.
- FeedKit for RSS/Atom/JSON Feed.
- Feed full text first, then structured metadata and headless semantic extraction, with rendered DOM extraction only as a controlled per-source fallback.
- Typed ArticleDocument blocks are the rendering source of truth. Raw publisher HTML never reaches the native reading surface.
- Canonical URL, content hash, and near-duplicate detection.
- A local article-bias engine in the first usable version. Start with Apple's on-device Foundation Models framework where available, backed by a bundled Core ML classifier for unsupported devices and for controlled evaluation. Strip publisher identity from model input, classify semantic article chunks, aggregate results, calibrate confidence, and cache the result with the article.

## Anti-references

- Apple News ads, sponsored content, closed source links, and aggregator subscription.
- Generic RSS readers made from identical cards.
- Ground News-style political scoring that visually dominates the reporting.
- Literal skeuomorphic newspaper or desk decoration.
- Red-versus-blue tribal color coding.
- AI summaries or political verdicts presented with false certainty.

## Success criteria for the first usable version

- Add a source by URL and preview its extracted output.
- Refresh feeds and deduplicate repeated items.
- Open a story into a polished native reader.
- Correctly render common article structures and images.
- Open the canonical publisher article from the top and bottom of the reader.
- Handle feed-only, partial, failed, and paywalled articles honestly.
- Read, save, restore position, search locally, and use the app at accessible Dynamic Type sizes.
- Every readable article receives an immediately visible Left, Center, Right, or N/A article label from local analysis. Source baseline remains separately available with provenance.
- Extraction failures are diagnosable per source.
