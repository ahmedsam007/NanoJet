(() => {
  const api = (typeof browser !== 'undefined' ? browser : chrome);

  const idmmacCandidates = new Set();
  const idmmacMeta = Object.create(null); // url -> { label, size, mime, hasAudio, hasVideo, width, height, itag }
  let hasAnyVideo = false;
  let globalBtn;

  // Inject page-context hooks to observe real fetch/XHR (content scripts run in isolated world)
  try {
    const hookCode = `(() => {\n      const post = (u) => { try { window.postMessage({ __idmmac_media: true, url: u }, '*'); } catch (e) {} };\n      try {\n        const of = window.fetch;\n        window.fetch = async function(...args) { try { const u = typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url) ? args[0].url : ''; if (u) post(u); } catch {} return await of.apply(this, args); };\n      } catch (e) {}\n      try {\n        const oo = XMLHttpRequest.prototype.open;\n        XMLHttpRequest.prototype.open = function(method, url, ...rest) { try { if (url) post(url); } catch {} return oo.apply(this, [method, url, ...rest]); };\n      } catch (e) {}\n    })();`;
    const s = document.createElement('script');
    s.textContent = hookCode;
    (document.documentElement || document.head || document.body).appendChild(s);
    s.remove();
  } catch {}

  window.addEventListener('message', (ev) => {
    try {
      const d = ev.data;
      if (d && d.__idmmac_media && typeof d.url === 'string') {
        tryCaptureURL(d.url);
      }
      if (d && d.__idmmac_yt_formats && Array.isArray(d.formats)) {
        d.formats.forEach((f) => {
          if (f && f.url) {
            idmmacCandidates.add(f.url);
            const meta = { label: f.label || inferLabel(f.url), size: f.size || extractSizeFromUrl(f.url), mime: f.mime || '', hasAudio: !!f.hasAudio, hasVideo: !!f.hasVideo, width: f.width || null, height: f.height || null, itag: f.itag || null };
            idmmacMeta[f.url] = meta;
          }
        });
      }
    } catch {}
  });

  function tryCaptureURL(url) {
    try {
      if (/\.(mp4|m4v|webm|mov|m3u8)(\?|#|$)/i.test(url)) {
        idmmacCandidates.add(url);
      }
    } catch {}
  }

  function createOverlay(video) {
    const wrapper = document.createElement('div');
    wrapper.className = 'idmmac-overlay';
    const button = document.createElement('button');
    button.className = 'idmmac-btn';
    button.title = 'Download with IDMMac';
    button.textContent = 'Download';
    button.addEventListener('click', (e) => {
      e.stopPropagation();
      e.preventDefault();
      tryOpenMenu(video, button);
    });
    wrapper.appendChild(button);
    document.body.appendChild(wrapper);
    positionOverlay(wrapper, video);
    const ro = new ResizeObserver(() => positionOverlay(wrapper, video));
    ro.observe(video);
    const so = () => positionOverlay(wrapper, video);
    window.addEventListener('scroll', so, { passive: true });
    window.addEventListener('resize', so, { passive: true });
  }

  function positionOverlay(wrapper, video) {
    const rect = video.getBoundingClientRect();
    const top = rect.top + window.scrollY + 8;
    const left = rect.left + window.scrollX + Math.max(8, rect.width - 110);
    wrapper.style.position = 'absolute';
    wrapper.style.zIndex = 2147483000;
    wrapper.style.top = `${Math.max(8, top)}px`;
    wrapper.style.left = `${Math.max(8, left)}px`;
    wrapper.style.display = rect.width > 80 && rect.height > 60 ? 'block' : 'none';
  }

  function tryOpenMenu(video, anchorButton) {
    const sources = collectVideoSources(video);
    idmmacCandidates.forEach((u) => {
      if (!sources.some((s) => s.url === u)) {
        sources.push({ url: u, label: inferLabel(u) });
      }
    });
    if (!sources.length && video.currentSrc) {
      sources.push({ url: video.currentSrc, label: inferLabel(video.currentSrc) });
    }
    if (!sources.length) return;
    showMenu(anchorButton, sources);
  }

  function collectVideoSources(video) {
    const list = [];
    if (video.src) list.push({ url: video.src, label: inferLabel(video.src) });
    video.querySelectorAll('source').forEach((s) => {
      const url = s.src || s.getAttribute('src');
      if (url) list.push({ url, label: s.getAttribute('label') || s.getAttribute('res') || inferLabel(url) });
    });
    const dataUrl = video.getAttribute('data-src') || video.getAttribute('data-url');
    if (dataUrl) list.push({ url: dataUrl, label: inferLabel(dataUrl) });
    const seen = new Set();
    return list.filter((it) => {
      try { new URL(it.url); } catch { return false; }
      const k = it.url.split('#')[0];
      if (seen.has(k)) return false;
      seen.add(k); return true;
    });
  }

  function inferLabel(url) {
    const m = /([0-9]{3,4})p(?![a-z])/i.exec(url) || /_(\d{3,4})\./i.exec(url);
    if (m) return `${m[1]}p`;
    if (/\.m3u8(\?|#|$)/i.test(url)) return 'HLS playlist';
    if (/\.mp4(\?|#|$)/i.test(url)) return 'MP4';
    return 'Video';
  }

  function extractSizeFromUrl(u) {
    try {
      const url = new URL(u);
      const clen = url.searchParams.get('clen');
      if (clen) {
        const n = parseInt(clen, 10);
        return isNaN(n) ? null : n;
      }
    } catch {}
    return null;
  }

  function buildLabel(base, sizeBytes, meta) {
    const parts = [];
    if (base) parts.push(base);
    if (meta && (meta.width || meta.height)) {
      const dim = `${meta.height || ''}${meta.height ? 'p' : ''}`;
      if (dim) parts.unshift(dim);
    }
    if (meta && meta.itag) {
      parts.push(`itag ${meta.itag}`);
    }
    if (meta && meta.mime) parts.push(meta.mime.split('/')[1] || meta.mime);
    if (typeof sizeBytes === 'number' && sizeBytes > 0) parts.push(formatBytes(sizeBytes));
    if (meta && (meta.hasAudio || meta.hasVideo)) {
      if (meta.hasAudio && meta.hasVideo) parts.push('AV'); else if (meta.hasVideo) parts.push('Video'); else if (meta.hasAudio) parts.push('Audio');
    }
    return parts.filter(Boolean).join(' • ');
  }

  function formatBytes(n) {
    const units = ['B','KB','MB','GB','TB'];
    let v = n;
    let i = 0;
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
    return (i === 0 ? `${v.toFixed(0)} ${units[i]}` : `${v.toFixed(1)} ${units[i]}`);
  }

  function showMenu(anchor, sources) {
    closeMenu();
    const menu = document.createElement('div');
    menu.className = 'idmmac-menu';
    sources.forEach((s) => {
      const url = s.url;
      const meta = idmmacMeta[url] || {};
      const size = meta.size || extractSizeFromUrl(url) || null;
      const label = buildLabel(s.label || meta.label || inferLabel(url), size, meta);
      const item = document.createElement('div');
      item.className = 'idmmac-menu-item';
      item.textContent = `Download ${label}`;
      item.addEventListener('click', (e) => {
        e.stopPropagation();
        e.preventDefault();
        const isYouTube = /(^|\.)youtube\.com$/i.test(location.hostname) || /(^|\.)youtu\.be$/i.test(location.hostname);
        if (isYouTube) {
          sendToApp(location.href, { itag: meta.itag || null, target: url });
        } else {
          sendToApp(url);
        }
        closeMenu();
      });
      menu.appendChild(item);
      if (!size && isExtensionContextValid()) {
        try {
          api.runtime.sendMessage({ type: 'idmmac_head', url, referer: location.href }, (resp) => {
            // Check for context invalidation
            if (api.runtime.lastError || (browser && browser.runtime && browser.runtime.lastError)) {
              return; // Silently fail - size enrichment is optional
            }
            if (resp && typeof resp.length === 'number' && resp.length > 0) {
              item.textContent = `Download ${buildLabel(s.label || inferLabel(url), resp.length, meta)}`;
            }
          });
        } catch {}
      }
    });
    document.body.appendChild(menu);
    const r = anchor.getBoundingClientRect();
    menu.style.position = 'absolute';
    menu.style.zIndex = 2147483001;
    menu.style.top = `${r.bottom + window.scrollY + 4}px`;
    menu.style.left = `${r.left + window.scrollX}px`;
    setTimeout(() => {
      window.addEventListener('click', closeMenu, { once: true });
    }, 0);
  }

  function closeMenu() {
    const m = document.querySelector('.idmmac-menu');
    if (m) m.remove();
  }

  // Check if extension context is still valid
  function isExtensionContextValid() {
    try {
      const api = (typeof browser !== 'undefined' ? browser : chrome);
      // Try to access runtime.id - if this throws or returns undefined, context is invalid
      return !!(api && api.runtime && api.runtime.id);
    } catch {
      return false;
    }
  }

  function sendToApp(url, extras) {
    try {
      const api = (typeof browser !== 'undefined' ? browser : chrome);
      
      // If extension context is invalid, use direct fallback
      if (!isExtensionContextValid()) {
        console.warn('IDMMac: Extension context invalidated. Using fallback method. Please reload the page for full functionality.');
        buildAndOpenDirect(url, extras);
        return;
      }

      const buildAndOpen = (cookieHeader) => {
        try {
          const headers = {
            Referer: location.href,
            Origin: location.origin,
            'User-Agent': navigator.userAgent
          };
          if (cookieHeader && cookieHeader.trim().length > 0) {
            headers['Cookie'] = cookieHeader;
          } else if (new URL(url).origin === location.origin) {
            const c = document.cookie;
            if (c && c.trim().length > 0) headers['Cookie'] = c;
          }
          const json = JSON.stringify(headers);
          const b64 = btoa(unescape(encodeURIComponent(json)));
          const extraParam = extras ? `&x=${encodeURIComponent(btoa(unescape(encodeURIComponent(JSON.stringify(extras)))))}` : '';
          const urlParam = encodeURIComponent(url);
          const headersParam = encodeURIComponent(b64);
          window.open(`idmmac://add?url=${urlParam}&headers=${headersParam}${extraParam}`, '_blank');
        } catch (e) {
          console.warn('IDMMac build/open error', e);
          // Try direct fallback on any error
          buildAndOpenDirect(url, extras);
        }
      };
      try {
        api.runtime.sendMessage({ type: 'idmmac_getCookies', url }, (resp) => {
          // Check for context invalidation (Firefox uses lastError, Chrome uses runtime.lastError)
          if ((api.runtime.lastError) || (browser && browser.runtime && browser.runtime.lastError)) {
            const err = api.runtime.lastError || browser.runtime.lastError;
            console.warn('IDMMac: Failed to get cookies, using fallback:', err ? err.message : 'unknown');
            buildAndOpen('');
            return;
          }
          const cookieHeader = resp && resp.cookie ? resp.cookie : '';
          buildAndOpen(cookieHeader);
        });
      } catch (_) {
        buildAndOpen('');
      }
    } catch (e) {
      console.warn('IDMMac video send error', e);
      // Final fallback
      buildAndOpenDirect(url, extras);
    }
  }

  // Direct fallback when extension context is invalid
  function buildAndOpenDirect(url, extras) {
    try {
      const headers = {
        Referer: location.href,
        Origin: location.origin,
        'User-Agent': navigator.userAgent
      };
      // Try to get same-origin cookies from document.cookie
      try {
        if (new URL(url).origin === location.origin) {
          const c = document.cookie;
          if (c && c.trim().length > 0) headers['Cookie'] = c;
        }
      } catch {}
      
      const json = JSON.stringify(headers);
      const b64 = btoa(unescape(encodeURIComponent(json)));
      const extraParam = extras ? `&x=${encodeURIComponent(btoa(unescape(encodeURIComponent(JSON.stringify(extras)))))}` : '';
      const urlParam = encodeURIComponent(url);
      const headersParam = encodeURIComponent(b64);
      window.open(`idmmac://add?url=${urlParam}&headers=${headersParam}${extraParam}`, '_blank');
    } catch (e) {
      console.error('IDMMac direct fallback error', e);
    }
  }

  function scanRoot(root) {
    try {
      root.querySelectorAll('video').forEach((v) => {
        hasAnyVideo = true;
        if (v.dataset.idmmacBound) return;
        v.dataset.idmmacBound = '1';
        createOverlay(v);
      });
    } catch {}
    try {
      root.querySelectorAll('*').forEach((el) => {
        if (el.shadowRoot) scanRoot(el.shadowRoot);
      });
    } catch {}
  }

  function scan() {
    hasAnyVideo = false;
    scanRoot(document);
    // Show the floating button only when there are no <video> elements,
    // but we have detected downloadable media via network hooks.
    if (!hasAnyVideo && idmmacCandidates.size > 0) ensureGlobalButton();
  }

  function ensureGlobalButton() {
    if (globalBtn) {
      globalBtn.style.display = 'block';
      return;
    }
    
    // Check if extension context is valid before trying to get URL
    if (!isExtensionContextValid()) {
      return; // Skip creating button if context is invalid
    }
    
    globalBtn = document.createElement('button');
    globalBtn.className = 'idmmac-global-btn';
    try {
      const iconUrl = api.runtime.getURL('icons/icon24.png');
      const img = document.createElement('img');
      img.src = iconUrl;
      img.alt = 'IDMMac';
      img.style.width = '16px';
      img.style.height = '16px';
      img.style.display = 'inline-block';
      img.style.verticalAlign = 'middle';
      globalBtn.appendChild(img);
    } catch {
      // If icon fails, just use text
    }
    const span = document.createElement('span');
    span.textContent = 'Download Video';
    span.style.marginLeft = '6px';
    globalBtn.appendChild(span);
    globalBtn.title = 'Download with IDMMac';
    globalBtn.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      const list = collectGlobalSources();
      if (!list.length) return;
      showMenu(globalBtn, list);
    });
    document.body.appendChild(globalBtn);
  }

  function collectGlobalSources() {
    const sources = [];
    idmmacCandidates.forEach((u) => sources.push({ url: u, label: inferLabel(u) }));
    try {
      document.querySelectorAll('video').forEach((v) => {
        if (v.currentSrc) sources.push({ url: v.currentSrc, label: inferLabel(v.currentSrc) });
      });
    } catch {}
    const seen = new Set();
    return sources.filter((s) => {
      const k = (s.url || '').split('#')[0];
      if (seen.has(k)) return false; seen.add(k); return true;
    });
  }

  const observer = new MutationObserver(() => scan());
  observer.observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener('load', scan);
  document.addEventListener('DOMContentLoaded', scan);
  setInterval(scan, 2000);
})();
