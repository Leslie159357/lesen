// Reader bridge. Everything is injected from Swift — the WebView never fetches
// files, so EPUB internals cannot hit CORS or file:// restrictions.
(function () {
  'use strict';

  var content = document.getElementById('content');
  var empty = document.getElementById('empty');
  var titleEl = document.getElementById('bookTitle');
  var progressEl = document.getElementById('progress');
  var sections = [];
  var scale = 1;
  var mode = 'scroll';
  var lastProgress = 0;

  function post(payload) {
    try {
      window.webkit.messageHandlers.ob.postMessage(payload);
    } catch (e) { /* running outside the app */ }
  }

  function normalize(href) {
    return String(href || '').replace(/^\.\//, '').replace(/#.*$/, '');
  }

  // Split text nodes into sentence spans, then word spans inside each sentence.
  function wrapTextNodes(root) {
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
        var p = node.parentElement;
        if (!p) return NodeFilter.FILTER_REJECT;
        if (/^(SCRIPT|STYLE|CODE|PRE)$/.test(p.tagName)) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);

    nodes.forEach(function (node) {
      var text = node.nodeValue.replace(/\s+/g, ' ');
      var frag = document.createDocumentFragment();
      var sentences = text.split(/(?<=[.!?…])\s+/);
      sentences.forEach(function (sentence) {
        if (!sentence.trim()) {
          frag.appendChild(document.createTextNode(sentence));
          return;
        }
        var s = document.createElement('span');
        s.className = 's';
        var re = /[A-Za-zÄÖÜäöüßẞ'’\-]+/g;
        var last = 0;
        var m;
        while ((m = re.exec(sentence))) {
          if (m.index > last) s.appendChild(document.createTextNode(sentence.slice(last, m.index)));
          var w = document.createElement('span');
          w.className = 'w';
          w.textContent = m[0];
          s.appendChild(w);
          last = m.index + m[0].length;
        }
        if (last < sentence.length) s.appendChild(document.createTextNode(sentence.slice(last)));
        frag.appendChild(s);
        frag.appendChild(document.createTextNode(' '));
      });
      if (node.parentNode) node.parentNode.replaceChild(frag, node);
    });
  }

  function clearActive() {
    var prev = content.querySelector('.s.active');
    if (prev) prev.classList.remove('active');
  }

  function updateProgress() {
    if (!sections.length) return;
    var now = Date.now();
    if (now - lastProgress < 400) return;
    lastProgress = now;

    if (mode === 'page') {
      var step = Math.max(1, content.clientWidth);
      var pageIndex = Math.round(content.scrollLeft / step);
      var pages = Math.max(1, Math.ceil(content.scrollWidth / step));
      var percent = Math.min(1, (pageIndex + 1) / pages);
      progressEl.textContent = (pageIndex + 1) + ' / ' + pages;
      post({ type: 'progress', chapter: 0, percent: percent });
      return;
    }

    var idx = 0;
    var scrolled = window.scrollY;
    sections.forEach(function (sec, i) {
      if (sec.offsetTop <= scrolled + 140) idx = i;
    });
    var sec = sections[idx];
    var ratio = 0;
    if (sec) {
      var height = sec.offsetHeight || 1;
      ratio = Math.min(1, Math.max(0, (scrolled - sec.offsetTop + 140) / height));
    }
    progressEl.textContent = (idx + 1) + ' / ' + sections.length;
    post({ type: 'progress', chapter: idx, percent: ratio });
  }

  window.OB = {
    open: function (payload) {
      titleEl.textContent = payload.title || '';
      content.innerHTML = '';
      sections = [];
      (payload.chapters || []).forEach(function (ch, i) {
        var sec = document.createElement('section');
        sec.className = 'chapter';
        sec.dataset.href = normalize(ch.href);
        sec.dataset.index = String(i);
        sec.innerHTML = ch.html || '';
        content.appendChild(sec);
        sections.push(sec);
        wrapTextNodes(sec);
      });
      if (empty) empty.style.display = sections.length ? 'none' : 'block';
      updateProgress();
      post({ type: 'ready' });
    },

    gotoChapter: function (index) {
      var sec = sections[index];
      if (sec) sec.scrollIntoView({ block: 'start' });
    },

    highlight: function (chapterHref, textId) {
      var target = null;
      var href = normalize(chapterHref);
      if (textId) {
        for (var i = 0; i < sections.length; i++) {
          if (sections[i].dataset.href === href || sections[i].dataset.href.endsWith(href)) {
            try {
              target = sections[i].querySelector('#' + CSS.escape(textId));
            } catch (e) { target = null; }
            if (target) break;
          }
        }
      }
      if (!target) return;
      var sentence = target.closest('.s');
      if (!sentence) {
        var inner = target.querySelector('.s');
        sentence = inner || target;
      }
      clearActive();
      if (sentence.classList && sentence.classList.contains('s')) sentence.classList.add('active');
      sentence.scrollIntoView({ block: 'center', behavior: 'smooth' });
    },

    clearHighlight: clearActive,

    setMode: function (next) {
      mode = next === 'page' ? 'page' : 'scroll';
      document.body.classList.toggle('page-mode', mode === 'page');
      // entering page mode: start from the top-left of the flow
      content.scrollLeft = 0;
      window.scrollTo(0, 0);
      updateProgress();
    },

    page: function (direction) {
      if (mode !== 'page') {
        window.scrollBy({ top: direction * (window.innerHeight * 0.85), behavior: 'smooth' });
        return;
      }
      content.scrollBy({ left: direction * content.clientWidth, behavior: 'smooth' });
    },

    restore: function (position, percent) {
      if (mode === 'page') {
        var target = Math.max(0, percent * content.scrollWidth - content.clientWidth);
        content.scrollLeft = target;
        return;
      }
      var sec = sections[position];
      if (!sec) return;
      window.scrollTo(0, sec.offsetTop + Math.max(0, percent * sec.offsetHeight) - 100);
    },

    setFontScale: function (factor) {
      scale = Math.min(1.8, Math.max(0.7, scale * factor));
      document.documentElement.style.setProperty('--size', (19 * scale).toFixed(1) + 'px');
    }
  };

  content.addEventListener('click', function (event) {
    var wordEl = event.target.closest ? event.target.closest('.w') : null;
    if (!wordEl) return;
    var sentenceEl = wordEl.closest('.s');
    post({
      type: 'word',
      word: wordEl.textContent,
      sentence: sentenceEl ? sentenceEl.textContent.trim() : ''
    });
  });

  window.addEventListener('scroll', updateProgress, { passive: true });
  content.addEventListener('scroll', updateProgress, { passive: true });
  post({ type: 'log', msg: 'reader.js loaded' });
})();
