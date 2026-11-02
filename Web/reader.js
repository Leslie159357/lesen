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
    var idx = 0;
    var top = content.getBoundingClientRect().top;
    sections.forEach(function (sec, i) {
      var r = sec.getBoundingClientRect();
      if (r.top <= 120) idx = i + 1;
    });
    progressEl.textContent = (idx || 1) + ' / ' + sections.length;
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
  post({ type: 'log', msg: 'reader.js loaded' });
})();
