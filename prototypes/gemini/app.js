/* ==========================================================================
   Broadsheet Visual Prototype - Gemini Lane
   Interactive Behaviors
   ========================================================================== */

(function () {
  "use strict";

  // Safe local storage utility
  var store = {
    get: function (key, fallback) {
      try {
        return window.localStorage.getItem(key) || fallback;
      } catch (e) {
        return fallback;
      }
    },
    set: function (key, val) {
      try {
        window.localStorage.setItem(key, val);
      } catch (e) {
        // Fallback for private browsing mode
      }
    }
  };

  var root = document.documentElement;
  var mediaDark = window.matchMedia("(prefers-color-scheme: dark)");

  /* --------------------------------------------------------------------------
     Theme Management (Paper / Night / OLED / Auto)
     -------------------------------------------------------------------------- */
  function resolveTheme(pref) {
    if (pref === "auto") {
      return mediaDark.matches ? "night" : "paper";
    }
    return pref;
  }

  function applyTheme(pref) {
    var theme = resolveTheme(pref);
    root.setAttribute("data-theme", theme);
    root.setAttribute("data-theme-pref", pref);
    syncPressedButtons("[data-theme-set]", "data-theme-set", pref);
    updateWarmthLabel();
  }

  function syncPressedButtons(selector, attribute, activeVal) {
    var buttons = document.querySelectorAll(selector);
    for (var i = 0; i < buttons.length; i++) {
      var matches = buttons[i].getAttribute(attribute) === activeVal;
      buttons[i].setAttribute("aria-pressed", String(matches));
    }
  }

  var themePref = store.get("bs.theme", "auto");
  applyTheme(themePref);

  if (mediaDark.addEventListener) {
    mediaDark.addEventListener("change", function () {
      if (store.get("bs.theme", "auto") === "auto") {
        applyTheme("auto");
      }
    });
  }

  /* --------------------------------------------------------------------------
     Prototype Scaffolding: Screen Width
     -------------------------------------------------------------------------- */
  function applyWidth(w) {
    var device = document.querySelector(".device");
    if (device) {
      device.style.setProperty("--device-w", w + "px");
    }
    syncPressedButtons("[data-width-set]", "data-width-set", w);
  }
  var widthPref = store.get("bs.width", "390");
  applyWidth(widthPref);

  /* --------------------------------------------------------------------------
     Article Reading Preferences: Font Size & Font Family
     -------------------------------------------------------------------------- */
  var deviceContainer = document.querySelector(".device");

  function applyFontSize(size) {
    if (deviceContainer) {
      deviceContainer.setAttribute("data-size", size);
    }
    syncPressedButtons("[data-size-set]", "data-size-set", size);
  }

  function applyFontBody(family) {
    if (deviceContainer) {
      deviceContainer.setAttribute("data-body", family);
    }
    syncPressedButtons("[data-body-set]", "data-body-set", family);
  }

  // Set default reading preferences if we are on the article page
  applyFontSize(store.get("bs.size", "m"));
  applyFontBody(store.get("bs.body", "serif"));

  /* --------------------------------------------------------------------------
     Signature Feature: Library-Lamp Warmth Slider
     -------------------------------------------------------------------------- */
  function getWarmthText(val, theme) {
    var isDark = (theme === "night" || theme === "oled");
    var labelMap = {
      light: ["Alabaster", "Parchment", "Sepia", "Dimmed"],
      dark: ["Slate Night", "Charcoal Ink", "Warm Night", "Library Night"]
    };
    var idx = parseInt(val, 10);
    if (isNaN(idx) || idx < 0 || idx > 3) idx = 0;
    return isDark ? labelMap.dark[idx] : labelMap.light[idx];
  }

  function applyWarmth(val) {
    root.setAttribute("data-warmth", val);
    store.set("bs.warmth", val);
    
    // Sync slider controls if visible on screen
    var sliders = document.querySelectorAll(".warmth-slider");
    for (var i = 0; i < sliders.length; i++) {
      sliders[i].value = val;
    }
    
    updateWarmthLabel();
  }

  function updateWarmthLabel() {
    var currentWarmthVal = root.getAttribute("data-warmth") || "0";
    var currentTheme = root.getAttribute("data-theme") || "paper";
    
    var textLabel = getWarmthText(currentWarmthVal, currentTheme);
    var labelElements = document.querySelectorAll(".warmth-label");
    for (var i = 0; i < labelElements.length; i++) {
      labelElements[i].textContent = textLabel;
    }
  }

  var initialWarmth = store.get("bs.warmth", "0");
  applyWarmth(initialWarmth);

  /* --------------------------------------------------------------------------
     Delegated Click Event Handlers
     -------------------------------------------------------------------------- */
  document.addEventListener("click", function (event) {
    var targetBtn = event.target.closest ? event.target.closest("[data-action], [data-theme-set], [data-width-set], [data-size-set], [data-body-set], [data-open], [data-close]") : null;
    if (!targetBtn) return;

    // Theme select controls
    if (targetBtn.hasAttribute("data-theme-set")) {
      var pref = targetBtn.getAttribute("data-theme-set");
      store.set("bs.theme", pref);
      applyTheme(pref);
      return;
    }

    // Width select controls
    if (targetBtn.hasAttribute("data-width-set")) {
      var w = targetBtn.getAttribute("data-width-set");
      store.set("bs.width", w);
      applyWidth(w);
      return;
    }

    // Font size controls
    if (targetBtn.hasAttribute("data-size-set")) {
      var sz = targetBtn.getAttribute("data-size-set");
      store.set("bs.size", sz);
      applyFontSize(sz);
      return;
    }

    // Font body controls
    if (targetBtn.hasAttribute("data-body-set")) {
      var b = targetBtn.getAttribute("data-body-set");
      store.set("bs.body", b);
      applyFontBody(b);
      return;
    }

    // Modal/Sheet triggers
    if (targetBtn.hasAttribute("data-open")) {
      var dialogId = targetBtn.getAttribute("data-open");
      var targetDialog = document.getElementById(dialogId);
      if (targetDialog && targetDialog.showModal) {
        event.preventDefault();
        event.stopPropagation();
        targetDialog.showModal();
      }
      return;
    }

    // Modal close triggers
    if (targetBtn.hasAttribute("data-close")) {
      var activeDialog = targetBtn.closest("dialog");
      if (activeDialog) {
        activeDialog.close();
      }
      return;
    }

    // Custom actions
    var action = targetBtn.getAttribute("data-action");

    if (action === "save") {
      var isSaved = targetBtn.getAttribute("aria-pressed") !== "true";
      targetBtn.setAttribute("aria-pressed", String(isSaved));
      triggerToast(isSaved ? "Saved to Library." : "Removed from Library.");
      return;
    }

    if (action === "toggle-settings") {
      var settingsPanel = document.querySelector(".settings-panel");
      if (settingsPanel) {
        var isVisible = settingsPanel.getAttribute("data-visible") === "true";
        settingsPanel.setAttribute("data-visible", String(!isVisible));
        targetBtn.setAttribute("aria-pressed", String(!isVisible));
      }
      return;
    }

    if (action === "toast") {
      event.preventDefault();
      var message = targetBtn.getAttribute("data-toast") || "Feature not part of this visual prototype.";
      triggerToast(message);
    }
  });

  // Tapping the outer backdrop of a native dialog dismisses it
  document.addEventListener("click", function (event) {
    if (event.target.tagName === "DIALOG" && event.target.open) {
      var rect = event.target.getBoundingClientRect();
      var isClickedOutside = event.clientX < rect.left || event.clientX > rect.right ||
                             event.clientY < rect.top || event.clientY > rect.bottom;
      if (isClickedOutside) {
        event.target.close();
      }
    }
  });

  // Listener for warmth slider input
  document.addEventListener("input", function (event) {
    if (event.target.classList.contains("warmth-slider")) {
      applyWarmth(event.target.value);
    }
  });

  /* --------------------------------------------------------------------------
     Interactive Toast Notifications
     -------------------------------------------------------------------------- */
  var toastHideTimeout;
  function triggerToast(text) {
    var toastElement = document.querySelector(".toast");
    if (!toastElement) return;
    
    toastElement.textContent = text;
    toastElement.setAttribute("data-show", "true");
    
    window.clearTimeout(toastHideTimeout);
    toastHideTimeout = window.setTimeout(function () {
      toastElement.setAttribute("data-show", "false");
    }, 2200);
  }

  /* --------------------------------------------------------------------------
     Reading Progress Indicator (Scroll listener)
     -------------------------------------------------------------------------- */
  var scroller = document.querySelector(".scroll");
  var progressBar = document.querySelector(".progress-bar");

  if (scroller && progressBar) {
    var isTicking = false;
    scroller.addEventListener("scroll", function () {
      if (!isTicking) {
        isTicking = true;
        window.requestAnimationFrame(function () {
          var maxScroll = scroller.scrollHeight - scroller.clientHeight;
          var scrollPercent = maxScroll > 0 ? Math.min(1, scroller.scrollTop / maxScroll) : 0;
          progressBar.style.width = (scrollPercent * 100).toFixed(2) + "%";
          isTicking = false;
        });
      }
    }, { passive: true });
  }

})();
