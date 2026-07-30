# Broadsheet — product/UX and architecture brief

*A private, native iPhone/iPad news reader. No ads, no sponsorship, no subscription, no accounts.
Working title: **Broadsheet**. Research/shape document — no production code proposed here.*

Date: 2026-07-30 · Target: iOS/iPadOS 26.4+ (SwiftUI), one developer, personal use.

---

## 0. The one-paragraph thesis

Apple News is polished because it owns the rendering format — publishers submit Apple News Format and
Apple lays it out. We can't get that, so the entire product hinges on one thing: **a semantic
extraction pipeline good enough that our own block-level document model becomes the source of truth
for rendering.** Everything else — typography, bias chips, dedup, offline — is downstream of whether
extraction produces clean structured documents at a high enough rate. If extraction lands at 90%+ on
a curated set of ~40 sources, this is a genuinely better reading experience than Apple News. If it
lands at 60%, it's a worse RSS reader with extra steps. Section 9 is honest about that risk.

---

## 1. Product principles and anti-goals

### Principles

1. **One house design, no exceptions.** Every article renders in Broadsheet's typography and layout.
   Publisher CSS, publisher fonts, publisher JS never touch the reading surface. A NYT piece and a
   Substack post look like siblings. This is the product.
2. **Semantics preserved, chrome discarded.** A blockquote stays a blockquote; a photo keeps its
   caption and credit; a numbered list keeps its numbering. What's removed is *not content*: ads,
   sponsored modules, newsletter nags, related-content rails, share widgets, trackers, nav.
3. **The publisher is always one tap away and always named.** Prominent "Read at *publisher*" at the
   top of the article and again at the bottom. Publisher wordmark/name in the byline row. We are a
   reading client for content we have a right to read, not a republishing platform.
4. **Never bypass a paywall.** No archive mirrors, no Googlebot user-agent spoofing, no cookie/JS
   games, no AMP-URL laundering. If content is gated, we show what the feed gave us and hand off.
   This is a hard product rule, not a setting.
5. **Bias is context, not a verdict.** Show it, source it, date it, and show uncertainty honestly.
   `N/A` is a first-class, common, respectable answer.
6. **Local-first and quiet.** No account, no telemetry, no push notifications, no badge counts, no
   streaks, no "You're all caught up!" confetti. The app has no interest in your attention.
7. **Reading state is sacred; everything else is disposable.** Read/saved/annotations survive. Caches,
   extractions, and classifications can be nuked and rebuilt at any time.

### Anti-goals (explicit non-features)

- No social layer, comments, sharing feed, follower graph, or public profiles.
- No algorithmic engagement ranking. Ordering is recency + your explicit source priorities + story
  clustering. No implicit behavioral model deciding what you see.
- No in-app web browsing as a primary path. WKWebView appears only in a clearly-labeled "publisher
  page" sheet, never as the reading surface.
- No AI summaries in the default reading path. An optional, explicitly-invoked "brief me" action is
  acceptable; auto-summarizing every article both misrepresents the writing and burns battery.
- No notifications, breaking-news alerts, or background nagging.
- No multi-user, no sharing, no server. There is no backend to compromise.
- No "read later" service integrations in v1 (Instapaper/Readwise/Pocket-likes). Broadsheet *is* the
  read-later.
- No cross-publisher full-text search index sold as "research". It's a personal reader.

---

## 2. Information architecture and key interactions

### Navigation shell

**iPhone** — three tabs, no more.

| Tab | Contents |
|---|---|
| **Today** | The default surface. Story clusters + river. |
| **Library** | Sources, Folders, Saved, History, Downloaded. |
| **Search** | Full-text over cached articles + "add a source" entry point. |

**iPad** — `NavigationSplitView`, three columns: sidebar (Today / Saved / History / folder tree /
sources) → list column (story cards) → detail (reader). Keyboard-first: `j/k` next/prev, `Space`
page, `s` save, `o` open at publisher, `⌘F` find in article, `⌘⇧D` download. Pointer hover reveals
row actions. Multi-window supported (drag an article to a new window for side-by-side comparison of
two sources on the same story — this is genuinely useful given the bias framing).

### Today

Not a raw river. Three bands, top to bottom:

1. **Lead** — 1–3 story *clusters* with the widest cross-source coverage in the last ~18h. Large
   card: dominant image, headline from your preferred source in the cluster, `N sources` pill, and a
   **spectrum strip** (see below).
2. **Clusters** — remaining multi-source stories from the window, compact cards.
3. **From your sources** — everything else, reverse-chronological, grouped by day with sticky date
   headers. Single-source items live here.

A per-band collapse control and a "Just the river" toggle in settings for days when clustering
annoys you. Pull-to-refresh; a thin top progress hairline during fetch; never a blocking spinner.

### The spectrum strip (the signature UI element)

For a story cluster, a horizontal 5-segment bar (L / CL / C / CR / R) where each segment's height or
opacity encodes how many of the covering sources sit there. Tapping a segment filters the cluster's
source list. This turns bias data into something *useful* — "this story is only being covered on one
side" is real information, and it's information Apple News structurally will not give you.

Rules: the strip only appears when ≥3 sources are in the cluster and ≥2 have rated leanings.
Unrated sources appear in a separate `N/A` tail segment, never silently dropped — dropping them
would make coverage look more balanced than it is.

### Story cluster detail

Headline, one-line dek, spectrum strip, then the source list ordered by *your* priority (not by
bias). Each row: publisher, headline (they differ, often revealingly), bias chip, published time,
read/unread. Tap → reader. Long-press → "Open at publisher". A `Compare headlines` view stacks just
the headlines with publisher + leaning — cheap to build, disproportionately interesting.

### Library

- **Sources**: list with health indicator (last successful fetch, extraction success rate over last
  20 items, average items/day). A source that has been failing for a week says so, loudly. This is
  the maintenance surface and it should be blunt.
- **Add source**: paste any URL. Discovery pipeline (§4.1) resolves it to candidate feeds and shows
  a preview of the last 3 items *already rendered in house style* before you commit. That preview is
  the honest way to find out whether a source will extract well.
- **Folders**: manual grouping only (Politics / Tech / Local / Longform). No auto-tagging in v1.
- **Saved / History / Downloaded** as filtered views over the same store.

### Interaction details that matter

- **Unread is opt-in per source.** Wire services generate hundreds of items/day; treating them as
  "unread debt" ruins the app. Per-source setting: `Track unread` / `Ambient` (never shows a count).
- **Swipe left**: Save. **Swipe right**: Mark read / unread. Nothing else. No swipe-to-delete —
  articles age out on their own.
- **Long-press card** → context menu with a live preview of the *rendered* article, not a web
  screenshot.
- **Mark-all-read** is per-band and requires confirmation only above 50 items.

---

## 3. The reader — enough detail to prototype

Target: a single scroll view, `LazyVStack`, no web view, no publisher assets except images the
article itself contains.

### Vertical anatomy

```
┌─────────────────────────────────────────────────────┐
│  ← Back                     Aa   ⤓   ⋯              │  translucent, auto-hides on scroll
├─────────────────────────────────────────────────────┤
│                                                     │
│  [PUBLISHER WORDMARK/NAME]  ·  Center-Left ⓘ        │  source-level leaning chip
│                                                     │
│  A Headline Set in New York,                        │  38/42pt, serif, -0.5 tracking
│  Two or Three Lines Deep                            │
│                                                     │
│  The dek sits here in a lighter weight and a        │  20/28pt, serif, secondary
│  slightly warmer grey, one or two sentences.        │
│                                                     │
│  By Jane Doe and Sam Roe · Jul 29, 2026 · 8 min     │  15pt SF, tertiary
│  Updated Jul 30, 9:14 AM                            │  only when update ≠ publish
│                                                     │
│  ╭───────────────────────────────────────────────╮  │
│  │  ↗  Read at The Publisher                     │  │  PRIMARY. Bordered prominent.
│  ╰───────────────────────────────────────────────╯  │  full-width, always above the fold
│                                                     │
│  ▓▓▓▓▓▓▓▓▓▓▓ lead image ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓   │  edge-to-edge, aspect-preserved
│  Caption in 14pt. Credit in 12pt, tertiary.         │
│                                                     │
│  Body paragraph one, 19pt New York, 1.55 line       │  measure clamped to ~68ch
│  height, 20pt paragraph spacing, no first-line      │
│  indent, ragged right.                              │
│                                                     │
│  ## A Section Heading                               │  24pt semibold serif
│                                                     │
│  ▏ A blockquote, hairline rule on the leading       │
│  ▏ edge, italic, inset 16pt.                        │
│                                                     │
│  [ native embed card: X post / YouTube / chart ]    │  never a live iframe inline
│                                                     │
│  ─────────────────────────────────────────────      │
│  Article leaning: Not assessed  ⓘ                   │  article-level, honest default
│  Source rating: Center-Left — AllSides, Mar 2026 ⓘ  │  provenance + date, always
│  ─────────────────────────────────────────────      │
│                                                     │
│  ╭───────────────────────────────────────────────╮  │
│  │  ↗  Read the original at The Publisher        │  │  repeat, full width
│  ╰───────────────────────────────────────────────╯  │
│  Reported by The Publisher. Broadsheet reformats    │
│  articles for reading; text and images belong to    │
│  the publisher.                                     │
│                                                     │
│  ── Other coverage of this story ──                 │
│  [source rows with leaning chips]                   │
└─────────────────────────────────────────────────────┘
```

### Typography system

- **Body/headline: New York** (Apple's system serif, `Font.system(.body, design: .serif)`) — it's
  designed for reading, ships with the OS, needs no licensing, and supports full Dynamic Type and
  optical sizing. **UI chrome: SF Pro.** The serif/sans split is what makes it read as "designed"
  rather than "themed".
- **Dynamic Type is mandatory**, including accessibility sizes. Every size above is expressed as a
  relative text style, never a fixed point size. At AX sizes the measure clamp relaxes and the
  headline drops to two-thirds scale ratio.
- **Measure**: `min(680pt, containerWidth - 2*margin)` on iPad; full width minus 20pt on iPhone.
  Never let a 1024pt iPad column run body text edge to edge.
- **Reader settings (`Aa`)**: size (inherits Dynamic Type as default, ±3 steps), theme
  (Paper / Sepia / Night / Black-OLED), and a single `Serif ⇄ Sans` toggle for body. That's it.
  Four knobs, not fifteen. No line-height slider, no font picker, no width slider.
- **Themes** are semantic color sets, not inverted images. Night theme dims images to ~85%
  brightness via an overlay so a white infographic doesn't strobe.

### Block rendering rules

| Block | Rendering |
|---|---|
| `paragraph` | `Text(AttributedString)` with inline marks: em, strong, code, link, sup/sub, small-caps. |
| `heading(2..4)` | Serif semibold, 32/24/20pt scale, extra leading above. |
| `list(ordered/unordered, depth)` | Hanging indent, custom markers (`•` `–` at depth 2, `1.` `a.`). |
| `blockquote` | Leading hairline rule + inset, italic. Nested → deeper inset only. |
| `pullquote` | Larger serif, centered, generous vertical space, no rule. Distinct from blockquote. |
| `figure` | Async image, aspect-ratio placeholder to prevent layout jump, caption + credit below. Tap → full-screen zoomable viewer with pinch/pan. |
| `gallery` | Horizontal paging strip with dots; tap → viewer. |
| `table` | Native grid; horizontally scrollable with pinned first column; degrade to a "View table" sheet if >4 columns. |
| `code` | SF Mono, tinted background, horizontal scroll, no syntax highlighting. |
| `divider` | Hairline, 60% width, centered. |
| `aside` / `factbox` | Tinted rounded container, slightly smaller type. |
| `footnote` | Superscript marker; tap → popover, not a jump. |
| `embed` | Native card (§5.3). |

### Reading affordances

- **Scroll progress**: a 2pt hairline at the very top of the screen, no percentage numbers.
- **Position restore** per article, keyed by block index + intra-block offset (survives re-extraction
  and font size changes, which a raw scroll offset does not).
- **Text selection** enabled with a custom menu: Copy, Highlight, Define, Share (share always
  includes the publisher URL, never our extracted text).
- **Highlights** stored as `(blockID, characterRange, color)` against a stable block ID so a
  re-extraction can be diffed and highlights re-anchored or flagged as orphaned.
- **Estimated reading time** from body word count at 240 wpm, floored at 1 min. Shown once.
- **Haptics**: one `.soft` tick on save. Nowhere else.

---

## 4. Technical architecture

### Stack decisions (opinionated)

| Concern | Choice | Why |
|---|---|---|
| UI | SwiftUI, iOS 26.4+ | Given. `NavigationSplitView`, `LazyVStack`, `AttributedString`. |
| Persistence | **GRDB + SQLite (FTS5)**, not SwiftData | We need `UNIQUE` constraints for dedup, FTS5 for search, and free-form migrations. SwiftData-with-CloudKit forbids `@Attribute(.unique)`, requires every property optional-or-defaulted, bans `.deny` delete rules, and effectively restricts you to lightweight migration once enabled. Those constraints are hostile to a dedup-heavy schema. |
| Feed parsing | **FeedKit** (MIT) | Mature, RSS 0.9–2.0 / Atom / JSON Feed, actively maintained. |
| HTML parsing | **SwiftSoup** (MIT, jsoup port) | Headless, deterministic, testable, no WKWebView in the pipeline. |
| Article extraction | Own scorer over SwiftSoup, seeded by JSON-LD/OpenGraph | See §4.3. |
| Sync (later) | **CKSyncEngine** with a hand-rolled record mapping | Not `NSPersistentCloudKitContainer`. We sync ~5 small tables, not the whole store. |
| Embeddings/NLP | `NaturalLanguage` (`NLContextualEmbedding`, 512-dim on iOS; `NLTagger`) | On-device, free, no network. |
| Optional LLM | `FoundationModels` (on-device, ~3B, 4096-token context) | Gated on Apple Intelligence hardware; see §4.7 for why the context limit constrains what we ask it. |

### 4.1 Feeds and discovery

**Add-a-source pipeline**, given any pasted URL:

1. If it parses as a feed → done.
2. Fetch the page; collect `<link rel="alternate" type="application/rss+xml|atom+xml|feed+json">`
   from `<head>` (RSS autodiscovery). Note: `alternate` must be lowercase per spec; be liberal.
3. Probe conventional paths: `/feed`, `/rss`, `/rss.xml`, `/atom.xml`, `/index.xml`, `/feed.json`,
   `/feeds/posts/default` (Blogger), `/?feed=rss2` (WordPress). Cap at 8 HEAD/GET probes, ≤2 rps.
4. Look for a WordPress/Ghost/Substack/Blogger fingerprint to prefer the right path.
5. Present *all* candidates with title, item count, whether items carry full text
   (`content:encoded` / JSON Feed `content_html` present and >1200 chars), and a live-rendered
   preview of the newest 3 items.
6. Store `Source { id, title, homeURL, feedURL, iconURL, folder, priority, unreadPolicy,
   fullTextPolicy, etag, lastModified, lastFetch, healthStats }`.

**Polling**: adaptive per source. Start at 30 min; adjust toward the source's observed inter-item
interval, clamped `[15 min, 6 h]`. Always send `If-None-Match` / `If-Modified-Since`; treat 304 as
free. Honor `Retry-After` and `Cache-Control: max-age`. Exponential backoff with jitter on 4xx/5xx;
after 5 consecutive failures drop to 12h and surface the source as unhealthy. Identify ourselves in
the User-Agent with a contact-free app string — no browser spoofing.

`rel="hub"` (WebSub) is **not worth it** here: it needs a public callback URL, which means a server,
which the product doesn't have. Note it and move on.

**Background refresh**: `BGAppRefreshTask` for feed metadata, `BGProcessingTask` (requires-network,
optionally requires-charging) for extraction + image prefetch. Be realistic: iOS grants these
opportunistically and a personal-build app with low usage may get them rarely. Design the foreground
path to be fast enough that background refresh is a bonus, not the mechanism.

### 4.2 Data model (core tables)

```
Source(id, feedURL UNIQUE, homeURL, title, iconURL, folderID, priority, policies…, health…)
Item(id, sourceID, guid, canonicalURL, urlHash UNIQUE, title, dek, authors, published,
     updated, summaryHTML, feedContentHTML, imageURL, storyID?, contentHash, simhash)
Document(itemID PK, schemaVersion, extractorVersion, blocksJSON, wordCount, quality,
         extractedAt, state)          -- state: full | partial | paywalled | feedOnly | failed
Story(id, canonicalTitle, firstSeen, lastSeen, memberCount)
Rating(sourceID, scale, leaning, confidence, provider, ratedAt, url)
ArticleSignal(itemID, leaning?, confidence, signalsJSON, modelVersion)
ReadState(itemID, isRead, isSaved, progressBlockIdx, progressOffset, savedAt)
Highlight(id, itemID, blockID, range, color, note, createdAt)
Asset(id, itemID, remoteURL, localPath, bytes, width, height, role)
ItemFTS(title, dek, bodyText)         -- FTS5 external-content, contentless-delete
```

`Document.blocksJSON` is the crown jewel. `extractorVersion` lets us re-extract everything when the
scorer improves; `schemaVersion` lets the block model evolve without a store migration.

### 4.3 Extraction — the four-lane cascade

Run in order, stop at first acceptable result. Each lane produces a candidate `ArticleDoc` plus a
quality score; the cascade is not "try until no error" but "try until quality threshold".

**Lane 0 — Feed full text.** If `content:encoded` / Atom `content` / JSON Feed `content_html`
contains ≥1200 chars of prose and ≥3 block-level elements, sanitize and use it. Free, fast, no
extra HTTP request, and it's the publisher's own choice to syndicate. ~35–45% of a typical personal
feed list lands here (Substack, Ghost, most indie blogs, many nonprofits).

**Lane 1 — Structured metadata.** Fetch the canonical URL once. Parse JSON-LD (`NewsArticle`,
`Article`, `Report`), OpenGraph, Twitter cards, `<meta name="author">`, `<time datetime>`. This
lane doesn't produce the body; it produces *high-confidence headline, dek, byline, dates, hero
image, section, and the paywall signal* (§5.2), which then constrain and validate lane 2.

**Lane 2 — Semantic body extraction.** Own scorer over the SwiftSoup DOM:

- Strip by tag (`script style noscript nav header footer aside form iframe svg[role=presentation]`).
- Strip by heuristic class/id regex (`ad|advert|promo|sponsor|newsletter|subscribe|paywall|social|
  share|related|recirc|recommend|comment|trending|outbrain|taboola|masthead|breadcrumb`), with an
  allowlist guard so `sidebar-note` or `advertorial-disclosure`-style *content* isn't eaten.
- Prefer explicit containers: `<article>`, `[itemprop=articleBody]`, `[property=articleBody]`,
  `main article`.
- Otherwise score candidate containers by text density (text chars ÷ tag count), paragraph count,
  comma count, link density (reject >0.30), and depth penalty. Readability-family scoring — the
  algorithm is well-understood; porting the scoring rather than embedding JS keeps the pipeline
  headless and unit-testable.
- **Map to blocks, don't sanitize HTML.** This is the key architectural move: the output is a typed
  `ArticleDoc`, not filtered HTML. Anything we can't map to a known block type is *dropped*, which
  makes the renderer's job total and eliminates a whole class of layout surprises.

**Lane 3 — Rendered DOM (opt-in, per source).** Some sites build the body client-side. An offscreen
`WKWebView` with a non-persistent `WKWebsiteDataStore`, JS enabled, then extract `document.body`
HTML after `didFinish` + a settle delay, and re-run lane 2 on the result. This lane is expensive
(~0.5–2s, real memory) and *does* execute publisher JS, so: opt-in per source, never in background
tasks, never more than one at a time, content-blocker ruleset applied to kill known ad/tracker
hosts. A pre-ported Readability-in-WKWebView package (e.g. `Ryu0118/swift-readability`, MIT, which
wraps `@mozilla/readability`) is a reasonable implementation of this lane specifically.

**Quality score** (0–1), used for the threshold and shown in source health:
`0.35·(wordCount ≥ 250) + 0.20·(paragraphs ≥ 4) + 0.15·(linkDensity < 0.2) +
0.15·(title matches metadata title, fuzzy) + 0.15·(≥1 figure or explicit no-image signal)`.
Accept at ≥0.62; below that, fall through. Below 0.35 at the end of the cascade → `failed` (§5.1).

**Per-source overrides.** A small local rules file (bundled + user-editable JSON) keyed by host:
`{ bodySelector, removeSelectors[], preferLane, dateFormat, authorSelector, embedPolicy }`. Twenty
lines of override beats a thousand lines of heuristic for a source you read daily. Expect to write
these for ~15% of sources.

**Normalization pass** (runs on every lane's output):
- Absolutize URLs; strip tracking params (`utm_*`, `fbclid`, `gclid`, `mc_cid`, `ref`, `_hsenc`,
  `igshid`, `s=`/`t=` on x.com).
- Pick best image from `srcset`/`data-src`/`data-srcset`; prefer ≥1200px wide; record intrinsic
  dimensions so the renderer can reserve space.
- Collapse `<div>`-soup paragraphs into real paragraphs; drop empty and whitespace-only blocks.
- Detect and drop trailing boilerplate: repeated-across-articles-from-same-source tail blocks
  (n-gram compare against last 20 docs from that source) catches "Sign up for our newsletter",
  "Follow us on", and staff bios automatically. **This trick is worth more than 200 regexes.**
- Detect and drop leading "This article originally appeared in…" duplicated deks.
- Byline cleanup: strip "By ", split on `,`/`and`, drop "Staff"/"Wire".
- Timezone-normalize dates to UTC with the original offset retained for display.

### 4.4 Deduplication and story clustering

Two distinct problems, two mechanisms:

**(a) Exact/near-duplicate items** — the same article arriving twice (feed re-publish, GUID change,
syndication to a wire client, `?amp=1` variant).
- Canonicalize URL: lowercase host, strip `www.`, strip fragment, strip tracking params, resolve
  `rel=canonical` from lane 1, strip trailing slash. `urlHash = SHA256(canonicalURL)` with a UNIQUE
  index — cheapest and highest-yield check.
- `contentHash = SHA256(normalized body text)` catches re-published items at new URLs.
- **SimHash (64-bit) over 4-word shingles** of the body; Hamming distance ≤3 → duplicate. Cheap
  (bit-count), indexable by banding, and robust to a changed lede or added update paragraph.
- Resolution: keep the item from the higher-priority source, retain the other's URL as an
  `alsoAt` link so nothing is hidden.

**(b) Same-story clustering across publishers** — Reuters, AP, NYT, WSJ, Fox all covering one event.
- Candidate generation: items within a 36h window sharing ≥2 rare entities (`NLTagger` named-entity
  extraction over headline + first 3 paragraphs, IDF-weighted against a rolling corpus).
- Scoring: cosine similarity of `NLContextualEmbedding` sentence vectors over `headline + dek +
  lede`, combined with entity Jaccard and time proximity.
  `score = 0.55·cosine + 0.30·jaccard + 0.15·timeDecay`.
- Cluster with a simple online single-link algorithm at threshold ~0.72, with a **max cluster size
  of 12** and a guard: never merge two items from the same source into the same cluster (a source
  covering a story twice means follow-up, not duplicate).
- Clusters are advisory. Every cluster is expandable and dissolvable by the user; `Ungroup` is one
  tap and is remembered. **False merges are much worse than false splits** — a merged cluster hides
  an article, a split cluster merely fails to help. Tune the threshold conservatively.

### 4.5 Offline cache

- **Prefetch policy** per source: `Metadata only` / `Extract on refresh` / `Extract + images`.
  Default: extract on refresh for ≤20 items/day sources; metadata-only for wires.
- Images downsampled at write time to `2 × maxDisplayWidth` (so ~1400px on iPad), re-encoded to
  HEIC where the source is JPEG/PNG, originals discarded. Typically 60–80% size reduction.
- **Budget**: user-set, default 1.5 GB. LRU eviction weighted so `saved` never evicts, `read` evicts
  first, `unread & recent` evicts last. Evict assets before documents; documents before items.
- Documents are ~15–60 KB of JSON each — even 20,000 articles is well under 1 GB of text. The budget
  is really an image budget.
- Cellular: extraction on cellular defaults on (text is tiny), image prefetch defaults off.
- Everything under `Application Support`, excluded from iCloud backup except the reading-state
  tables. `NSFileProtectionCompleteUntilFirstUserAuthentication`.

### 4.6 Bias / political leaning

Two independent layers, never conflated in the UI.

**Layer 1 — Source rating (the reliable one).** A local table of publisher-level ratings, keyed by
domain, on the required scale (`left / center-left / center / center-right / right / N/A`), each row
carrying `provider`, `ratedAt`, and a link to the provider's methodology.

Provider notes (verify current terms before shipping anything, even privately):
- **AllSides** publishes Media Bias Ratings under **CC BY-NC 4.0** — usable for non-commercial
  purposes with attribution, which is exactly what a private personal app is; CSV/JSON on request,
  and a paid license/API for commercial use. Their scale maps 1:1 onto the required five buckets.
  This is the best default.
- **Ad Fontes Media** rates bias on −42…+42 and reliability 0–64 via multi-analyst panels, and offers
  free non-commercial licenses for personal/education/non-profit/civic use. Their two-axis data is
  more informative; bucket the bias axis for display and keep reliability as a separate, optional
  signal. Bucketing thresholds are a judgment call — document them in-app.
- **MBFC** offers a data API with an explicit license agreement; the RapidAPI tier is explicitly not
  for redistribution/commercial products. Broader domain coverage, weaker methodology transparency.

**Design decision: ship AllSides as the primary provider, allow a second provider as an overlay, and
when two providers disagree by more than one bucket, show the disagreement rather than averaging
it.** Averaging manufactures false precision. A `Left / Center-Left (providers disagree)` chip is
more honest and more interesting.

Ratings are a **bundled, versioned snapshot** refreshed manually (a JSON file the app can re-import),
not a live API call per article. No network dependency in the reading path, no per-request licensing
question, and the "as of" date is unambiguous.

**Layer 2 — Article-level signal (the unreliable one).** Be disciplined here. The default state for
any article is **`Not assessed`**, and that is what ships in MVP.

When enabled (later scope), compute *signals*, not a verdict:
- Loaded/valence lexicon hits per 1000 words (`slammed`, `regime`, `far-left`, `radical`,
  `pro-life`/`anti-abortion` framing pairs, etc.), with the matched terms viewable.
- Source-of-quotes balance: named entities in attributed quotes, mapped to a small
  politician/organization lean table.
- Opinion-vs-news classification from JSON-LD `articleSection`, URL path (`/opinion/`, `/commentary/`,
  `/editorial/`), and a lightweight text classifier. **This is the single most valuable article-level
  signal and it's nearly free** — an opinion column from a center source is not a center article.
- Headline/body sentiment divergence.

Only if all of the above are computed does an optional `FoundationModels` pass run, prompted to
choose a bucket *given the extracted signals* and forced through guided generation into
`{ leaning, confidence, evidenceSpans[] }`. Constraint that shapes the design: the on-device model
has a **4096-token context covering both input and output** (~3,000 words), with `contextSize` and
`tokenCount(for:)` available since iOS 26.4 — so a 2,500-word article does not fit alongside a
prompt. Feed it headline + dek + first ~600 words + the computed signal summary, not the article.
Model availability also requires Apple Intelligence hardware (iPhone 15 Pro and later, Apple-silicon
iPad/Mac), so this path must be entirely optional.

**Confidence rubric** (shown as text, not stars):
| Confidence | Meaning |
|---|---|
| `Rated` | Source-level, from a named provider, with date. |
| `Indicative` | Article signals agree with the source rating, or ≥3 strong signals agree. |
| `Weak` | Signals present but mixed, or model-only. Shown greyed with an explicit caveat. |
| `Not assessed` | Default. No rating for the domain, or signals below threshold. |

Every chip is tappable and opens a provenance sheet: who rated it, when, by what method, with a link.
No chip is ever shown without a path to its provenance. **A bias label with no provenance is worse
than no label.**

### 4.7 Direct-source links (non-negotiable plumbing)

- `Item.canonicalURL` is captured before any normalization and never mutated.
- Reader shows the publisher link **above the fold** and again in the footer, both as prominent
  bordered buttons, both labeled with the publisher's actual name.
- Tapping opens `SFSafariViewController` by default (keeps cookies/session so a subscriber stays
  logged in — this is how a paying subscriber actually reads gated content) with a setting for
  default browser.
- Share sheet, Handoff, Spotlight indexing, and copy-link **always** emit `canonicalURL`. Our
  extracted text is never the shared payload.
- Long-press on any publisher name anywhere in the app → open at publisher.

---

## 5. Failure, paywall, and embed handling

### 5.1 Extraction failure states

| State | Trigger | UI |
|---|---|---|
| `full` | quality ≥ 0.62 | Normal reader. |
| `partial` | quality 0.35–0.62, or body ends mid-sentence, or blocks dropped | Reader renders what we have, with a footer notice: *"Broadsheet couldn't read all of this article."* + prominent publisher link + `Try again` (forces lane 3). |
| `feedOnly` | Fetch blocked (403/robots), or quality < 0.35 but feed summary exists | Card view: headline, dek, image, summary, big publisher button. Explicitly not styled as a failure — many feeds are summary-only by design. |
| `paywalled` | §5.2 | Dedicated state, below. |
| `failed` | Nothing usable | Honest card: *"This one has to be read at the publisher."* + button + `Report extraction issue` which dumps a local diagnostic (URL, host, lane results, scores) to a file for later rule-writing. |

**Retry policy**: transient network → 3 tries with backoff. Structural failure → do *not* retry
automatically; queue for retry only when `extractorVersion` changes. A background job that
re-extracts `failed` and `partial` documents after an extractor upgrade is a two-hour build and
makes the app get better over time without any user action.

**Robots.txt**: fetch and cache per host (24h TTL), and honor `Disallow` for our extraction fetch.
Practically it costs a handful of sources; ethically and legally it is the difference between "a
reading client" and "a scraper", and it's the right default for a tool that fetches on a timer. The
user-facing effect is the source falls back to `feedOnly` with a clear reason shown in source health.

### 5.2 Paywalls

**Detection** (any one is sufficient):
1. JSON-LD `isAccessibleForFree: false` — Google's documented markup for paywalled content, widely
   deployed because publishers need it to stay indexed without being flagged for cloaking. The
   `hasPart` entries carry a `cssSelector` pointing at the gated DOM element, which tells us exactly
   which part is restricted. **This is a publisher explicitly declaring the boundary — treat it as
   authoritative.**
2. Body ends abruptly (<300 words) while metadata suggests a full article, plus a gate-ish element
   present (`[class*=paywall]`, `[id*=regwall]`, `[data-testid*=subscri]`).
3. Known-metered host + observed truncation.
4. HTTP 402/403 on the article fetch.

**Behavior**: render exactly the free portion (whatever the publisher served without a session, or
whatever `hasPart.isAccessibleForFree: true` marks as free), in house style, with a clear divider and:

> **The rest of this article is for *Publisher* subscribers.**
> [ ↗ Continue at The Publisher ]  [ Subscribe at The Publisher ]

Both buttons open `SFSafariViewController` so an existing subscription session applies. If the user
is a subscriber and the site sets cookies, the article reads fine at the publisher — that's the
correct outcome and it's a feature, not a workaround.

**Explicitly not implemented, ever**: user-agent spoofing as a crawler, referrer spoofing, cookie
jar rotation, JS-disable tricks, archive-site mirrors, AMP/`?outputType=amp` URL substitution, or
paste-from-clipboard-bypass. A per-source `I have a subscription` toggle that reuses `SFSafariView`
cookies is the *only* sanctioned route to full text on gated sites, and even then extraction should
prefer to hand off rather than harvest an authenticated page.

### 5.3 Embeds

**Never render a third-party iframe inline.** That's the tracker vector and the layout-chaos vector
in one. Instead, an allowlist of embed types, each with a native card:

| Provider | Card content | Tap action |
|---|---|---|
| X / Twitter | Author, handle, text, media thumb, timestamp (from `blockquote.twitter-tweet` fallback text — the markup ships with the text inline) | Sheet with isolated WKWebView, or Safari |
| Bluesky / Mastodon | Same, via public post JSON / oEmbed | Sheet |
| YouTube / Vimeo | Poster frame + duration + title | `AVPlayer` where a direct stream is available; otherwise Safari. Do not embed the YouTube iframe. |
| Instagram / TikTok | Poster + author | Safari (their oEmbed now requires a token; don't bother) |
| Apple Podcasts / Spotify | Show art, title | Deep link to the native app |
| Datawrapper / Flourish / Infogram | Static PNG fallback if the provider exposes one (Datawrapper does: `/full/{id}/plain.png`-style static exports) | Sheet with WKWebView |
| Newsletter/gift-link/generic iframe | Link card with favicon + title | Safari |
| Unknown | Link card | Safari |

Rules: the fallback for *any* unrecognized embed is a link card — never a blank space, never a
broken box. Embed cards are visually distinct (tinted container, hairline border, provider glyph) so
you always know you're looking at something that lives elsewhere. The isolated WKWebView uses
`WKWebsiteDataStore.nonPersistent()` and a content-blocker ruleset, and is torn down on dismiss.

**Twitter/X specifically**: the standard embed markup includes the tweet text and author inside the
`<blockquote>` before the script upgrades it. Parse that. It works offline, it renders in house
style, it's fast, and it survives the API being hostile.

---

## 6. Legal and privacy risk (not legal advice)

The risk profile of a **private, personal, unpublished, non-commercial** reader is very different
from a product. It's not zero, and the mitigations below are cheap.

| Risk | Reality for this app | Mitigation |
|---|---|---|
| **Copyright / reproduction** | Reformatting content you have the right to read, on your own device, for your own reading, with no redistribution, is the same shape as browser Reader Mode, Instapaper, and NetNewsWire — long-tolerated. Risk rises sharply the moment content is shared, published, or the app is distributed. | Don't distribute. No export of full extracted text (export = URL + your highlights + your notes). No sharing of rendered articles. Attribution on every screen. |
| **Paywall circumvention** (this is the sharp one — DMCA §1201 and CFAA theories attach to *access controls*, not to formatting) | Only a risk if you build bypass features. | Hard rule from §5.2. Detect and stop. Never spoof a crawler. This single discipline removes most of the legal exposure. |
| **ToS violations** | Many publisher ToS prohibit automated access and reformatting. Breach-of-contract exposure for a single private user is negligible in practice but real in principle. | Honor `robots.txt`. Rate-limit (≤1 concurrent request/host, ≥2s spacing). Honest User-Agent. Don't crawl beyond feed-linked article URLs — no site-wide spidering, no archive backfill. |
| **Ad/tracker removal** | Not itself unlawful for personal use in the US/EU; publishers dislike it. | It's inherent to the product. Don't advertise it as a feature to third parties (there are no third parties). |
| **Bias labels / defamation** | Attaching a political label to a named publisher is the *reputational* risk that would matter if this were ever public. For a private app, it's near-zero. | Attribute every rating to its provider with date and method link. Never present a computed label as fact. Keep `Not assessed` the default. |
| **Ratings-data licensing** | AllSides ratings are CC BY-NC 4.0 — non-commercial with attribution, which a private personal app satisfies; Ad Fontes offers free non-commercial licenses; MBFC's API has explicit non-redistribution terms on the cheap tier. | Attribute in-app on every chip's provenance sheet and in an About screen. Don't redistribute the ratings file. Re-read the current terms before importing; these change. |
| **Privacy** | Ironically the strongest part: no account, no server, no analytics, no third-party SDKs. Publisher servers still see your IP on fetch — that's ordinary reading. | Fetch article HTML only for items you'll plausibly read (prefetch policy). Non-persistent data store for the embed WebView. No cross-site cookie jar for extraction fetches. Optional: route fetches through iCloud Private Relay if enabled — don't claim it works without testing. |
| **iCloud sync (later)** | CloudKit private database is end-to-end-ish and Apple-managed; syncing full extracted article bodies means storing publisher text in your iCloud account. | Sync **reading state, sources, highlights, and notes only** — never extracted bodies. Smaller, faster, cheaper, and sidesteps the question entirely. |
| **Distribution** | Personal build. A free Apple ID gives 7-day provisioning (you'd re-sign weekly); the $99/yr Developer Program gives 1-year profiles and TestFlight. | Budget the $99 if this survives past a prototype. It's the only recurring cost in the whole project. |

Bottom line: the two disciplines that matter are **never bypass access controls** and **never
redistribute**. Everything else is hygiene.

---

## 7. Scope

### MVP (target: something you actually read daily)

1. Add sources by URL with autodiscovery + preview; folders; per-source priority.
2. Feed fetch (RSS/Atom/JSON Feed) with conditional GET and adaptive polling; foreground refresh.
3. Extraction lanes 0–2 + normalization + per-source override file.
4. `ArticleDoc` block model + the full renderer for: paragraph, heading, list, blockquote,
   pullquote, figure, divider, code, link-card embed. (Table and gallery can wait.)
5. House typography, 4 themes, Dynamic Type, reader settings (4 knobs).
6. Publisher links top and bottom; `SFSafariViewController` handoff; correct share payload.
7. Failure/paywall states (§5.1, §5.2) including `isAccessibleForFree` detection.
8. Exact + near-duplicate dedup (URL canonical, contentHash, SimHash).
9. **Source-level** bias chips from a bundled AllSides-derived snapshot, with provenance sheets.
   Article-level = `Not assessed`, visibly.
10. Offline: extract-on-refresh, image prefetch, LRU budget.
11. Read/unread/saved, position restore, FTS5 search.
12. Source health screen (this is the maintenance tool; skipping it makes v1 unmaintainable).
13. iPad three-column layout + keyboard shortcuts.

### v1.1 — the earned features

- Story clustering + spectrum strip + compare-headlines (needs a corpus of real data to tune).
- Highlights and notes with stable block anchoring.
- Lane 3 (WKWebView extraction) as an opt-in per source.
- Native embed cards for X/Bluesky/YouTube.
- Second ratings provider with disagreement display.
- Re-extraction job on extractor version bump.

### v2 and later

- iCloud sync via `CKSyncEngine` (reading state + sources + highlights only).
- Article-level bias signals (lexicon + quote balance + opinion classifier), still labeled as signals.
- Optional `FoundationModels` pass for article leaning and on-demand summaries.
- Table/gallery blocks, footnote popovers, full-screen image viewer with gallery paging.
- macOS (Catalyst or native SwiftUI) — the extraction pipeline is already platform-neutral.
- Widgets, Shortcuts/App Intents, Spotlight indexing.
- OPML import/export.

### Deliberately never

Push notifications. Engagement ranking. Social. Sync of article bodies. Paywall bypass. Publishing.

---

## 8. Open decisions — with defaults already chosen

These are recorded as decided; revisit only with evidence.

| # | Question | **Default taken** | Revisit if |
|---|---|---|---|
| 1 | SwiftData vs GRDB | **GRDB/SQLite.** Unique constraints, FTS5, free migrations. | You decide iCloud sync of everything matters more than dedup ergonomics. |
| 2 | Extract eagerly or on-tap | **Eagerly on refresh** for normal-volume sources; on-tap for wires. | Battery or data complaints. |
| 3 | Honor robots.txt | **Yes.** | Never — this one's a principle. |
| 4 | Article-level bias in MVP | **No.** `Not assessed`. | Only after source-level ships and you've read 500 articles with it. |
| 5 | Ratings provider | **AllSides** (CC BY-NC), Ad Fontes as overlay. | Coverage gaps on your actual source list — measure first. |
| 6 | Bundled snapshot vs live ratings API | **Bundled, versioned, manual refresh.** | Coverage churn becomes annoying. |
| 7 | Two-provider disagreement | **Show both.** Never average. | Never. |
| 8 | Reader font | **New York (serif)**, SF Pro for chrome. | User testing of one (you). |
| 9 | Clustering in MVP | **No.** Ship the river first. | After ~2 weeks of corpus exists to tune against. |
| 10 | Cluster threshold bias | **Favor false splits over false merges.** | Never. |
| 11 | Lane 3 (WKWebView) | **Opt-in per source, foreground only.** | If >30% of your sources need it, reconsider the whole extraction approach. |
| 12 | Embeds | **Allowlist + native cards; unknown → link card.** | New provider you actually encounter. |
| 13 | Unread counts | **Off by default per source.** | You miss them. |
| 14 | Cache budget | **1.5 GB, LRU, saved never evicted.** | Device storage pressure. |
| 15 | Sync scope (when it lands) | **State only, never bodies.** | Never — legal and size both argue for it. |
| 16 | Cloud LLM fallback | **No, by default.** | See §9 cost math. |

---

## 9. Skeptical self-review — where this fails or gets expensive

**1. Extraction rot is the project killer, and it's a *maintenance* cost, not a build cost.**
Publishers redesign. A per-source override that worked in March silently produces half an article in
July. There is no test suite that protects you because the ground truth lives on someone else's
server. Mitigation is structural, not heroic: the quality score must be computed and *stored* on
every extraction, the source health screen must surface a rolling success rate, and a drop below 70%
on a source must be visible without you going looking. Budget ~1–2 hours/month forever. If you won't
spend that, cut the source list to 15 and pick sources with full-text feeds — which changes the
product into "a very nice RSS reader for indie publishers", a real and defensible outcome.

**2. The bias feature is the part most likely to be quietly wrong.**
Source-level ratings are defensible — they're someone else's methodology, dated and attributed.
Article-level is where this goes bad. A 3B-parameter on-device model with a 4096-token window,
seeing the first 600 words of an article, will produce confident-sounding buckets that are noise.
The failure isn't that it's wrong once; it's that a wrong label rendered in a clean, authoritative
UI *feels* right, and over months it shapes what you believe about publishers. The mitigation is the
`Not assessed` default and the provenance sheet, but the honest framing is: **the spectrum strip
across a story cluster is the feature with real epistemic value; per-article leaning may never be
good enough to ship.** Be willing to kill it.

**3. Clustering false-merges hide articles, and you won't notice.**
A false split is visible and mildly annoying. A false merge means an article you wanted disappeared
under a card you collapsed. Since there's no analytics and one user, silent recall loss is
undetectable. Mitigation: clusters never *remove* items from the "From your sources" river — they
only add a grouped view above it. Redundancy over elegance.

**4. Paywall discipline costs real content, and the temptation compounds.**
Roughly half of serious national reporting is gated. The app will repeatedly show you a headline you
want and a wall. Every one of those moments is an argument for "just this one workaround." The rule
holds only if it's structural — no bypass code paths exist to enable. Practical answer: pay for 2–3
subscriptions and use the `SFSafariViewController` session handoff. That's the honest cost of this
product, ~$200–400/yr, and it's larger than the $99 developer program.

**5. Embeds are an unbounded tarpit.**
Every provider has a different markup, a different oEmbed policy, and a habit of changing both.
The allowlist will always be incomplete. This is fine *only* because the fallback is a link card,
which is why the fallback must be built first and be genuinely good-looking. If you build the X card
before the generic link card, embeds will eat a month.

**6. Cost, honestly.**
On-device is free: `NaturalLanguage`, `FoundationModels`, SwiftSoup, FeedKit, GRDB all cost nothing
at runtime. The only meaningful cloud temptation is an LLM for extraction repair or bias. Order of
magnitude, at ~200 articles/day, ~2k input tokens each (≈12M tokens/month): with Claude Haiku 4.5 at
$1/M input, that's ~$12/month before the 50% Batch API discount and up to 90% prompt-cache savings —
so realistically single-digit dollars/month. Not ruinous, but it (a) reintroduces a network
dependency in the reading path, (b) sends your reading list to a third party, which contradicts
principle 6, and (c) is a recurring cost on a project whose entire premise is "no subscription."
**Default: no cloud LLM.** If extraction repair genuinely needs one, run it on-demand for the single
article you're staring at, not as a pipeline stage.

**7. Background refresh will disappoint you.**
`BGAppRefreshTask` scheduling is opportunistic and correlates with usage frequency; a personal build
you open twice a day may get very few grants. If you architect around "content is always
pre-extracted," mornings will feel broken. Architect around a fast foreground refresh — parallel
feed fetches, extraction streaming into the list as it completes, list usable immediately.

**8. Typography is where "as polished as Apple News" is actually won or lost, and it's the part
that looks easiest.** Apple News's polish is mostly restraint: consistent vertical rhythm, correct
optical margins, images that don't jump, and captions that don't fight the body. The failure mode
is a technically correct renderer that feels cheap because paragraph spacing is 8pt off and images
reflow on load. Reserve aspect-ratio space for every image before it loads; define the vertical
rhythm as a single spacing scale and never deviate; test at AX3 and at 320pt width before believing
anything.

**9. One-user products drift into infinite polish.** There's no ship date and no external forcing
function. The concrete counter: the MVP list in §7 is the definition of done for v1, source-health
screen included, and clustering/bias-per-article are explicitly *not* in it. Read on it for two
weeks before writing another line of feature code.

---

## Sources

- [Meet the Foundation Models framework — WWDC25](https://developer.apple.com/videos/play/wwdc2025/286/)
- [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [Making the most of Apple Foundation Models: Context Window](https://zats.io/blog/making-the-most-of-apple-foundation-models-context-window/)
- [NLContextualEmbedding — Apple Developer Documentation](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding)
- [What's new in SwiftUI — WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/)
- [SwiftData Limitations — What to Know Before Adopting SwiftData](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/)
- [Designing Models for CloudKit Sync: Core Data & SwiftData Rules](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/)
- [FeedKit — Swift Package Index](https://swiftpackageindex.com/nmdias/FeedKit)
- [Ryu0118/swift-readability (wraps @mozilla/readability)](https://github.com/Ryu0118/swift-readability)
- [RSS Autodiscovery — RSS Advisory Board](https://www.rssboard.org/rss-autodiscovery)
- [Subscription and paywalled content markup — Google Search Central](https://developers.google.com/search/docs/appearance/structured-data/paywalled-content)
- [AllSides Media Bias Rating Methods](https://www.allsides.com/about/media-bias-rating-methods)
- [AllSides Bias Ratings License & API](https://www.allsides.com/tools-services/bias-ratings-license-api)
- [Ad Fontes Media — Methodology](https://adfontesmedia.com/methodology/)
- [Ad Fontes Media — Publisher Services](https://adfontesmedia.com/publisher-services/)
- [MBFC's Data API](https://mediabiasfactcheck.com/mbfcs-data-api/)
- [Claude Platform pricing](https://platform.claude.com/docs/en/about-claude/pricing)
