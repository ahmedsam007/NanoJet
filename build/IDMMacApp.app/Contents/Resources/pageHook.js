(() => {
  const post = (u) => { try { window.postMessage({ __idmmac_media: true, url: u }, '*'); } catch (e) {} };
  try {
    const of = window.fetch;
    window.fetch = async function(...args) {
      try {
        const u = typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url) ? args[0].url : '';
        if (u) post(u);
      } catch {}
      return await of.apply(this, args);
    };
  } catch {}
  try {
    const oo = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url, ...rest) {
      try { if (url) post(url); } catch {}
      return oo.apply(this, [method, url, ...rest]);
    };
  } catch {}

  // YouTube: post available formats from ytInitialPlayerResponse when present
  function postYTFormats() {
    try {
      const resp = (window.ytInitialPlayerResponse && window.ytInitialPlayerResponse.streamingData) || null;
      if (!resp) return;
      const formats = [];
      const push = (f) => {
        if (!f) return;
        let url = f.url || f.manifestUrl || '';
        if (!url && f.signatureCipher) {
          try {
            const p = new URLSearchParams(f.signatureCipher);
            url = p.get('url') || '';
            // NOTE: p.get('s') requires decipher; we skip those entries
          } catch {}
        }
        if (!url) return;
        const mime = (f.mimeType || '').split(';')[0] || '';
        const q = f.qualityLabel || f.quality || '';
        const clen = f.contentLength || (url.includes('clen=') ? (new URL(url)).searchParams.get('clen') : '') || '';
        let bytes = clen ? parseInt(clen, 10) : NaN;
        if ((!bytes || isNaN(bytes) || bytes <= 0) && typeof f.bitrate === 'number') {
          // Approximate size from bitrate * duration when contentLength is missing
          const dur = typeof f.approxDurationMs === 'string' ? parseInt(f.approxDurationMs, 10) : (typeof resp.approxDurationMs === 'string' ? parseInt(resp.approxDurationMs, 10) : NaN);
          if (dur && !isNaN(dur) && dur > 0) {
            const bits = f.bitrate * (dur / 1000);
            bytes = Math.floor(bits / 8);
          }
        }
        const hasAudio = !!(f.audioQuality || (mime.includes('audio/') || (mime.includes('video/') && (f.audioChannels || f.audioSampleRate))));
        const hasVideo = mime.includes('video/');
        const width = typeof f.width === 'number' ? f.width : null;
        const height = typeof f.height === 'number' ? f.height : null;
        const itag = typeof f.itag === 'number' ? f.itag : null;
        formats.push({ url, label: q || (mime || 'Video'), mime, hasAudio, hasVideo, size: (bytes && !isNaN(bytes) && bytes > 0) ? bytes : null, width, height, itag });
      };
      (resp.formats || []).forEach(push);
      (resp.adaptiveFormats || []).forEach(push);
      if (resp.hlsManifestUrl) formats.push({ url: resp.hlsManifestUrl, label: 'HLS playlist' });
      if (formats.length) {
        window.postMessage({ __idmmac_yt_formats: true, formats }, '*');
      }
    } catch {}
  }
  // Initial check and on SPA navigations
  try { postYTFormats(); } catch {}
  window.addEventListener('yt-navigate-finish', () => { try { postYTFormats(); } catch {} });
  const ytObs = new MutationObserver(() => { try { postYTFormats(); } catch {} });
  try { ytObs.observe(document.documentElement, { childList: true, subtree: true }); } catch {}
})();


