// ============================================================
// Dynamics 365 Text Resizer — Content Script
// Supports plain textareas (by aria-label) and Quill rich-text editors
// ============================================================

const BUILTIN_LABELS = [
  'Description',
  'Notes',
  'Resolution'
];

const MARKER_CLASS  = 'd365-resizer-enhanced';
const QUILL_MARKER  = 'd365-quill-enhanced';
const FORMAT_BTN_CLASS = 'd365-format-btn';

let settings = {
  enabled: true,
  autoFit: true,
  minHeight: 180,
  showHighlight: true,
  customFields: []
};

// ── Selectors ──────────────────────────────────────────────

// Escape a string for use inside a CSS attribute selector "..."
function escapeAttrValue(s) {
  return String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

// Build CSS selector for built-in + custom textarea labels.
// Each clause includes :not(.MARKER_CLASS) so already-enhanced fields are
// skipped at the DOM-walk level rather than filtered in JS afterwards.
function buildNewTextareaSelector() {
  const all = BUILTIN_LABELS.concat(settings.customFields);
  return all
    .map(label => `textarea[aria-label="${escapeAttrValue(label)}"]:not(.${MARKER_CLASS})`)
    .join(',');
}

// ── Markdown stripper ──────────────────────────────────────

function stripMarkdown(text) {
  return text
    // Headers: # Heading → Heading
    .replace(/^#{1,6}\s+/gm, '')
    // Bold+italic: ***text*** or ___text___
    .replace(/\*{3}(.+?)\*{3}/g, '$1')
    .replace(/_{3}(.+?)_{3}/g, '$1')
    // Bold: **text** or __text__
    .replace(/\*{2}(.+?)\*{2}/g, '$1')
    .replace(/_{2}(.+?)_{2}/g, '$1')
    // Italic: *text* or _text_
    .replace(/\*(.+?)\*/g, '$1')
    .replace(/_(.+?)_/g, '$1')
    // Inline code: `code`
    .replace(/`([^`]+)`/g, '$1')
    // Links: [text](url) → text (url)
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '$1 ($2)')
    // Blockquotes: > text → text
    .replace(/^>\s*/gm, '')
    // Horizontal rules
    .replace(/^-{3,}\s*$/gm, '')
    .replace(/^\*{3,}\s*$/gm, '')
    .replace(/^_{3,}\s*$/gm, '')
    // Bullet lists: - item or * item → • item
    .replace(/^[\-\*]\s+/gm, '• ');
}

// ── Format button ──────────────────────────────────────────

function injectFormatButton(el, isQuill) {
  const container = el.parentElement;
  if (!container) return;

  if (container.querySelector('.' + FORMAT_BTN_CLASS)) return;

  const btn = document.createElement('button');
  btn.textContent = 'Format';
  btn.className = FORMAT_BTN_CLASS;
  btn.title = 'Strip markdown formatting';
  btn.style.cssText = [
    'position:absolute',
    'top:4px',
    'right:4px',
    'z-index:9999',
    'font-size:11px',
    'padding:2px 6px',
    'background:#0078d4',
    'color:white',
    'border:none',
    'border-radius:3px',
    'cursor:pointer',
    'opacity:0.8',
    'line-height:1.4'
  ].join(';');

  btn.addEventListener('mouseenter', () => { btn.style.opacity = '1'; });
  btn.addEventListener('mouseleave', () => { btn.style.opacity = '0.8'; });

  btn.addEventListener('click', (e) => {
    e.preventDefault();
    e.stopPropagation();

    if (isQuill) {
      const editor = el.querySelector('.ql-editor');
      if (!editor) return;
      const raw = editor.innerText || editor.textContent || '';
      const formatted = stripMarkdown(raw);
      editor.innerText = formatted;
      editor.dispatchEvent(new Event('input', { bubbles: true }));
      editor.dispatchEvent(new Event('change', { bubbles: true }));
    } else {
      const raw = el.value;
      const formatted = stripMarkdown(raw);
      const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
        window.HTMLTextAreaElement.prototype, 'value'
      ).set;
      nativeInputValueSetter.call(el, formatted);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    }
  });

  const pos = getComputedStyle(container).position;
  if (pos === 'static') container.style.position = 'relative';

  container.appendChild(btn);
}

// ── Styles ─────────────────────────────────────────────────

function injectStyles() {
  if (document.getElementById('d365-resizer-styles')) return;
  const style = document.createElement('style');
  style.id = 'd365-resizer-styles';
  style.textContent = `
    /* ── Plain textarea enhancements ── */
    .${MARKER_CLASS} {
      resize: vertical !important;
      overflow: auto !important;
      max-height: none !important;
      transition: outline 0.2s ease;
    }
    .${MARKER_CLASS}.d365-highlight:hover {
      outline: 2px solid rgba(0, 120, 212, 0.45) !important;
      outline-offset: 1px;
    }

    /* ── Quill rich-text editor enhancements ── */
    .${QUILL_MARKER} {
      resize: vertical !important;
      overflow: hidden !important;
      max-height: none !important;
      transition: outline 0.2s ease;
    }
    .${QUILL_MARKER} .ql-container {
      overflow: visible !important;
      max-height: none !important;
      height: auto !important;
      min-height: 0 !important;
      flex: 1 1 auto !important;
    }
    .${QUILL_MARKER} .ql-editor {
      overflow: auto !important;
      max-height: none !important;
      min-height: 0 !important;
    }
    .${QUILL_MARKER}.d365-highlight:hover {
      outline: 2px solid rgba(0, 120, 212, 0.45) !important;
      outline-offset: 1px;
    }
  `;
  document.head.appendChild(style);
}

function removeInjectedStyles() {
  const el = document.getElementById('d365-resizer-styles');
  if (el) el.remove();
}

// ── Auto-fit: textareas ────────────────────────────────────

// Grow a textarea to fit its content. Two-phase write avoids stale
// scrollHeight readings: we briefly set height:auto so the browser
// reports the natural content height, then commit max(content, minHeight).
//
// We cache the last fitted value on the element and bail out early when
// nothing has changed — Dynamics fires DOM mutations many times per
// second, and refitting unconditionally was clobbering text selections
// (e.g. Ctrl+A) every ~300 ms.
//
// As defence-in-depth, when a fit must actually run on the currently
// focused textarea we preserve and restore selectionStart/End around
// the height swap.
function fitTextarea(ta, force) {
  if (!ta.isConnected) return;
  if (!force && ta._d365LastValue === ta.value) return;
  ta._d365LastValue = ta.value;

  const focused = (ta.ownerDocument.activeElement === ta);
  const selStart = focused ? ta.selectionStart : null;
  const selEnd   = focused ? ta.selectionEnd   : null;
  const selDir   = focused ? ta.selectionDirection : null;

  ta.style.height = 'auto';
  const needed = ta.scrollHeight;
  ta.style.height = Math.max(needed, settings.minHeight) + 'px';

  if (focused && selStart !== null && selEnd !== null) {
    try { ta.setSelectionRange(selStart, selEnd, selDir || 'none'); } catch (_) {}
  }
}

// Re-fit every enhanced textarea whose value has actually changed since
// the last fit. Batched: 2 reflows total regardless of how many fields
// need fitting; zero work when nothing changed.
function fitAllTextareas() {
  const tas = Array.from(document.querySelectorAll('.' + MARKER_CLASS))
    .filter(ta => ta._d365LastValue !== ta.value);
  if (tas.length === 0) return;
  tas.forEach(ta => { ta._d365LastValue = ta.value; ta.style.height = 'auto'; });
  const heights = tas.map(ta => ta.scrollHeight);
  tas.forEach((ta, i) => {
    ta.style.height = Math.max(heights[i], settings.minHeight) + 'px';
  });
}

// ── Auto-fit: Quill ────────────────────────────────────────

// Quill structure: .quill > .ql-toolbar + .ql-container > .ql-editor
// Same change-detection guard as textareas: skip when innerHTML is
// unchanged so the global apply pass doesn't trample contenteditable
// selections.
function fitQuill(q, force) {
  if (!q.isConnected) return;
  const editor = q.querySelector('.ql-editor');
  if (!editor) return;
  if (!force && q._d365LastHtml === editor.innerHTML) return;
  q._d365LastHtml = editor.innerHTML;
  // Collapse to auto so q.scrollHeight reflects true content height, not the
  // flex-allocated layout height (which caused cumulative growth per keystroke).
  q.style.height = 'auto';
  q.style.height = Math.max(q.scrollHeight, settings.minHeight) + 'px';
}

// Batched version: collapse all → read all → write all (mirrors fitAllTextareas).
function fitAllQuills() {
  const qs = Array.from(document.querySelectorAll('.' + QUILL_MARKER)).filter(q => {
    const editor = q.querySelector('.ql-editor');
    return editor && q._d365LastHtml !== editor.innerHTML;
  });
  if (qs.length === 0) return;
  qs.forEach(q => {
    q._d365LastHtml = q.querySelector('.ql-editor').innerHTML;
    q.style.height = 'auto';
  });
  const heights = qs.map(q => q.scrollHeight);
  qs.forEach((q, i) => {
    q.style.height = Math.max(heights[i], settings.minHeight) + 'px';
  });
}

// ── Apply: plain textareas ─────────────────────────────────

function applyTextareaStyles() {
  const selector = buildNewTextareaSelector();
  document.querySelectorAll(selector).forEach(ta => {
    ta.classList.add(MARKER_CLASS);
    if (settings.showHighlight) ta.classList.add('d365-highlight');
    ta.style.minHeight = settings.minHeight + 'px';

    // One handler per element, attached only once. It reads current
    // settings at fire time so toggling autoFit off doesn't require
    // detaching it.
    if (!ta._d365FitHandler) {
      ta._d365FitHandler = () => {
        if (settings.enabled && settings.autoFit) fitTextarea(ta, true);
      };
      ta.addEventListener('input', ta._d365FitHandler);
    }

    if (settings.autoFit) fitTextarea(ta, true);

    ensureVisibilityObserver();
    visibilityObserver.observe(ta);

    injectFormatButton(ta, false);
  });
}

// ── Apply: Quill rich-text editors ─────────────────────────

function applyQuillStyles() {
  const minH = settings.minHeight;
  const quills = document.querySelectorAll('.quill:not(.' + QUILL_MARKER + ')');

  quills.forEach(q => {
    const editor = q.querySelector('.ql-editor[contenteditable="true"]');
    if (!editor) return;

    q.classList.add(QUILL_MARKER);
    if (settings.showHighlight) q.classList.add('d365-highlight');
    q.style.display = 'flex';
    q.style.flexDirection = 'column';
    q.style.minHeight = minH + 'px';

    if (!editor._d365FitHandler) {
      editor._d365FitHandler = () => {
        if (settings.enabled && settings.autoFit) fitQuill(q, true);
      };
      editor.addEventListener('input', editor._d365FitHandler);
    }

    if (settings.autoFit) {
      fitQuill(q, true);
    } else {
      const current = parseInt(q.style.height || getComputedStyle(q).height, 10);
      if (!current || current < minH) q.style.height = minH + 'px';
    }

    ensureVisibilityObserver();
    visibilityObserver.observe(q);

    injectFormatButton(q, true);
  });
}

// ── Combined apply + count ─────────────────────────────────

function countEnhanced() {
  return document.querySelectorAll('.' + MARKER_CLASS).length
       + document.querySelectorAll('.' + QUILL_MARKER).length;
}

function applyStyles() {
  if (!settings.enabled) return 0;
  applyTextareaStyles();
  applyQuillStyles();
  // Re-fit existing fields to catch programmatic content updates
  // (tab switches, async data loads) that don't fire `input`.
  if (settings.autoFit) {
    fitAllTextareas();
    fitAllQuills();
  }
  return countEnhanced();
}

// ── Remove all enhancements ────────────────────────────────

function removeStyles() {
  stopVisibilityObserver();
  document.querySelectorAll('.' + FORMAT_BTN_CLASS).forEach(btn => btn.remove());

  document.querySelectorAll('.' + MARKER_CLASS).forEach(el => {
    el.classList.remove(MARKER_CLASS, 'd365-highlight');
    el.style.resize = '';
    el.style.overflow = '';
    el.style.height = '';
    el.style.minHeight = '';
    el.style.maxHeight = '';
    if (el._d365FitHandler) {
      el.removeEventListener('input', el._d365FitHandler);
      delete el._d365FitHandler;
    }
    delete el._d365LastValue;
  });

  document.querySelectorAll('.' + QUILL_MARKER).forEach(el => {
    el.classList.remove(QUILL_MARKER, 'd365-highlight');
    el.style.resize = '';
    el.style.overflow = '';
    el.style.height = '';
    el.style.minHeight = '';
    el.style.maxHeight = '';
    el.style.display = '';
    el.style.flexDirection = '';
    delete el._d365LastHtml;

    const container = el.querySelector('.ql-container');
    if (container) {
      container.style.overflow = '';
      container.style.maxHeight = '';
      container.style.height = '';
      container.style.minHeight = '';
      container.style.flex = '';
    }
    const editor = el.querySelector('.ql-editor');
    if (editor) {
      editor.style.overflow = '';
      editor.style.maxHeight = '';
      editor.style.minHeight = '';
      if (editor._d365FitHandler) {
        editor.removeEventListener('input', editor._d365FitHandler);
        delete editor._d365FitHandler;
      }
    }
  });
}

// ── Badge ──────────────────────────────────────────────────

let lastBadgeCount = -1;

function updateBadge(count) {
  if (count === lastBadgeCount) return;
  lastBadgeCount = count;
  try {
    chrome.runtime.sendMessage({ type: 'updateBadge', count }).catch(() => {});
  } catch (_) {
    // Extension context gone (e.g. extension reloaded) — harmless
  }
}

// ── Debounce helper ────────────────────────────────────────

function debounce(fn, delay) {
  let timer;
  return function (...args) {
    clearTimeout(timer);
    timer = setTimeout(() => fn.apply(this, args), delay);
  };
}

const debouncedApply = debounce(() => {
  const count = applyStyles();
  updateBadge(count);
}, 300);

// ── MutationObserver ───────────────────────────────────────

let observer = null;
let visibilityObserver = null;

function startObserver() {
  if (observer) return;
  // Only react to mutations that add new nodes — pure text edits inside
  // existing fields fire mutations too and should be ignored.
  observer = new MutationObserver((mutations) => {
    if (mutations.some(m => m.addedNodes.length > 0)) {
      debouncedApply();
    }
  });
  observer.observe(document.body, { childList: true, subtree: true });
}

function stopObserver() {
  if (observer) {
    observer.disconnect();
    observer = null;
  }
  stopVisibilityObserver();
}

// Re-fit enhanced elements when they become visible (e.g. SPA tab switch).
// The MutationObserver only fires on addedNodes, so it misses the case where
// Dynamics reveals a hidden tab panel by toggling display/visibility on an
// ancestor — the element was already processed while hidden (scrollHeight=0)
// and the cached value prevents a re-fit. IntersectionObserver fires when the
// element actually enters the viewport, by which point layout is valid.
function ensureVisibilityObserver() {
  if (visibilityObserver) return;
  visibilityObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (!entry.isIntersecting || !settings.enabled || !settings.autoFit) return;
      const el = entry.target;
      if (el.classList.contains(MARKER_CLASS)) fitTextarea(el, true);
      else if (el.classList.contains(QUILL_MARKER)) fitQuill(el, true);
    });
  });
}

function stopVisibilityObserver() {
  if (visibilityObserver) {
    visibilityObserver.disconnect();
    visibilityObserver = null;
  }
}

// ── Init ───────────────────────────────────────────────────

function init() {
  chrome.storage.sync.get(
    { enabled: true, autoFit: true, minHeight: 180, showHighlight: true, customFields: [] },
    (stored) => {
      settings = { ...settings, ...stored };
      injectStyles();

      if (settings.enabled) {
        const count = applyStyles();
        updateBadge(count);
        startObserver();
      } else {
        updateBadge(0);
      }
    }
  );
}

// ── Message listener (popup → content) ─────────────────────

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.type === 'settingsUpdated') {
    settings = { ...settings, ...msg.settings };

    if (!settings.enabled) {
      stopObserver();
      removeStyles();
      updateBadge(0);
    } else {
      removeStyles();
      removeInjectedStyles();
      injectStyles();
      updateBadge(applyStyles());
      startObserver();
    }
    sendResponse({ ok: true });
  }

  if (msg.type === 'getCount') {
    sendResponse({ count: countEnhanced() });
  }
  return true;
});

init();
