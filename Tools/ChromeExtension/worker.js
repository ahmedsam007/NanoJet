// Intercept new downloads and redirect to idmmac:// scheme
chrome.downloads.onCreated.addListener(async (item) => {
  try {
    // Only intercept http/https
    if (!item || !item.url || !/^https?:/i.test(item.url)) return;
    // Cancel Chrome's own download
    await chrome.downloads.cancel(item.id);
    await chrome.downloads.erase({ id: item.id });

    const encoded = encodeURIComponent(item.url);
    // Attempt to open the custom scheme; on macOS this will route to the app
    await chrome.tabs.create({ url: `idmmac://add?url=${encoded}` });
  } catch (e) {
    console.warn('IDMMac intercept error:', e);
  }
});

// Context menu for links and media (video/audio)
chrome.runtime.onInstalled.addListener(() => {
  try {
    chrome.contextMenus.create({
      id: 'idmmac_download_link',
      title: 'Download with IDMMac',
      contexts: ['link']
    });
    chrome.contextMenus.create({
      id: 'idmmac_download_media',
      title: 'Download video with IDMMac',
      contexts: ['video', 'audio']
    });
  } catch (e) {
    console.warn('Context menu create error:', e);
  }
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  try {
    let targetUrl = null;
    if (info.menuItemId === 'idmmac_download_link' && info.linkUrl) {
      targetUrl = info.linkUrl;
    } else if (info.menuItemId === 'idmmac_download_media' && info.srcUrl) {
      targetUrl = info.srcUrl;
    }
    if (!targetUrl || !/^https?:/i.test(targetUrl)) return;
    const encoded = encodeURIComponent(targetUrl);
    await chrome.tabs.create({ url: `idmmac://add?url=${encoded}` });
  } catch (e) {
    console.warn('Context menu click error:', e);
  }
});


