// ============================================================
// Dynamics 365 Text Resizer — Background Script
// ============================================================

// Initialise default settings on first install. On update, fill in any
// keys missing from earlier versions without clobbering user-set values.
chrome.runtime.onInstalled.addListener((details) => {
  if (details.reason === 'install') {
    chrome.storage.sync.set({
      enabled: true,
      autoFit: true,
      minHeight: 180,
      showHighlight: true,
      customFields: []
    });
  } else if (details.reason === 'update') {
    chrome.storage.sync.get({ autoFit: undefined }, (stored) => {
      if (stored.autoFit === undefined) {
        chrome.storage.sync.set({ autoFit: true });
      }
    });
  }
  chrome.browserAction.setBadgeBackgroundColor({ color: '#0078d4' });
  chrome.browserAction.setBadgeTextColor({ color: '#ffffff' });
});

// Re-apply badge colours on browser startup
chrome.runtime.onStartup.addListener(() => {
  chrome.browserAction.setBadgeBackgroundColor({ color: '#0078d4' });
  chrome.browserAction.setBadgeTextColor({ color: '#ffffff' });
});

// Update the badge count when the content script reports enhanced fields
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'updateBadge') {
    const text = msg.count > 0 ? String(msg.count) : '';
    if (sender.tab && sender.tab.id) {
      chrome.browserAction.setBadgeText({ text, tabId: sender.tab.id });
    }
    sendResponse({ ok: true });
  }
  return true;
});
