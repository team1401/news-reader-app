# Vendored third-party code

## Mozilla Readability

- **Files:** `Readability.js`, `Readability-readerable.js`
- **Upstream:** https://github.com/mozilla/readability
- **Vendored from:** `main` @ `d7949dc47dd9ed9ee1d3b34ffdcf3bce28cde435`
- **Retrieved:** 2026-07-30
- **Copyright:** © 2010 Arc90 Inc, © Mozilla Foundation and contributors
- **Licence:** Apache License 2.0 — the full text is in `LICENSE.md` in this
  directory, and both the licence and the notice are bundled inside the app so
  they ship with the binary that uses the code.
- **Modifications:** none. The files are byte-for-byte as published upstream.

`broadsheet-extract.js` in this directory is Broadsheet's own bridge. It calls
into Readability and converts the result into Broadsheet's typed semantic blocks;
it is licensed under Apache 2.0 as well so the directory has a single licence.

Readability runs inside a `WKWebView` that has JavaScript enabled but every
subresource load blocked by a `WKContentRuleList`, a non-persistent data store,
and no cookies — see `ReadabilityExtractor.swift`. It is given HTML that
Broadsheet already fetched; it never navigates, logs in, or dismisses anything.
