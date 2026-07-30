# Claude research lane: private native news reader

## Working directory
Write only under `/Users/helix/.Hermes/workspace/news-reader-app/research/claude/`.

## Goal
Produce a rigorous product/UX and technical architecture brief for a private, native Apple news reader that feels as polished as Apple News but has no ads, sponsored placements, or app subscription. It must ingest easily configurable sources, normalize every article into one house reading design, show political leaning (left/center-left/center/center-right/right/N/A, with confidence and source-vs-article distinction), and include prominent links to original publisher articles.

## Confirmed constraints
- Private personal app, initially iPhone and iPad, SwiftUI preferred.
- Local-first; optional iCloud later.
- Articles render in our native formatting, not publisher web formatting.
- Preserve headline, dek, byline, dates, body structure, images/captions, lists, blockquotes, links, and useful embeds.
- Remove ads, sponsored modules, nags, trackers, nav, and unrelated recommendations.
- Never bypass paywalls. Attribute publishers clearly and link to the original at top and bottom.
- Configurable RSS/Atom/JSON Feed and website/feed discovery.
- No external publishing, account changes, purchases, pushes, PRs, or secrets.
- This is research/shape work only. Do not create production UI or code yet.

## Deliverable
Create `/Users/helix/.Hermes/workspace/news-reader-app/research/claude/REPORT.md` containing:
1. Product principles and anti-goals.
2. Proposed screen/information architecture and key interactions.
3. Article-reader experience in enough detail to guide a visual prototype.
4. Technical architecture for feeds, article extraction, semantic normalization, native rendering, deduplication, offline cache, bias classification, and direct-source links.
5. Extraction failure/paywall/embed handling.
6. Legal/privacy risks for a private personal reader and practical mitigations (not legal advice).
7. MVP vs later scope.
8. Top unanswered decisions, but make reasonable defaults rather than asking basic questions.
9. A skeptical self-review: where this could fail or become expensive.

Be opinionated, concrete, concise, and avoid generic SaaS patterns. Do not claim Apple-private APIs are available without evidence.