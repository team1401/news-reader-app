import Foundation

/// Bundled HTML for extraction tests.
///
/// All of it is invented. `accessibleArticle` is shaped like an ordinary openly
/// published story; `paywalledArticle` and `regwallArticle` declare themselves
/// restricted exactly the way real publishers do, so the classifier is tested
/// against the real signals without ever fetching a real gated page.
enum HTMLFixtures {

    static let bodyParagraphs = [
        "The harbour authority published its dredging schedule on Tuesday, setting out which berths will be closed and for how long. The document is the first to cover a full calendar year rather than a single season.",
        "Operators had asked for a longer horizon after two consecutive years in which closures were announced with under a month's notice. The authority's engineering office said the change was possible because survey work finished early.",
        "Three berths on the eastern quay will close in sequence rather than together, which the authority said would keep at least two deepwater positions available at any point in the schedule.",
        "The schedule does not commit to a budget. A separate financing decision is expected later in the year, and the authority declined to say whether the sequencing would survive a smaller allocation.",
        "Local pilots welcomed the certainty but noted that the plan assumes the survey vessel remains available through the autumn, which is not guaranteed under its current charter."
    ]

    static var accessibleArticle: String {
        """
        <!DOCTYPE html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <title>Harbour authority publishes a full-year dredging schedule</title>
            <meta property="og:title" content="Harbour authority publishes a full-year dredging schedule">
            <meta property="article:published_time" content="2026-07-27T09:15:00Z">
          </head>
          <body>
            <header class="site-header"><nav class="main-navigation"><a href="/world">World</a><a href="/business">Business</a></nav></header>
            <div class="advert-slot">Advertisement</div>
            <article class="article-body">
              <h1>Harbour authority publishes a full-year dredging schedule</h1>
              <p class="byline">By A Fictional Reporter</p>
              <figure>
                <img src="https://cdn.example.org/harbour.jpg" alt="A dredger alongside a quay" width="1200" height="800">
                <figcaption>A dredger alongside the eastern quay.</figcaption>
              </figure>
              <p>\(bodyParagraphs[0])</p>
              <p>\(bodyParagraphs[1]) The <a href="/documents/schedule">full schedule</a> runs to forty pages.</p>
              <h2>What changes on the eastern quay</h2>
              <p>\(bodyParagraphs[2])</p>
              <blockquote>
                <p>Two deepwater positions is the floor, not the target.</p>
                <footer>The authority's engineering office</footer>
              </blockquote>
              <ul><li>Berth four closes first.</li><li>Berth five follows in the spring.</li></ul>
              <p>\(bodyParagraphs[3])</p>
              <p>\(bodyParagraphs[4])</p>
            </article>
            <aside class="newsletter-signup">Sign up for our newsletter</aside>
            <div class="related-stories"><a href="/other">Another story you should read</a></div>
            <footer class="site-footer">© A Fictional Publisher</footer>
          </body>
        </html>
        """
    }

    /// Declares `isAccessibleForFree: false` in JSON-LD — schema.org's own way of
    /// saying this article is not free.
    static let paywalledArticle = """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Subscribers only: the financing decision behind the dredging schedule</title>
        <meta property="article:content_tier" content="locked">
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"NewsArticle",
         "headline":"Subscribers only: the financing decision behind the dredging schedule",
         "isAccessibleForFree":false,
         "hasPart":{"@type":"WebPageElement","isAccessibleForFree":false,"cssSelector":".article-body"}}
        </script>
      </head>
      <body>
        <article>
          <h1>Subscribers only: the financing decision behind the dredging schedule</h1>
          <p>The authority's financing decision has been circulating in draft since May.</p>
          <div class="paywall-overlay" data-paywall="true">
            <p>Subscribe to continue reading.</p>
            <a href="/subscribe">See subscription options</a>
          </div>
        </article>
      </body>
    </html>
    """

    /// A registration wall: no structured declaration, only markup and a prompt,
    /// with almost no article behind it.
    static let regwallArticle = """
    <!DOCTYPE html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Register to keep reading</title></head>
      <body>
        <article>
          <h1>The financing decision behind the dredging schedule</h1>
          <p>A short teaser paragraph appears above the wall.</p>
          <div id="regwall-container">
            <p>Create a free account to continue reading this article.</p>
          </div>
        </article>
      </body>
    </html>
    """

    /// Open, but not an article: a video shell with no prose.
    static let thinPage = """
    <!DOCTYPE html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Watch: the harbour from above</title></head>
      <body>
        <article>
          <h1>Watch: the harbour from above</h1>
          <video src="https://cdn.example.org/clip.mp4"></video>
          <p>A two-minute clip.</p>
        </article>
      </body>
    </html>
    """

    /// A publisher-supplied full-content feed fragment.
    static var feedContentFragment: String {
        bodyParagraphs.map { "<p>\($0)</p>" }.joined()
            + "<h2>What changes on the eastern quay</h2>"
            + "<p>\(bodyParagraphs[2]) See the <a href=\"https://example.org/schedule\">schedule</a>.</p>"
            + "<ul><li>Berth four closes first.</li><li>Berth five follows.</li></ul>"
    }
}
