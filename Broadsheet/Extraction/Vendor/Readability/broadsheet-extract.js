/*
 * Broadsheet semantic extraction bridge.
 *
 * Copyright (c) 2026 Broadsheet. Licensed under the Apache License, Version 2.0,
 * the same licence as the vendored Mozilla Readability it calls into.
 *
 * This file does two jobs and nothing else:
 *
 *   1. `readability` mode runs Mozilla's Readability over the loaded document.
 *   2. `fragment` mode walks a publisher-supplied feed content fragment.
 *
 * Both then convert the resulting DOM into Broadsheet's typed semantic blocks.
 * Raw publisher HTML never leaves this file: only typed blocks cross back into
 * Swift, so nothing untyped can reach the native reading surface.
 *
 * It never invents content. Every string it emits is text that was present in
 * the DOM it was given.
 */

(function () {
  "use strict";

  var MAX_BLOCKS = 400;
  var MAX_RUNS_PER_BLOCK = 200;

  // Chrome that survives extraction often carries these hooks. Matching is on
  // class and id only — never on the text — so ordinary reporting that happens
  // to mention "subscribe" is not discarded.
  var CHROME_PATTERN =
    /(^|[\s_-])(share|sharing|newsletter|promo|related|recirc|advert|ad-|ads-|subscribe|subscription|paywall|regwall|meter|nav|navigation|breadcrumb|footer|social|comment|disqus|tags|taboola|outbrain|more-on|read-more|sidebar)([\s_-]|$)/i;

  function textOf(node) {
    return (node.textContent || "").replace(/\s+/g, " ").trim();
  }

  function isChrome(element) {
    if (!element || element.nodeType !== 1) {
      return false;
    }
    var signature = (element.className || "") + " " + (element.id || "");
    if (typeof signature !== "string") {
      return false;
    }
    return CHROME_PATTERN.test(signature);
  }

  function absoluteURL(raw) {
    if (!raw) {
      return null;
    }
    try {
      var resolved = new URL(raw, document.baseURI);
      if (resolved.protocol !== "https:" && resolved.protocol !== "http:") {
        return null;
      }
      return resolved.href;
    } catch (error) {
      return null;
    }
  }

  function pushRun(runs, run) {
    if (!run || !run.text || runs.length >= MAX_RUNS_PER_BLOCK) {
      return;
    }
    var previous = runs[runs.length - 1];
    if (previous && previous.kind === "plain" && run.kind === "plain") {
      previous.text += run.text;
      return;
    }
    runs.push(run);
  }

  function collectRuns(node, runs, emphasis) {
    for (var i = 0; i < node.childNodes.length; i++) {
      var child = node.childNodes[i];

      if (child.nodeType === 3) {
        var text = (child.nodeValue || "").replace(/\s+/g, " ");
        if (text) {
          pushRun(runs, { kind: emphasis || "plain", text: text });
        }
        continue;
      }
      if (child.nodeType !== 1) {
        continue;
      }

      var tag = child.tagName.toLowerCase();
      if (tag === "script" || tag === "style" || tag === "noscript" || isChrome(child)) {
        continue;
      }
      if (tag === "br") {
        pushRun(runs, { kind: "plain", text: " " });
        continue;
      }
      if (tag === "a") {
        var href = absoluteURL(child.getAttribute("href"));
        var label = textOf(child);
        if (href && label) {
          pushRun(runs, { kind: "link", text: label, url: href });
        } else if (label) {
          pushRun(runs, { kind: emphasis || "plain", text: label });
        }
        continue;
      }
      if (tag === "em" || tag === "i" || tag === "cite") {
        collectRuns(child, runs, "emphasis");
        continue;
      }
      if (tag === "strong" || tag === "b") {
        collectRuns(child, runs, "strong");
        continue;
      }
      collectRuns(child, runs, emphasis);
    }
  }

  function runsFor(node) {
    var runs = [];
    collectRuns(node, runs, null);
    // Trim the outer edges without disturbing the runs in between.
    if (runs.length) {
      runs[0].text = runs[0].text.replace(/^\s+/, "");
      runs[runs.length - 1].text = runs[runs.length - 1].text.replace(/\s+$/, "");
    }
    return runs.filter(function (run) {
      return run.text.length > 0;
    });
  }

  function imageBlock(element) {
    var source = element.getAttribute("src") || element.getAttribute("data-src");
    if (!source && element.getAttribute("srcset")) {
      source = element.getAttribute("srcset").split(",")[0].trim().split(" ")[0];
    }
    var url = absoluteURL(source);
    if (!url) {
      return null;
    }
    var alt = (element.getAttribute("alt") || "").trim();
    var width = parseInt(element.getAttribute("width") || "0", 10);
    var height = parseInt(element.getAttribute("height") || "0", 10);
    // Tracking pixels and spacer images are not journalism.
    if (width > 0 && height > 0 && (width < 100 || height < 100)) {
      return null;
    }
    return {
      type: "image",
      url: url,
      alt: alt,
      caption: null,
      credit: null,
      aspectRatio: width > 0 && height > 0 ? width / height : null
    };
  }

  function figureBlock(element) {
    var image = element.querySelector("img");
    if (!image) {
      return null;
    }
    var block = imageBlock(image);
    if (!block) {
      return null;
    }
    var caption = element.querySelector("figcaption");
    if (caption) {
      var captionText = textOf(caption);
      if (captionText) {
        block.caption = captionText;
      }
    }
    return block;
  }

  function listBlock(element, ordered) {
    var items = [];
    var children = element.children;
    for (var i = 0; i < children.length; i++) {
      if (children[i].tagName.toLowerCase() !== "li") {
        continue;
      }
      var runs = runsFor(children[i]);
      if (runs.length) {
        items.push(runs);
      }
    }
    if (!items.length) {
      return null;
    }
    return { type: "list", ordered: !!ordered, items: items };
  }

  function quoteBlock(element) {
    var attribution = null;
    var footer = element.querySelector("footer, cite");
    if (footer) {
      attribution = textOf(footer) || null;
      footer.parentNode.removeChild(footer);
    }
    var text = textOf(element);
    if (!text) {
      return null;
    }
    return { type: "pullQuote", text: text, attribution: attribution };
  }

  function walk(root, blocks) {
    for (var i = 0; i < root.children.length; i++) {
      if (blocks.length >= MAX_BLOCKS) {
        return;
      }
      var element = root.children[i];
      var tag = element.tagName.toLowerCase();

      if (tag === "script" || tag === "style" || tag === "noscript" || tag === "form" || tag === "iframe") {
        continue;
      }
      if (isChrome(element)) {
        continue;
      }

      if (tag === "p") {
        var runs = runsFor(element);
        if (runs.length) {
          blocks.push({ type: "paragraph", runs: runs });
        }
        continue;
      }
      if (/^h[1-6]$/.test(tag)) {
        var heading = textOf(element);
        if (heading) {
          blocks.push({ type: "heading", text: heading });
        }
        continue;
      }
      if (tag === "blockquote") {
        var quote = quoteBlock(element);
        if (quote) {
          blocks.push(quote);
        }
        continue;
      }
      if (tag === "ul" || tag === "ol") {
        var list = listBlock(element, tag === "ol");
        if (list) {
          blocks.push(list);
        }
        continue;
      }
      if (tag === "figure") {
        var figure = figureBlock(element);
        if (figure) {
          blocks.push(figure);
        }
        continue;
      }
      if (tag === "img") {
        var image = imageBlock(element);
        if (image) {
          blocks.push(image);
        }
        continue;
      }
      if (tag === "hr") {
        blocks.push({ type: "divider" });
        continue;
      }
      if (tag === "pre" || tag === "code") {
        var code = textOf(element);
        if (code) {
          blocks.push({ type: "paragraph", runs: [{ kind: "plain", text: code }] });
        }
        continue;
      }
      if (tag === "table" || tag === "video" || tag === "audio" || tag === "svg" || tag === "canvas") {
        // Unsupported embeds are dropped rather than flattened into prose that
        // would read as reporting the publisher did not write.
        continue;
      }

      if (element.children.length) {
        walk(element, blocks);
      } else {
        var loose = textOf(element);
        if (loose.length > 40) {
          blocks.push({ type: "paragraph", runs: [{ kind: "plain", text: loose }] });
        }
      }
    }
  }

  function plainLength(blocks) {
    var total = 0;
    for (var i = 0; i < blocks.length; i++) {
      var block = blocks[i];
      if (block.type === "paragraph") {
        for (var j = 0; j < block.runs.length; j++) {
          total += block.runs[j].text.length;
        }
      } else if (block.type === "pullQuote") {
        total += block.text.length;
      }
    }
    return total;
  }

  function metaContent(names) {
    for (var i = 0; i < names.length; i++) {
      var element =
        document.querySelector('meta[property="' + names[i] + '"]') ||
        document.querySelector('meta[name="' + names[i] + '"]');
      if (element) {
        var value = (element.getAttribute("content") || "").trim();
        if (value) {
          return value;
        }
      }
    }
    return null;
  }

  window.__broadsheetExtract = function (mode) {
    try {
      var container;
      var title = null;
      var byline = null;
      var excerpt = null;
      var siteName = null;
      var publishedTime = null;

      if (mode === "readability") {
        if (typeof Readability !== "function") {
          return JSON.stringify({ ok: false, error: "Readability is not loaded." });
        }
        var parsed = new Readability(document.cloneNode(true), {
          charThreshold: 250,
          keepClasses: false
        }).parse();

        if (!parsed || !parsed.content) {
          return JSON.stringify({ ok: false, error: "Readability found no article content." });
        }

        title = parsed.title || null;
        byline = parsed.byline || null;
        excerpt = parsed.excerpt || null;
        siteName = parsed.siteName || null;
        publishedTime = parsed.publishedTime || metaContent(["article:published_time", "datePublished"]);

        container = document.createElement("div");
        container.innerHTML = parsed.content;
      } else {
        container = document.body;
        title = metaContent(["og:title"]);
      }

      var blocks = [];
      walk(container, blocks);

      // A heading identical to the headline is publisher chrome once the native
      // reader has already typeset the headline above it.
      if (title && blocks.length && blocks[0].type === "heading") {
        var first = blocks[0].text.replace(/\s+/g, " ").trim().toLowerCase();
        if (first === title.replace(/\s+/g, " ").trim().toLowerCase()) {
          blocks.shift();
        }
      }

      var lead = null;
      for (var i = 0; i < blocks.length; i++) {
        if (blocks[i].type === "image") {
          lead = blocks[i];
          blocks.splice(i, 1);
          break;
        }
      }

      return JSON.stringify({
        ok: true,
        mode: mode,
        title: title,
        byline: byline,
        excerpt: excerpt,
        siteName: siteName,
        publishedTime: publishedTime,
        leadImage: lead,
        blocks: blocks,
        textLength: plainLength(blocks)
      });
    } catch (error) {
      return JSON.stringify({ ok: false, error: String(error && error.message ? error.message : error) });
    }
  };
})();
