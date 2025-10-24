// Firefox MV2 uses browser.*
const api = (typeof browser !== 'undefined' ? browser : chrome);

// Intercept new downloads and redirect to nanojet:// scheme
api.downloads.onCreated.addListener(async (item) => {
  try {
    // Only intercept http/https
    if (!item || !item.url || !/^https?:/i.test(item.url)) return;
    // Cancel Chrome's own download
    await api.downloads.cancel(item.id);
    try { await api.downloads.erase({ id: item.id }); } catch (_) {}

    const encoded = encodeURIComponent(item.url);
    // Attempt to open the custom scheme; on macOS this will route to the app
    await api.tabs.create({ url: `nanojet://add?url=${encoded}` });
  } catch (e) {
    console.warn('NanoJet intercept error:', e);
  }
});

// Context menu for links and media (video/audio)
api.runtime.onInstalled.addListener(() => {
  try {
    api.contextMenus.create({
      id: 'nanojet_download_link',
      title: 'Download with NanoJet',
      contexts: ['link']
    });
    api.contextMenus.create({
      id: 'nanojet_download_media',
      title: 'Download video with NanoJet',
      contexts: ['video', 'audio']
    });
  } catch (e) {
    console.warn('Context menu create error:', e);
  }
});

api.contextMenus.onClicked.addListener(async (info, tab) => {
  try {
    let targetUrl = null;
    if (info.menuItemId === 'nanojet_download_link' && info.linkUrl) {
      targetUrl = info.linkUrl;
    } else if (info.menuItemId === 'nanojet_download_media' && info.srcUrl) {
      targetUrl = info.srcUrl;
    }
    if (!targetUrl || !/^https?:/i.test(targetUrl)) return;
    const headers = await buildHeadersForUrl(targetUrl, tab?.url);
    const headersB64 = encodeURIComponent(btoa(unescape(encodeURIComponent(JSON.stringify(headers)))));
    const encoded = encodeURIComponent(targetUrl);
    await api.tabs.create({ url: `nanojet://add?url=${encoded}&headers=${headersB64}` });
  } catch (e) {
    console.warn('Context menu click error:', e);
  }
});

// Handle cookie/header requests and lightweight HEAD size probe from content scripts
api.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || !message.type) return;
  if (message.type === 'nanojet_getCookies' && message.url) {
    buildCookieHeader(message.url).then((cookieHeader) => {
      sendResponse({ cookie: cookieHeader });
    }).catch(() => sendResponse({ cookie: '' }));
    return true; // keep the channel open for async response
  }
  if (message.type === 'nanojet_head' && message.url) {
    (async () => {
      try {
        const headers = new Headers();
        if (message.referer) headers.set('Referer', message.referer);
        headers.set('Accept', '*/*');
        headers.set('Accept-Encoding', 'identity');
        // First try HEAD
        let res = await fetch(message.url, { method: 'HEAD', redirect: 'follow', cache: 'no-store', headers });
        let len = res.headers.get('content-length');
        if (!len || parseInt(len, 10) <= 0) {
          headers.set('Range', 'bytes=0-0');
          res = await fetch(message.url, { method: 'GET', redirect: 'follow', cache: 'no-store', headers });
          const cr = res.headers.get('Content-Range');
          if (cr && /\/(\d+)$/i.test(cr)) {
            const m = cr.match(/\/(\d+)$/i);
            len = m && m[1] ? m[1] : null;
          }
        }
        sendResponse({ length: len ? parseInt(len, 10) : null });
      } catch (e) {
        sendResponse({ length: null });
      }
    })();
    return true;
  }
});

async function buildHeadersForUrl(targetUrl, referer) {
  const headers = {
    'User-Agent': navigator.userAgent
  };
  if (referer) headers['Referer'] = referer;
  const cookie = await buildCookieHeader(targetUrl);
  if (cookie) headers['Cookie'] = cookie;
  return headers;
}

async function buildCookieHeader(targetUrl) {
  try {
    const u = new URL(targetUrl);
    const cookies = await api.cookies.getAll({ url: u.origin });
    if (!cookies || cookies.length === 0) return '';
    const pairs = cookies
      .filter(c => !c.hostOnly || u.hostname.endsWith(c.domain.replace(/^\./, '')))
      .map(c => `${c.name}=${c.value}`);
    return pairs.join('; ');
  } catch (e) {
    return '';
  }
}


