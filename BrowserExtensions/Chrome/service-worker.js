const HOST_NAME = "com.amora.browser";
const STORAGE_KEY = "amoraTrackedMediaTabs";
const STORAGE_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const YOUTUBE_TAB_PATTERNS = [
  "https://www.youtube.com/watch*",
  "https://youtube.com/watch*",
  "https://www.youtube.com/shorts/*",
  "https://youtube.com/shorts/*",
  "https://youtu.be/*"
];
let port = null;
let reconnectTimer = null;
let persistTimer = null;
let trackedMediaTabs = new Map();
let currentMediaTabId = null;
let lastControlledTabId = null;
let activeTabId = null;
let lastFocusedWindowId = null;
let chromeWindowFocused = null;
let pendingYouTubeNavigations = new Set();
let commandFinalizers = new Map();
let completedCommandRequests = new Set();

function controlLog(event, details = {}) {
  const record = {event, timestamp: Date.now(), ...details};
  console.info("[AMORA Control][Diagnostics]", event, JSON.stringify(record));
}

function rememberCompletedCommand(requestId) {
  completedCommandRequests.add(requestId);
  setTimeout(() => completedCommandRequests.delete(requestId), 30000);
}

function post(message) {
  if (!port) return false;
  try {
    port.postMessage(message);
    return true;
  } catch (error) {
    port = null;
    controlLog("native port post failed", {type: message?.type ?? "unknown", requestId: message?.requestId ?? null, error: String(error)});
    return false;
  }
}

function connect() {
  if (port) return;
  try {
    port = chrome.runtime.connectNative(HOST_NAME);
    controlLog("native port connected", {host: HOST_NAME});
  } catch (error) {
    port = null;
    controlLog("native port connect threw", {host: HOST_NAME, error: String(error)});
    scheduleReconnect();
    return;
  }

  port.onMessage.addListener((message) => {
    if (message?.type === "hello" || message?.type === "pong") return;
    if (message?.type === "mediaCommand") {
      controlLog("native command received", {requestId: message.requestId, action: message.action, provider: message.provider, requestedTabId: message.tabId});
      handleCommand(message);
    }
    if (message?.type === "contentPing") handleContentPing(message);
  });

  port.onDisconnect.addListener(() => {
    const error = chrome.runtime.lastError;
    controlLog("native port disconnected", {runtimeError: error?.message ?? null});
    port = null;
    scheduleReconnect();
  });
  post({type: "hello", app: "AMORA", version: "4.4"});
}

connect();

function scheduleReconnect() {
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => { reconnectTimer = null; connect(); }, 2000);
}

function isYouTubeURL(url) {
  return /^https:\/\/(www\.)?(youtube\.com\/(watch|shorts)\b|youtu\.be\/)/i.test(url || "");
}

function isYouTubeOrigin(url) {
  return /^https:\/\/(www\.)?(youtube\.com|youtu\.be)(\/|$)/i.test(url || "");
}

function finiteNumber(value, fallback = 0) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function tabState(tab) {
  return {
    tabId: tab.tabId,
    windowId: tab.windowId,
    url: tab.url,
    provider: "YouTube",
    title: tab.title,
    isPlaying: tab.isPlaying,
    currentTime: tab.currentTime,
    duration: tab.duration,
    lastSeen: tab.lastSeen,
    contentScriptReady: tab.contentScriptReady,
    hasVideo: tab.hasVideo,
    lastPlayingAt: tab.lastPlayingAt,
    lastInteractedAt: tab.lastInteractedAt,
    lastControlledAt: tab.lastControlledAt,
    isActive: tab.isActive
  };
}

function schedulePersist() {
  if (persistTimer) clearTimeout(persistTimer);
  persistTimer = setTimeout(() => {
    persistTimer = null;
    const payload = {
      tabs: [...trackedMediaTabs.values()].map(tabState),
      currentMediaTabId,
      lastControlledTabId
    };
    try {
      chrome.storage.session.set({[STORAGE_KEY]: payload}, () => { void chrome.runtime.lastError; });
    } catch (_) {
      // Session storage is only a recovery aid; live state remains in memory.
    }
  }, 150);
}

function removeTrackedTab(tabId) {
  const removed = trackedMediaTabs.delete(tabId);
  if (lastControlledTabId === tabId) lastControlledTabId = null;
  if (currentMediaTabId === tabId) currentMediaTabId = null;
  if (removed) schedulePersist();
  return removed;
}

function sortedByRecentPlaying(tabs) {
  return tabs.sort((a, b) =>
    (b.lastPlayingAt || 0) - (a.lastPlayingAt || 0) ||
    (b.lastInteractedAt || 0) - (a.lastInteractedAt || 0) ||
    (b.lastControlledAt || 0) - (a.lastControlledAt || 0) ||
    a.tabId - b.tabId
  );
}

// Policy: active playback always wins. Of multiple playing tabs, the most
// recently transitioned-to-playing tab wins; ties use recent tab interaction,
// recent AMORA control, then ascending tab ID. When all tabs are paused, keep
// AMORA's last controlled tab; otherwise retain the most recently played tab so
// Play can resume it from the background, then prefer the active/recent tab.
function resolveMediaControlTarget() {
  const tabs = [...trackedMediaTabs.values()];
  const playing = sortedByRecentPlaying(tabs.filter(tab => tab.isPlaying));
  if (playing.length) return playing[0];

  const controlled = trackedMediaTabs.get(lastControlledTabId);
  if (controlled) return controlled;

  const previouslyPlaying = sortedByRecentPlaying(tabs.filter(tab => (tab.lastPlayingAt || 0) > 0));
  if (previouslyPlaying.length) return previouslyPlaying[0];

  const active = tabs.filter(tab => tab.isActive && (lastFocusedWindowId == null || tab.windowId === lastFocusedWindowId));
  if (active.length) return active.sort((a, b) => a.tabId - b.tabId)[0];

  const recentlyInteracted = tabs.sort((a, b) =>
    (b.lastInteractedAt || 0) - (a.lastInteractedAt || 0) || a.tabId - b.tabId
  );
  return recentlyInteracted[0] || null;
}

function publishCurrentState() {
  const target = resolveMediaControlTarget();
  currentMediaTabId = target?.tabId ?? null;
  if (!target) {
    post({type: "clear", trackedMediaTabCount: 0, currentMediaTabId: null});
    schedulePersist();
    return;
  }

  const isActive = target.tabId === activeTabId && target.windowId === lastFocusedWindowId;
  const snapshot = {
    type: "mediaState",
    browser: "Chrome",
    provider: "YouTube",
    tabId: target.tabId,
    windowId: target.windowId,
    title: target.title,
    isPlaying: target.isPlaying,
    currentTime: target.currentTime,
    duration: target.duration,
    url: target.url,
    lastSeen: target.lastSeen,
    contentScriptReady: target.contentScriptReady,
    hasVideo: target.hasVideo,
    isActive,
    isInBackground: !isActive || chromeWindowFocused === false,
    trackedMediaTabCount: trackedMediaTabs.size,
    currentMediaTabId: target.tabId,
    capabilities: {play: true, pause: true, next: false, previous: false, seek: false}
  };
  post(snapshot);
  schedulePersist();
}

function updateTrackedState(tabId, windowId, message, {publish = true, controlled = false} = {}) {
  if (!Number.isInteger(tabId) || !message || message.provider !== "YouTube" || !isYouTubeURL(message.url)) return null;
  const now = Date.now();
  const previous = trackedMediaTabs.get(tabId);
  const isPlaying = message.isPlaying === true;
  const record = {
    tabId,
    windowId: Number.isInteger(windowId) ? windowId : (previous?.windowId ?? -1),
    url: String(message.url),
    provider: "YouTube",
    title: typeof message.title === "string" ? message.title.slice(0, 1000) : "",
    isPlaying,
    currentTime: finiteNumber(message.currentTime),
    duration: finiteNumber(message.duration),
    lastSeen: now,
    contentScriptReady: true,
    hasVideo: true,
    lastPlayingAt: isPlaying ? (previous?.isPlaying ? previous.lastPlayingAt : now) : (previous?.lastPlayingAt || 0),
    lastInteractedAt: previous?.lastInteractedAt || 0,
    lastControlledAt: controlled ? now : (previous?.lastControlledAt || 0),
    isActive: previous?.isActive === true || tabId === activeTabId
  };
  trackedMediaTabs.set(tabId, record);
  if (controlled) lastControlledTabId = tabId;
  if (publish) publishCurrentState();
  return record;
}

function updateFromContentPing(tab, result) {
  if (result?.state && result.hasVideo === true) {
    return updateTrackedState(tab.id, tab.windowId, result.state, {publish: false});
  }
  if (result?.hasVideo === false) removeTrackedTab(tab.id);
  return null;
}

function sendContentPing(tabId, requestId, callback) {
  let settled = false;
  const finish = (result) => {
    if (settled) return;
    settled = true;
    clearTimeout(timer);
    callback(result);
  };
  controlLog("content ping sent", {requestId, targetTabId: tabId});
  const timeoutMs = 1200;
  const timer = setTimeout(() => {
    controlLog("content ping timed out", {requestId, targetTabId: tabId, timeoutMs});
    finish({reachable: false, reason: "content_script_unavailable", runtimeError: "ping_timeout"});
  }, timeoutMs);
  chrome.tabs.sendMessage(tabId, {type: "contentPing", requestId, tabId}, {frameId: 0}, (result) => {
    const error = chrome.runtime.lastError;
    if (settled) {
      controlLog("late content ping callback", {requestId, targetTabId: tabId, runtimeError: error?.message ?? null});
      return;
    }
    if (error) {
      controlLog("content ping failed", {requestId, targetTabId: tabId, runtimeError: error.message});
      finish({reachable: false, reason: "content_script_unavailable", runtimeError: error.message});
      return;
    }
    if (!result || result.type !== "contentPong" || result.requestId !== requestId || result.tabId !== tabId) {
      controlLog("content ping acknowledgement mismatch", {requestId, targetTabId: tabId, responseRequestId: result?.requestId ?? null, responseTabId: result?.tabId ?? null, responseType: result?.type ?? null});
      finish({reachable: false, reason: "acknowledgement_not_returned", runtimeError: null});
      return;
    }
    controlLog("content script responded", {requestId, targetTabId: tabId, hasVideo: result.hasVideo === true});
    finish({reachable: true, ...result});
  });
}

function pingAfterInjection(tab, requestId, callback) {
  controlLog("content script reinjection requested", {requestId, targetTabId: tab.id});
  let settled = false;
  const finish = (result) => {
    if (settled) return;
    settled = true;
    clearTimeout(injectionTimer);
    callback(result);
  };
  const injectionTimeoutMs = 1500;
  const injectionTimer = setTimeout(() => {
    controlLog("content script injection timed out", {requestId, targetTabId: tab.id, timeoutMs: injectionTimeoutMs});
    finish({ready: false, reason: "content_script_unavailable", url: tab.url || "", hasVideo: false, runtimeError: "injection_timeout"});
  }, injectionTimeoutMs);
  chrome.scripting.executeScript({target: {tabId: tab.id, frameIds: [0]}, files: ["content.js"]}, () => {
    const injectionError = chrome.runtime.lastError;
    if (settled) return;
    if (injectionError) {
      controlLog("content script injection failed", {requestId, targetTabId: tab.id, runtimeError: injectionError.message});
      finish({ready: false, reason: "content_script_unavailable", runtimeError: injectionError.message, url: tab.url || "", hasVideo: false});
      return;
    }
    clearTimeout(injectionTimer);
    settled = true;
    controlLog("content script injection completed", {requestId, targetTabId: tab.id});
    setTimeout(() => sendContentPing(tab.id, requestId, (result) => {
      if (!result.reachable) {
        callback({ready: false, reason: "content_script_unavailable", runtimeError: result.runtimeError, url: tab.url || "", hasVideo: false});
        return;
      }
      if (result.requestId !== requestId || result.tabId !== tab.id) {
        callback({ready: false, reason: "acknowledgement_not_returned", url: result.url || tab.url || "", hasVideo: false});
        return;
      }
      updateFromContentPing(tab, result);
      callback({ready: result.success === true && result.hasVideo === true, reason: result.reason || (result.hasVideo ? null : "content_video_unavailable"), url: result.url || tab.url || "", hasVideo: result.hasVideo === true, state: result.state || null});
    }), 100);
  });
}

function ensureContentScript(tabId, requestId, callback, forceInject = false) {
  chrome.tabs.get(tabId, (tab) => {
    const error = chrome.runtime.lastError;
    if (error || !tab?.id) {
      controlLog("target tab lookup failed", {requestId, targetTabId: tabId, runtimeError: error?.message ?? null});
      callback({ready: false, reason: "target_tab_does_not_exist", runtimeError: error?.message ?? null});
      return;
    }
    const tabUrl = tab.url || trackedMediaTabs.get(tabId)?.url || "";
    if (!isYouTubeURL(tabUrl)) {
      controlLog("target is not a supported YouTube tab", {requestId, targetTabId: tabId, url: tabUrl});
      callback({ready: false, reason: "target_tab_not_youtube", url: tabUrl});
      return;
    }

    if (forceInject) {
      pingAfterInjection(tab, requestId, callback);
      return;
    }

    sendContentPing(tab.id, requestId, (first) => {
      if (first.reachable) {
        if (first.requestId !== requestId || first.tabId !== tab.id) {
          callback({ready: false, reason: "acknowledgement_not_returned", url: first.url || tabUrl, hasVideo: false});
          return;
        }
        updateFromContentPing(tab, first);
        controlLog("content script preflight passed", {requestId, targetTabId: tab.id, hasVideo: first.hasVideo === true});
        callback({ready: first.success === true && first.hasVideo === true, reason: first.reason || (first.hasVideo ? null : "content_video_unavailable"), url: first.url || tabUrl, hasVideo: first.hasVideo === true, state: first.state || null});
        return;
      }
      controlLog("content script missing or stale", {requestId, targetTabId: tab.id, reason: first.reason, runtimeError: first.runtimeError ?? null});
      pingAfterInjection(tab, requestId, callback);
    });
  });
}

function sendResult(command, success, reason, state, targetTabId = null, details = {}) {
  const tabId = targetTabId ?? (Number.isInteger(command.tabId) ? command.tabId : null);
  const normalizedState = state ? {isPlaying: state.isPlaying === true, ...state} : null;
  const response = {type: "mediaCommandResult", provider: "youtube", action: command.action, requestId: command.requestId, tabId, targetTabId: tabId, success, reason: reason || null, state: normalizedState, timestamp: Date.now(), ...details};
  controlLog("command completion", {requestId: command.requestId, action: command.action, targetTabId: tabId, success, reason: reason || null, chromeRuntimeError: details.chromeRuntimeError ?? null});
  const finalize = commandFinalizers.get(command.requestId);
  if (finalize) finalize(response);
  else if (completedCommandRequests.has(command.requestId)) controlLog("late command outcome suppressed", {requestId: command.requestId, targetTabId: tabId, success, reason: reason || null});
  else if (!post(response)) controlLog("command response could not reach native host", {requestId: command.requestId, targetTabId: tabId});
}

function commandState(tab) {
  if (!tab) return null;
  const isActive = tab.tabId === activeTabId && tab.windowId === lastFocusedWindowId;
  return {
    provider: "YouTube",
    browser: "Chrome",
    tabId: tab.tabId,
    windowId: tab.windowId,
    title: tab.title,
    isPlaying: tab.isPlaying,
    currentTime: tab.currentTime,
    duration: tab.duration,
    url: tab.url,
    contentScriptReady: tab.contentScriptReady,
    hasVideo: tab.hasVideo,
    isActive,
    isInBackground: !isActive || chromeWindowFocused === false,
    trackedMediaTabCount: trackedMediaTabs.size,
    capabilities: {play: true, pause: true, next: false, previous: false, seek: false}
  };
}

function refreshActiveYouTubeTab(windowId, callback = () => {}) {
  const queryWindow = (id, focused) => {
    if (!Number.isInteger(id)) { callback(); return; }
    lastFocusedWindowId = id;
    if (typeof focused === "boolean") chromeWindowFocused = focused;
    chrome.tabs.query({active: true, windowId: id, url: YOUTUBE_TAB_PATTERNS}, (tabs) => {
      void chrome.runtime.lastError;
      activeTabId = tabs?.[0]?.id ?? null;
      for (const tab of trackedMediaTabs.values()) {
        if (tab.windowId === id) tab.isActive = tab.tabId === activeTabId;
      }
      callback();
    });
  };

  if (Number.isInteger(windowId)) {
    queryWindow(windowId, true);
    return;
  }
  chrome.windows.getLastFocused({}, (window) => {
    const error = chrome.runtime.lastError;
    if (error || !window?.id || window.id === chrome.windows.WINDOW_ID_NONE) {
      chromeWindowFocused = false;
      callback();
      return;
    }
    queryWindow(window.id, window.focused === true);
  });
}

function sendCommandToTab(tabId, command, retry) {
  const tracked = trackedMediaTabs.get(tabId);
  const routedCommand = {...command, type: "mediaCommand", tabId, targetTabId: tabId};
  let settled = false;
  const timeoutMs = 2000;
  const timeout = setTimeout(() => {
    if (settled) return;
    settled = true;
    controlLog("tabs.sendMessage response timed out", {requestId: command.requestId, action: command.action, targetTabId: tabId, retry, timeoutMs});
    recoverOrFail("acknowledgement_not_returned", null);
  }, timeoutMs);

  function recoverOrFail(reason, runtimeError) {
    if (!retry) {
      const recoveryRequestId = `${command.requestId}-recovery`;
      controlLog("recovering content script after command delivery failure", {requestId: command.requestId, recoveryRequestId, action: command.action, targetTabId: tabId, reason, runtimeError});
      ensureContentScript(tabId, recoveryRequestId, (readiness) => {
        if (!readiness.ready) {
          sendResult(command, false, readiness.reason || "content_script_unavailable", null, tabId, {chromeRuntimeError: readiness.runtimeError ?? runtimeError});
          return;
        }
        controlLog("content script recovery verified; retrying command once", {requestId: command.requestId, action: command.action, targetTabId: tabId});
        sendCommandToTab(tabId, command, true);
      }, true);
    } else {
      sendResult(command, false, reason === "acknowledgement_not_returned" ? "acknowledgement_not_returned" : "tabs_send_message_failed", null, tabId, {chromeRuntimeError: runtimeError});
    }
  }

  controlLog("tabs.sendMessage dispatch", {requestId: command.requestId, action: command.action, targetTabId: tabId, provider: "YouTube", trackedYouTubeTab: !!tracked && isYouTubeURL(tracked.url), retry});
  chrome.tabs.sendMessage(tabId, routedCommand, {frameId: 0}, (result) => {
    const error = chrome.runtime.lastError;
    if (settled) {
      controlLog("late tabs.sendMessage callback", {requestId: command.requestId, action: command.action, targetTabId: tabId, runtimeError: error?.message ?? null, responseReceived: !!result});
      return;
    }
    settled = true;
    clearTimeout(timeout);
    if (error || !result) {
      const runtimeError = error?.message ?? null;
      controlLog("tabs.sendMessage failed", {requestId: command.requestId, action: command.action, targetTabId: tabId, retry, runtimeError});
      recoverOrFail("tabs_send_message_failed", runtimeError);
      return;
    }
    controlLog("content-script response received", {requestId: command.requestId, responseRequestId: result.requestId ?? null, action: command.action, responseAction: result.action ?? null, targetTabId: tabId, responseTabId: result.tabId ?? null, success: result.success === true, reason: result.reason ?? null});
    if (result.type !== "mediaCommandResult" || result.requestId !== command.requestId || result.action !== command.action || result.tabId !== tabId || typeof result.success !== "boolean") {
      sendResult(command, false, "acknowledgement_not_returned", null, tabId);
      return;
    }

    let updated = trackedMediaTabs.get(tabId) || tracked;
    if (result.state && result.success === true) {
      updated = updateTrackedState(tabId, updated?.windowId, result.state, {publish: false, controlled: true}) || updated;
    } else if (result.success === true && updated) {
      updated.lastControlledAt = Date.now();
      lastControlledTabId = tabId;
    }
    if (result.success === true) {
      lastControlledTabId = tabId;
      publishCurrentState();
    }
    const selected = resolveMediaControlTarget() || updated;
    sendResult(command, result.success, result.reason || null, commandState(selected) || result.state || null, tabId);
  });
}

function handleCommand(command) {
  if (!command.requestId || (command.provider && command.provider.toLowerCase() !== "youtube") || !["play", "pause"].includes(command.action) || !Number.isInteger(command.tabId)) {
    sendResult(command, false, "invalid_command", null);
    return;
  }
  if (commandFinalizers.has(command.requestId) || completedCommandRequests.has(command.requestId)) {
    controlLog("duplicate native command request ignored", {requestId: command.requestId, action: command.action, requestedTabId: command.tabId});
    return;
  }
  const deadlineMs = 4600;
  const deadline = setTimeout(() => {
    const finalize = commandFinalizers.get(command.requestId);
    if (!finalize) return;
    commandFinalizers.delete(command.requestId);
    rememberCompletedCommand(command.requestId);
    controlLog("worker command deadline exceeded", {requestId: command.requestId, action: command.action, requestedTabId: command.tabId, deadlineMs});
    post({type: "mediaCommandResult", provider: "youtube", action: command.action, requestId: command.requestId, tabId: command.tabId, targetTabId: command.tabId, success: false, reason: "acknowledgement_not_returned", state: null, timestamp: Date.now()});
  }, deadlineMs);
  commandFinalizers.set(command.requestId, (response) => {
    if (!commandFinalizers.has(command.requestId)) return;
    commandFinalizers.delete(command.requestId);
    rememberCompletedCommand(command.requestId);
    clearTimeout(deadline);
    if (!post(response)) controlLog("native port unavailable for command response", {requestId: command.requestId, action: command.action, targetTabId: response.tabId});
  });
  controlLog("command validated", {requestId: command.requestId, action: command.action, provider: command.provider, requestedTabId: command.tabId});
  ready.then(() => {
    const target = resolveMediaControlTarget();
    if (!target?.tabId) { sendResult(command, false, "target_tab_does_not_exist", null, command.tabId); return; }
    const isTrackedYouTubeTab = trackedMediaTabs.has(target.tabId) && isYouTubeURL(target.url);
    controlLog("selected command target", {requestId: command.requestId, action: command.action, requestedTabId: command.tabId, selectedTabId: target.tabId, trackedYouTubeTab: isTrackedYouTubeTab, isActive: target.tabId === activeTabId && target.windowId === lastFocusedWindowId});
    if (!isTrackedYouTubeTab) {
      sendResult(command, false, "target_tab_not_youtube", null, command.tabId);
      return;
    }
    if (target.tabId !== command.tabId) {
      sendResult(command, false, "target_changed", null, command.tabId, {currentTargetTabId: target.tabId});
      return;
    }
    const routedCommand = {...command, tabId: target.tabId};
    ensureContentScript(target.tabId, command.requestId, (readiness) => {
      if (!readiness.ready) {
        controlLog("content preflight failed", {requestId: command.requestId, action: command.action, targetTabId: target.tabId, reason: readiness.reason, runtimeError: readiness.runtimeError ?? null});
        sendResult(command, false, readiness.reason || "content_script_unavailable", null, target.tabId, {chromeRuntimeError: readiness.runtimeError ?? null});
        return;
      }
      sendCommandToTab(target.tabId, routedCommand, false);
    });
  }).catch((error) => sendResult(command, false, "service_worker_internal_error", null, command.tabId, {error: String(error)}));
}

function handleContentPing(message) {
  if (!message.requestId) return;
  controlLog("AMORA content diagnostic requested", {requestId: message.requestId});
  ready.then(() => {
    let target = resolveMediaControlTarget();
    if (!target) {
      chrome.tabs.query({active: true, lastFocusedWindow: true, url: YOUTUBE_TAB_PATTERNS}, (tabs) => {
        const tab = (tabs || []).find(item => item?.id && isYouTubeURL(item.url));
        if (!tab) {
          post({type: "contentPong", requestId: message.requestId, tabId: null, success: false, reason: "youtube_tab_unavailable", url: "", hasVideo: false});
          return;
        }
        controlLog("content diagnostic target selected", {requestId: message.requestId, targetTabId: tab.id, trackedYouTubeTab: trackedMediaTabs.has(tab.id)});
        ensureContentScript(tab.id, message.requestId, (result) => {
          if (result.state) updateTrackedState(tab.id, tab.windowId, result.state);
          post({type: "contentPong", requestId: message.requestId, tabId: tab.id, success: result.ready, reason: result.reason || null, url: result.url || tab.url || "", hasVideo: result.hasVideo === true});
        });
      });
      return;
    }
    controlLog("content diagnostic target selected", {requestId: message.requestId, targetTabId: target.tabId, trackedYouTubeTab: trackedMediaTabs.has(target.tabId)});
    ensureContentScript(target.tabId, message.requestId, (result) => {
      if (result.state) updateTrackedState(target.tabId, target.windowId, result.state);
      post({type: "contentPong", requestId: message.requestId, tabId: target.tabId, success: result.ready, reason: result.reason || null, url: result.url || target.url || "", hasVideo: result.hasVideo === true});
    });
  });
}

function handleTabActivation(tabId, windowId) {
  activeTabId = tabId;
  lastFocusedWindowId = windowId;
  chromeWindowFocused = true;
  const now = Date.now();
  for (const tab of trackedMediaTabs.values()) {
    if (tab.windowId === windowId) tab.isActive = tab.tabId === tabId;
  }
  const selected = trackedMediaTabs.get(tabId);
  if (selected) selected.lastInteractedAt = now;
  publishCurrentState();
}

function handleTabUpdated(tabId, changeInfo, tab) {
  const wasTracked = trackedMediaTabs.has(tabId);
  if (changeInfo.url && !isYouTubeURL(changeInfo.url)) {
    pendingYouTubeNavigations.delete(tabId);
    if (wasTracked) {
      removeTrackedTab(tabId);
      publishCurrentState();
    }
    return;
  }
  if (changeInfo.status === "loading") {
    if (wasTracked || (changeInfo.url && isYouTubeURL(changeInfo.url))) pendingYouTubeNavigations.add(tabId);
    if (wasTracked) {
      removeTrackedTab(tabId);
      publishCurrentState();
    }
    return;
  }
  const nextURL = changeInfo.url || ((wasTracked || pendingYouTubeNavigations.has(tabId)) ? tab?.url : "") || "";
  if (changeInfo.status === "complete" && pendingYouTubeNavigations.has(tabId) && !isYouTubeURL(nextURL)) {
    pendingYouTubeNavigations.delete(tabId);
  }
  if (isYouTubeURL(nextURL) && (changeInfo.status === "complete" || changeInfo.url)) {
    pendingYouTubeNavigations.delete(tabId);
    ensureContentScript(tabId, `updated-${Date.now()}`, (result) => {
      if (result.state) updateTrackedState(tabId, tab?.windowId, result.state);
      else if (!result.hasVideo) {
        removeTrackedTab(tabId);
        publishCurrentState();
      }
    });
  }
}

function initialize() {
  return new Promise((resolve) => {
    const loadSession = (done) => {
      try {
        chrome.storage.session.get(STORAGE_KEY, (items) => {
          void chrome.runtime.lastError;
          const saved = items?.[STORAGE_KEY];
          if (saved && Array.isArray(saved.tabs)) {
            const now = Date.now();
            for (const item of saved.tabs) {
              if (!Number.isInteger(item.tabId) || !isYouTubeURL(item.url) || !item.hasVideo || now - finiteNumber(item.lastSeen, 0) > STORAGE_MAX_AGE_MS) continue;
              trackedMediaTabs.set(item.tabId, {
                tabId: item.tabId,
                windowId: Number.isInteger(item.windowId) ? item.windowId : -1,
                url: item.url,
                provider: "YouTube",
                title: typeof item.title === "string" ? item.title.slice(0, 1000) : "",
                isPlaying: item.isPlaying === true,
                currentTime: finiteNumber(item.currentTime),
                duration: finiteNumber(item.duration),
                lastSeen: finiteNumber(item.lastSeen, now),
                contentScriptReady: item.contentScriptReady === true,
                hasVideo: true,
                lastPlayingAt: finiteNumber(item.lastPlayingAt),
                lastInteractedAt: finiteNumber(item.lastInteractedAt),
                lastControlledAt: finiteNumber(item.lastControlledAt),
                isActive: false
              });
            }
            currentMediaTabId = Number.isInteger(saved.currentMediaTabId) ? saved.currentMediaTabId : null;
            lastControlledTabId = Number.isInteger(saved.lastControlledTabId) ? saved.lastControlledTabId : null;
          }
          done();
        });
      } catch (_) {
        done();
      }
    };

    loadSession(() => {
      chrome.tabs.query({url: YOUTUBE_TAB_PATTERNS}, (tabs) => {
        void chrome.runtime.lastError;
        const openTabs = new Map((tabs || []).filter(tab => Number.isInteger(tab.id)).map(tab => [tab.id, tab]));
        for (const [tabId, record] of trackedMediaTabs) {
          const openTab = openTabs.get(tabId);
          if (!openTab || !isYouTubeURL(openTab.url)) removeTrackedTab(tabId);
          else {
            record.url = openTab.url || record.url;
            record.windowId = openTab.windowId;
            record.isActive = openTab.active === true;
            if (openTab.active) {
              activeTabId = tabId;
              lastFocusedWindowId = openTab.windowId;
            }
          }
        }
        if (!trackedMediaTabs.has(lastControlledTabId)) lastControlledTabId = null;
        if (!trackedMediaTabs.has(currentMediaTabId)) currentMediaTabId = null;
        publishCurrentState();
        const supportedTabs = (tabs || []).filter(tab => Number.isInteger(tab.id) && isYouTubeURL(tab.url));
        if (!supportedTabs.length) { resolve(); return; }
        let remaining = supportedTabs.length;
        for (const tab of supportedTabs) {
          ensureContentScript(tab.id, `startup-${Date.now()}-${tab.id}`, (result) => {
            if (result.state) updateTrackedState(tab.id, tab.windowId, result.state, {publish: false});
            else if (!result.hasVideo) removeTrackedTab(tab.id);
            remaining -= 1;
            if (remaining === 0) {
              refreshActiveYouTubeTab(null, () => {
                publishCurrentState();
                resolve();
              });
            }
          });
        }
      });
    });
  });
}

const ready = initialize();

chrome.runtime.onMessage.addListener((message, sender) => {
  if (message?.type === "contentReady") {
    const tab = sender.tab;
    if (tab?.id && isYouTubeURL(tab.url || message.url)) {
      ready.then(() => ensureContentScript(tab.id, `ready-${Date.now()}`, (result) => {
        if (result.state) updateTrackedState(tab.id, tab.windowId, result.state);
      }));
    }
    return;
  }
  if (message?.type === "mediaUnavailable" && Number.isInteger(sender.tab?.id)) {
    const tab = sender.tab;
    if (!isYouTubeOrigin(tab.url || "") || !isYouTubeOrigin(message.url || "")) return;
    ready.then(() => {
      removeTrackedTab(tab.id);
      publishCurrentState();
    });
    return;
  }
  if (message?.type !== "mediaState" || !Number.isInteger(sender.tab?.id)) return;
  const tab = sender.tab;
  if (!isYouTubeURL(tab.url || message.url) || !isYouTubeURL(message.url)) return;
  ready.then(() => {
    updateTrackedState(tab.id, tab.windowId, message);
  });
});

chrome.tabs.onActivated.addListener(({tabId, windowId}) => {
  ready.then(() => handleTabActivation(tabId, windowId));
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  ready.then(() => handleTabUpdated(tabId, changeInfo, tab));
});

chrome.tabs.onRemoved.addListener((tabId) => {
  ready.then(() => {
    pendingYouTubeNavigations.delete(tabId);
    removeTrackedTab(tabId);
    publishCurrentState();
  });
});

chrome.windows.onFocusChanged.addListener((windowId) => {
  chromeWindowFocused = windowId !== chrome.windows.WINDOW_ID_NONE;
  if (!chromeWindowFocused) {
    ready.then(() => publishCurrentState());
    return;
  }
  refreshActiveYouTubeTab(windowId, () => {
    ready.then(() => publishCurrentState());
  });
});

if (chrome.tabs.onReplaced) {
  chrome.tabs.onReplaced.addListener((addedTabId, removedTabId) => {
    ready.then(() => {
      const wasTracked = trackedMediaTabs.has(removedTabId);
      removeTrackedTab(removedTabId);
      if (!wasTracked) {
        publishCurrentState();
        return;
      }
      chrome.tabs.get(addedTabId, (tab) => {
        if (!chrome.runtime.lastError && tab?.id && isYouTubeURL(tab.url)) {
          ensureContentScript(addedTabId, `replaced-${Date.now()}`, (result) => {
            if (result.state) updateTrackedState(addedTabId, tab.windowId, result.state);
            else publishCurrentState();
          });
        } else {
          void chrome.runtime.lastError;
          publishCurrentState();
        }
      });
    });
  });
}
