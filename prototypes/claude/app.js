/* Broadsheet visual prototype: minimal vanilla behavior.
   Nothing here models real product logic. It exists so the prototype can be
   evaluated in light and dark, at two phone widths, and at several text sizes. */

(function () {
  "use strict";

  var store = {
    get: function (k, fallback) {
      try { return window.localStorage.getItem(k) || fallback; } catch (e) { return fallback; }
    },
    set: function (k, v) {
      try { window.localStorage.setItem(k, v); } catch (e) { /* private mode */ }
    }
  };

  var root = document.documentElement;
  var media = window.matchMedia("(prefers-color-scheme: dark)");

  /* ---- Theme: paper / night / oled / auto ------------------------------- */

  function resolveTheme(pref) {
    if (pref === "auto") return media.matches ? "night" : "paper";
    return pref;
  }

  function applyTheme(pref) {
    root.setAttribute("data-theme", resolveTheme(pref));
    root.setAttribute("data-theme-pref", pref);
    sync("[data-theme-set]", "data-theme-set", pref);
  }

  function sync(selector, attr, value) {
    var nodes = document.querySelectorAll(selector);
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].setAttribute("aria-pressed", String(nodes[i].getAttribute(attr) === value));
    }
  }

  var themePref = store.get("bs.theme", "auto");
  applyTheme(themePref);

  if (media.addEventListener) {
    media.addEventListener("change", function () {
      if (store.get("bs.theme", "auto") === "auto") applyTheme("auto");
    });
  }

  /* ---- Device width ----------------------------------------------------- */

  function applyWidth(w) {
    var device = document.querySelector(".device");
    if (device) device.style.setProperty("--device-w", w + "px");
    sync("[data-width-set]", "data-width-set", w);
  }
  applyWidth(store.get("bs.width", "390"));

  /* ---- Article reading settings ----------------------------------------- */

  var article = document.querySelector(".article");

  function applySize(size) {
    if (article) article.setAttribute("data-size", size);
    sync("[data-size-set]", "data-size-set", size);
  }

  function applyBody(face) {
    if (article) article.setAttribute("data-body", face);
    sync("[data-body-set]", "data-body-set", face);
  }

  if (article) {
    applySize(store.get("bs.size", "m"));
    applyBody(store.get("bs.body", "serif"));
  }

  /* ---- Delegated clicks -------------------------------------------------- */

  document.addEventListener("click", function (event) {
    var el = event.target.closest ? event.target.closest("[data-action], [data-theme-set], [data-width-set], [data-size-set], [data-body-set], [data-open], [data-close]") : null;
    if (!el) return;

    if (el.hasAttribute("data-theme-set")) {
      var pref = el.getAttribute("data-theme-set");
      store.set("bs.theme", pref);
      applyTheme(pref);
      return;
    }

    if (el.hasAttribute("data-width-set")) {
      var w = el.getAttribute("data-width-set");
      store.set("bs.width", w);
      applyWidth(w);
      return;
    }

    if (el.hasAttribute("data-size-set")) {
      var s = el.getAttribute("data-size-set");
      store.set("bs.size", s);
      applySize(s);
      return;
    }

    if (el.hasAttribute("data-body-set")) {
      var f = el.getAttribute("data-body-set");
      store.set("bs.body", f);
      applyBody(f);
      return;
    }

    if (el.hasAttribute("data-open")) {
      var dlg = document.getElementById(el.getAttribute("data-open"));
      if (dlg && dlg.showModal) { event.preventDefault(); dlg.showModal(); }
      return;
    }

    if (el.hasAttribute("data-close")) {
      var sheet = el.closest("dialog");
      if (sheet) sheet.close();
      return;
    }

    var action = el.getAttribute("data-action");

    if (action === "save") {
      var on = el.getAttribute("aria-pressed") !== "true";
      el.setAttribute("aria-pressed", String(on));
      toast(on ? "Saved to Library." : "Removed from Library.");
      return;
    }

    if (action === "toast") {
      event.preventDefault();
      toast(el.getAttribute("data-toast") || "Not part of this visual prototype.");
    }
  });

  /* Tapping the backdrop of a sheet dismisses it. */
  document.addEventListener("click", function (event) {
    var dlg = event.target;
    if (dlg.tagName === "DIALOG" && dlg.open) {
      var r = dlg.getBoundingClientRect();
      var outside = event.clientX < r.left || event.clientX > r.right ||
                    event.clientY < r.top || event.clientY > r.bottom;
      if (outside) dlg.close();
    }
  });

  /* ---- Toast ------------------------------------------------------------ */

  var toastTimer;
  function toast(message) {
    var node = document.querySelector(".toast");
    if (!node) return;
    node.textContent = message;
    node.setAttribute("data-show", "true");
    window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(function () {
      node.setAttribute("data-show", "false");
    }, 2200);
  }

  /* ---- Reading progress hairline ---------------------------------------- */

  var scroller = document.querySelector(".scroll");
  var progress = document.querySelector(".progress");

  if (scroller && progress) {
    var ticking = false;
    scroller.addEventListener("scroll", function () {
      if (ticking) return;
      ticking = true;
      window.requestAnimationFrame(function () {
        var max = scroller.scrollHeight - scroller.clientHeight;
        var pct = max > 0 ? Math.min(1, scroller.scrollTop / max) : 0;
        progress.style.width = (pct * 100).toFixed(2) + "%";
        ticking = false;
      });
    }, { passive: true });
  }
})();
