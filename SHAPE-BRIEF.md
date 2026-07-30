# Shape Brief: Broadsheet Native News Reader

**Status:** Proposed for Brian's confirmation before implementation
**Register:** Product

## Product shape

A private iPhone and iPad reader that feels editorial rather than app-dashboard-like. It opens into a composed news river, but the article reader is the product's center of gravity. The interface should feel quiet and premium without becoming nostalgic, decorative, or precious.

## Physical scene

Brian opens the app early in the Airstream with daylight changing around him, then returns to a saved long-form article at night. The interface must remain calm, legible, and restrained in bright daylight and dim evening conditions without changing the publisher's photography or turning the app into a literal paper simulation.

## Recommended design direction

Use Claude's information architecture and reader rigor as the foundation. Keep only the useful restraint from Gemini's "Quiet Desk" direction: warm tinted neutrals, serif content typography, flat editorial rows, and muted perspective colors. Reject the literal desk metaphor, image warming filters, oversized app masthead, circular balance wheel, and political badges that compete with headlines.

### Visual strategy

- Restrained palette: slightly warm light neutral, deep slate dark neutral, one quiet interface accent.
- Editorial serif for reporting; native system sans for controls and metadata.
- Varied hierarchy rather than identical cards: lead story, compact clusters, and a chronological river.
- Publisher photography remains color-accurate. Never apply aesthetic warmth filters.
- Dividers and whitespace provide structure. Shadows are rare.
- Motion is brief and functional: article continuity, saved-state confirmation, progress, and no decorative page-turn theater.

## Navigation

### iPhone

Three native tabs:
1. Today
2. Library
3. Search

No "For You" tab. There is no behavioral recommendation engine.

### iPad

Three-column NavigationSplitView:
- Sidebar: Today, folders, sources, saved, history.
- Story list.
- Article reader.

Support keyboard shortcuts and opening two related articles side by side later.

## Today shape

- Date and a compact product identity, not a huge masthead.
- One lead story or story cluster when justified by source coverage.
- Multi-source clusters show a subtle perspective-distribution strip only when enough rated sources exist.
- Remaining stories appear in a chronological editorial river with varied image placement.
- The article-level Left, Center, Right, or N/A label stays immediately visible in the feed and article header as a core navigation signal. It should feel integrated with the editorial hierarchy rather than decorative, and it must identify itself as an on-device estimate rather than an objective verdict.
- Pull to refresh. Content remains usable while extraction completes.

## Article-reader shape

Vertical anatomy:
1. Native navigation controls and reading settings.
2. Publisher name plus an immediately visible article-level Left, Center, Right, or N/A label with confidence/provenance affordance. The publisher's source baseline remains separate.
3. Headline and dek.
4. Byline, published/updated dates, reading time.
5. Prominent `Read at [Publisher]` canonical-source action above the first body block.
6. Lead image with accurate aspect ratio, caption, and credit.
7. Semantic native blocks: paragraphs, headings, lists, quotations, figures, dividers, code, tables, footnotes, and safe embed cards.
8. Perspective section near the end: the article-level local-AI estimate, confidence, evidence/rationale, model version, and a separately attributed publisher baseline.
9. Full-width `Read the original at [Publisher]` action.
10. Clear attribution statement and related coverage when available.

Reader settings remain minimal: text size, serif/sans body, and Paper/Night/OLED themes. Dynamic Type and VoiceOver are first-class.

## Political-context treatment

- Use position, wording, and provenance before color.
- Muted sage-to-ochre-to-terracotta spectrum may support scanning, but labels must remain understandable without color.
- Keep the article bias label immediately visible. Show source baseline and article assessment separately.
- Source rating text includes provider and date in the detail sheet.
- Article-level local assessment is required in the first usable version. Use Left, Center, Right, or N/A, with N/A covering nonpolitical material, insufficient content, and calibrated abstention.
- If providers disagree materially, show disagreement instead of averaging.
- Story-cluster perspective distribution is more valuable than pretending every article has a precise ideological coordinate.

## Extraction and failure states

- Full: native reader.
- Partial: render legitimate extracted blocks and state that the complete article could not be read.
- Feed only: render publisher-supplied excerpt and image.
- Paywalled: show free portion, explain the boundary, and open the publisher in an authenticated Safari view.
- Failed: say the story must be read at the publisher and offer a local formatting-problem report.

## First implementation slice after approval

Build a disposable but runnable SwiftUI spike with:
- Today river using realistic fixture data.
- One long-form native article containing all primary block types.
- Source links at top and bottom.
- Prominent article-level bias label with an on-device-analysis provenance sheet, plus a separate source baseline.
- Light and dark themes.
- iPhone and iPad layouts.

Claude and Gemini should each receive this approved brief and build isolated visual prototypes. Helix will build/run both, capture screenshots, critique them, and merge the strongest direction before the ingestion engine is implemented.

## Explicitly out of this first visual slice

Live feeds, production extraction, database migrations, CloudKit, story-clustering algorithms, notifications, sharing extracted text, and App Store distribution. The visual slice must still include realistic mocked states for the required local article-bias engine.

## Approval question

Approve this shape as written, or identify what should change before the two visual prototypes are built.
