# Gemini visual probe

Create a high-fidelity, static HTML/CSS visual prototype to help Brian choose the product shape before SwiftUI implementation.

## Read first
- `/Users/helix/.Hermes/workspace/news-reader-app/PRODUCT.md`
- `/Users/helix/.Hermes/workspace/news-reader-app/SHAPE-BRIEF.md`
- `/Users/helix/.Hermes/workspace/news-reader-app/research/gemini/REPORT.md`

## Write boundary
Write only under `/Users/helix/.Hermes/workspace/news-reader-app/prototypes/gemini/`.

## Deliverables
- `index.html`: realistic iPhone Today/feed screen at 390px width.
- `article.html`: realistic iPhone article-reader screen using the same design system.
- `README.md`: concise design rationale and deliberate tradeoffs.
- Standalone HTML/CSS/vanilla JS only. No build step. It must render from a local HTTP server.

## Required content and behavior
- This is a real product UI, not a marketing page, poster, or moodboard.
- Use realistic fixture journalism and source metadata, but do not imitate publisher logos.
- Today must have varied editorial hierarchy, not identical cards.
- No For You tab, engagement scoring, glass, gradient text, red-vs-blue tribal coding, giant decorative masthead, literal wood/leather decoration, circular political balance wheel, or image color filters.
- Article reader must be the star and include headline, dek, byline/date, source baseline with provenance affordance, article status `Not assessed`, hero image/caption/credit, headings, paragraphs, blockquote, inline figure, and original-publisher actions near the top and bottom.
- Political context must be quiet and secondary to reporting.
- Use system-safe serif/sans stacks. No remote font dependency.
- Responsive enough to remain coherent at 430px.
- Include links between index.html and article.html.
- Strong accessibility semantics and visible focus states.
- No em dashes in UI copy.

## Design lane
Be more visually ambitious than the Claude lane while remaining believable as a premium native Apple product. Keep the calm editorial ethos but create a distinctive composition, thoughtful image rhythm, and one memorable non-gimmicky signature detail. Fix the flaws of the earlier Quiet Desk image: cramped masthead/date, oversized brand, overflowing category row, verdict-like bias chips, repeated headline, and lack of imagery.

Do not publish, push, install dependencies, access secrets, or modify production files. Verify both pages exist and are syntactically coherent before finishing.