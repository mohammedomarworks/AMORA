const HOST_NAME = "com.amora.browser";
let port = null;

function post(message) {
  if (!port) return false;
  try {
    port.postMessage(message);
    return true;
  } catch (_) {
    port = null;
    return false;
  }
}

function connect() {
  try {
    port = chrome.runtime.connectNative(HOST_NAME);
  } catch (_) {
    port = null;
    return;
  }

  port.onMessage.addListener((message) => {
    if (message?.type === "hello" || message?.type === "pong") return;
    if (message?.type !== "playPause") return;
    chrome.tabs.query({active: true, lastFocusedWindow: true}, (tabs) => {
      if (chrome.runtime.lastError || !tabs[0]?.id) return;
      chrome.tabs.sendMessage(tabs[0].id, {type: "playPause"}, () => {
        void chrome.runtime.lastError;
      });
    });
  });

  port.onDisconnect.addListener(() => {
    // lastError must be read in this callback or Chrome logs it as an
    // unchecked runtime.lastError. No message may be posted after this.
    void chrome.runtime.lastError;
    port = null;
  });
  post({type: "hello", app: "AMORA", version: "4.2"});
}

connect();

port.onMessage.addListener((message) => {
  if (!message || message.type !== "playPause") return;
  chrome.tabs.query({active: true, lastFocusedWindow: true}, (tabs) => {
    if (tabs[0]?.id) chrome.tabs.sendMessage(tabs[0].id, {type: "playPause"});
  });
});

chrome.runtime.onMessage.addListener((message, sender) => {
  if (!message || message.type !== "mediaState" || !sender.tab?.id) return;
  chrome.tabs.query({active: true, lastFocusedWindow: true}, (tabs) => {
    if (tabs[0]?.id !== sender.tab.id) return;
    post(message);
  });
});

function clearIfNotYouTube(tabId) {
  chrome.tabs.get(tabId, (tab) => {
    const url = tab?.url || "";
    if (!/^https:\/\/(www\.)?(youtube\.com\/watch|youtube\.com\/shorts|youtu\.be\/)/.test(url)) {
      post({type: "clear"});
    }
  });
}

chrome.tabs.onActivated.addListener(({tabId}) => clearIfNotYouTube(tabId));
chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.status === "loading") clearIfNotYouTube(tabId);
});
