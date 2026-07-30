# Broadsheet: Gemini Visual Prototype (Revised)

A high-fidelity visual prototype representing the Today feed and native Article Reader for Broadsheet, a private native news reader. This prototype has been revised to incorporate Brian's binding design and product decisions.

Assigned Directory: `/Users/helix/.Hermes/workspace/news-reader-app/prototypes/gemini/`

---

## 1. Key Revisions & Design Decisions

This revision updates the Gemini visual prototype to align with the core product shape and Brian's feedback:

*   **Core Article-Level Bias Estimator:** Prominent article-level leaning labels (`Left`, `Center`, `Right`, or `N/A`) are now immediately visible on every feed item card (including the Lead Story) and at the top of the Article Reader. They are styled with a micro device icon to signify they are calculated on-device.
*   **Methodology & Provenance on Tap:** Tapping any article bias badge opens the new interactive **On-Device Bias Analysis** bottom sheet containing the estimate, confidence level (e.g. 94%), model version/ensemble details (`CoreML Classifier v1.4`), a short rationale, evidence text spans, and a mock manual correction control.
*   **Separation of Publisher Baselines:** Sourced publisher baselines (e.g. `Publisher: Left-Center` or `Pub: Left`) are kept strictly secondary and separate from article estimates. In the feed, they are displayed as subtle plain text next to the article estimate button. In the reader header and footer, they are rendered with secondary visual weight. Tapping the baseline opens the separate **Baseline Provenance** details.
*   **Factual Coverage Cluster Wording:** Removed subjective terms like "bias detected" from multi-source clusters. They are replaced by factual language: `Coverage by source baseline`.
*   **Folders Relocated to Library (Clipped Nav Fix):** Removed the horizontal category scroller from the Today feed (folders belong in Library/sidebar, not Today). Replaced the mock Library toast with a functional Library drawer. It houses the horizontal **Folders** category navigation. Spacing margins are fixed using a flexbox scroll padding technique (`scroll-padding-right` with a flex-shrink spacer), ensuring that the categories navigation never clips at the right edge.
*   **depth & Viewport rhythm:** Reduced vertical padding on the Today header and lead story margins. The lead story's dek was made more concise. This successfully pulls the top of the next section (the story cluster) into the initial viewport, signaling depth to the user.
*   **Canonical Button Placement:** Placed the primary `Read at [Publisher]` button prominently at the top of the article page, ensuring it stays above the hero image and falls within the first viewport.

---

## 2. Signature Detail: The Library-Lamp Warmth Slider

To accommodate Brian's changing reading conditions—from early morning light in the Airstream to late-night reading—we implemented the **Library-Lamp Warmth Slider** in the Article Reader settings panel:

*   **What it does:** Tapping the gear icon in the reading bar toggles a slide-down options drawer. Sliding the "Library Lamp" range slider dynamically modifies the background and text color variables of the app.
*   **The Tones:**
    *   *Light Mode:* Shifts from **Cool Alabaster** (a bright, crisp neutral) through **Warm Parchment** and **Editorial Sepia** to **Dimmed** (a soft, warm sand tone).
    *   *Dark Mode:* Transitions from **Slate Night** (slate charcoal) through **Charcoal Ink** and **Warm Night** to **Library Night** (amber-tinted black).
*   **Color Accuracy:** The background transitions remain matte and paper-like. The original photography/illustration is preserved without filters, maintaining accurate color rendering for editorial photos.

---

## 3. Deliberate Tradeoffs

*   **No Remote Fonts:** To guarantee instant load times and offline reliability, the prototype relies exclusively on system-safe serif/sans-serif stacks (`New York`, `ui-serif`, Georgia vs. `-apple-system`, `SF Pro Text`).
*   **Standard SVG Graphics:** Rather than linking external images, all visuals are modeled inline using vector graphics, ensuring responsive rendering and consistent performance under any network condition.
*   **Flat Matte Layouts:** Shadows are minimized and glassmorphism is excluded, emphasizing flat, tactile dividers and clean typography.

---

## 4. How to Preview

To preview the prototype, run a local web server within this directory:

```bash
# Option A: Python 3 standard library
python3 -m http.server 8000

# Option B: Node.js server
npx serve .
```

Open a browser and navigate to:
*   Today Feed: `http://localhost:8000/index.html`
*   Article Reader: `http://localhost:8000/article.html`

Use the prototype controls at the top of the browser window to toggle widths (390px / 430px), themes, reading fonts, and text sizes.
