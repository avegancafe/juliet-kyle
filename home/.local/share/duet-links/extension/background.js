// Links opened from the Claude Duet app window (chromium --app=https://claude.ai/duet)
// are handed to the duet-open-in-zen native host, which runs xdg-open.
// Tabs opened from normal Chromium windows are left alone.
const HOST = "com.kyle.duet_open_in_zen";
const waiting = new Set(); // new tabs whose real URL hasn't arrived yet

const isWebUrl = (url) => /^https?:\/\//.test(url || "");

async function fromDuet(sourceTabId) {
  try {
    const tab = await chrome.tabs.get(sourceTabId);
    const win = await chrome.windows.get(tab.windowId);
    return win.type === "app" && /^https:\/\/claude\.ai\//.test(tab.url || "");
  } catch {
    return false;
  }
}

function handOff(tabId, url) {
  waiting.delete(tabId);
  chrome.runtime.sendNativeMessage(HOST, { url }, () => {
    if (chrome.runtime.lastError) {
      console.error("duet-open-in-zen failed:", chrome.runtime.lastError.message);
      return; // leave the Chromium tab open so the link isn't lost
    }
    chrome.tabs.remove(tabId).catch(() => {});
  });
}

chrome.webNavigation.onCreatedNavigationTarget.addListener(async (d) => {
  if (!(await fromDuet(d.sourceTabId))) return;
  if (isWebUrl(d.url)) handOff(d.tabId, d.url);
  else waiting.add(d.tabId); // e.g. window.open() and then navigate
});

chrome.webNavigation.onBeforeNavigate.addListener((d) => {
  if (d.frameId === 0 && waiting.has(d.tabId) && isWebUrl(d.url)) handOff(d.tabId, d.url);
});

chrome.tabs.onRemoved.addListener((tabId) => waiting.delete(tabId));
