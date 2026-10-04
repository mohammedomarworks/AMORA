(function () {
  // Replace any previous listener instance cleanly when the worker reinjects
  // after extension reload or a failed content-script handshake.
  try { globalThis.__AMORA_CONTENT_SCRIPT__?.cleanup?.(); } catch (_) {}
  const attachedVideos = new Map();
  const commandResponses = new Map();
  const cacheTimers = new Set();
  let mutationObserver = null;
  let intervalId = null;
  let navigateHandler = null;
  let popstateHandler = null;
  let messageHandler = null;

  function sendRuntimeMessage(message) {
    try {
      chrome.runtime.sendMessage(message, () => { void chrome.runtime.lastError; });
    } catch (_) {
      // The extension can be reloaded while this page context is still alive.
    }
  }

  function currentVideo() {
    const video = document.querySelector("video.html5-main-video") || document.querySelector("video");
    if (!video) return null;
    const hasLoadedMedia = !!(video.currentSrc || video.src || video.srcObject) || video.readyState >= 1 || video.duration > 0 || video.classList.contains("html5-main-video");
    return hasLoadedMedia ? video : null;
  }

  function videoSummary(video) {
    return {
      found: !!video,
      paused: video?.paused ?? null,
      currentTime: video && Number.isFinite(video.currentTime) ? video.currentTime : null,
      duration: video && Number.isFinite(video.duration) ? video.duration : null,
      readyState: video?.readyState ?? null,
      hasSource: !!(video?.currentSrc || video?.src)
    };
  }

  sendRuntimeMessage({type: "contentReady", url: location.href});

  let lastSent = 0;
  let lastMetadataKey = "";
  let lastHref = location.href;
  let unavailableTimer = null;
  let unavailableReportedKey = "";

  function isSupportedVideoURL(url) {
    return /^https:\/\/(www\.)?(youtube\.com\/(watch|shorts)\b|youtu\.be\/)/i.test(url || "");
  }

  function reportUnavailable() {
    if (unavailableReportedKey === location.href) return;
    unavailableReportedKey = location.href;
    sendRuntimeMessage({type: "mediaUnavailable", url: location.href});
  }

  function scheduleUnavailableIfPlayerMissing() {
    if (!isSupportedVideoURL(location.href)) {
      if (unavailableTimer) clearTimeout(unavailableTimer);
      unavailableTimer = null;
      reportUnavailable();
      return;
    }
    if (unavailableTimer) return;
    unavailableTimer = setTimeout(() => {
      unavailableTimer = null;
      if (!currentVideo()) reportUnavailable();
    }, 3000);
  }

  function mediaState(video) {
    return {
      provider: "YouTube",
      title: document.title || "",
      channel: document.querySelector("ytd-channel-name a")?.textContent?.trim() || "",
      isPlaying: !video.paused,
      currentTime: Number.isFinite(video.currentTime) ? video.currentTime : null,
      duration: Number.isFinite(video.duration) ? video.duration : null,
      url: location.href,
      capabilities: {play: true, pause: true, next: false, previous: false, seek: false}
    };
  }

  function sendState(force) {
    const video = currentVideo();
    if (!video) return;
    const state = mediaState(video);
    const metadataKey = `${state.url}\n${state.title}\n${state.channel}\n${state.duration}`;
    const metadataChanged = metadataKey !== lastMetadataKey;
    const now = Date.now();
    if (!force && !metadataChanged && now - lastSent < 1000) return;
    lastSent = now;
    lastMetadataKey = metadataKey;
    sendRuntimeMessage({type: "mediaState", browser: "Chrome", ...state});
  }

  function attach() {
    if (!isSupportedVideoURL(location.href)) {
      scheduleUnavailableIfPlayerMissing();
      return;
    }
    const video = currentVideo();
    if (!video) {
      scheduleUnavailableIfPlayerMissing();
      return;
    }
    if (unavailableTimer) {
      clearTimeout(unavailableTimer);
      unavailableTimer = null;
    }
    unavailableReportedKey = "";
    if (attachedVideos.has(video)) {
      sendState(false);
      return;
    }
    const listeners = [
      ...["play", "pause", "loadedmetadata", "durationchange", "seeked"].map(event => [event, () => sendState(true)]),
      ["timeupdate", () => sendState(false)]
    ];
    listeners.forEach(([event, listener]) => video.addEventListener(event, listener));
    attachedVideos.set(video, listeners);
    sendState(true);
  }

  messageHandler = (message, sender, sendResponse) => {
    if (message?.type === "contentPing") {
      const video = currentVideo();
      const response = {
        type: "contentPong",
        requestId: message.requestId,
        tabId: message.tabId ?? null,
        success: true,
        url: location.href,
        hasVideo: !!video,
        state: video ? mediaState(video) : null
      };
      console.info("[AMORA Control] content ping response", JSON.stringify({requestId: message.requestId, targetTabId: message.tabId ?? null, video: videoSummary(video), hasVideo: !!video}));
      sendResponse(response);
      return false;
    }
    if (message?.type !== "mediaCommand") return false;
    const requestId = typeof message.requestId === "string" ? message.requestId : "missing";
    const tabId = Number.isInteger(message.tabId) ? message.tabId : null;
    console.info("[AMORA Control][Diagnostics] content command received", JSON.stringify({requestId, action: message.action, targetTabId: tabId, provider: message.provider, timestamp: Date.now()}));
    if (message.provider !== "youtube" || !["play", "pause"].includes(message.action) || !requestId || requestId === "missing") {
      sendResponse({type: "mediaCommandResult", provider: "youtube", success: false, requestId, action: message.action || "unknown", tabId, reason: "invalid_command", state: null, timestamp: Date.now()});
      return false;
    }
    const previous = commandResponses.get(requestId);
    if (previous) {
      console.info("[AMORA Control] duplicate command request reused", JSON.stringify({requestId, action: message.action, targetTabId: tabId, completed: !!previous.response}));
      if (previous.response) sendResponse(previous.response);
      else previous.waiters.push(sendResponse);
      return true;
    }
    const entry = {response: null, waiters: [sendResponse]};
    commandResponses.set(requestId, entry);
    const respond = (success, reason, video, before) => {
      if (entry.response) return;
      const after = videoSummary(video);
      const response = {
        type: "mediaCommandResult",
        provider: "youtube",
        success,
        requestId,
        action: message.action,
        tabId,
        reason: reason || null,
        state: video ? mediaState(video) : null,
        timestamp: Date.now()
      };
      entry.response = response;
      for (const waiter of entry.waiters.splice(0)) waiter(response);
      console.info("[AMORA Control][Diagnostics] content command outcome", JSON.stringify({requestId, action: message.action, targetTabId: tabId, provider: "youtube", success, reason: reason || null, timestamp: Date.now(), before, after}));
      const timer = setTimeout(() => {
        cacheTimers.delete(timer);
        if (commandResponses.get(requestId) === entry) commandResponses.delete(requestId);
      }, 30000);
      cacheTimers.add(timer);
    };
    const video = currentVideo();
    if (!video) {
      console.info("[AMORA Control][Diagnostics] content video element not found", JSON.stringify({requestId, action: message.action, targetTabId: tabId, location: location.href, timestamp: Date.now()}));
      respond(false, "content_video_unavailable", null, videoSummary(null));
      return true;
    }
    const before = videoSummary(video);
    console.info("[AMORA Control] content video element found", JSON.stringify({requestId, action: message.action, targetTabId: tabId, before}));
    if (message.action === "pause") {
      console.info("[AMORA Control] pause attempted", JSON.stringify({requestId, targetTabId: tabId, before}));
      try {
        video.pause();
        const success = video.paused === true;
        if (success) sendState(true);
        respond(success, success ? null : "video_pause_failed", video, before);
      } catch (error) {
        respond(false, "video_pause_failed", video, before);
        console.error("[AMORA Control] pause exception", JSON.stringify({requestId, targetTabId: tabId, error: String(error)}));
      }
    } else {
      console.info("[AMORA Control] play attempted", JSON.stringify({requestId, targetTabId: tabId, before}));
      try {
        const playPromise = video.play();
        if (playPromise && typeof playPromise.then === "function") {
          playPromise.then(() => {
            const success = video.paused === false;
            if (success) sendState(true);
            respond(success, success ? null : "video_play_failed", video, before);
          }).catch(error => {
            respond(false, "video_play_failed", video, before);
            console.warn("[AMORA Control] play rejected", JSON.stringify({requestId, targetTabId: tabId, error: String(error)}));
          });
        } else {
          const success = video.paused === false;
          if (success) sendState(true);
          respond(success, success ? null : "video_play_failed", video, before);
        }
      } catch (error) {
        respond(false, "video_play_failed", video, before);
        console.error("[AMORA Control] play exception", JSON.stringify({requestId, targetTabId: tabId, error: String(error)}));
      }
    }
    return true;
  };
  chrome.runtime.onMessage.addListener(messageHandler);

  mutationObserver = new MutationObserver(attach);
  mutationObserver.observe(document.documentElement, {childList: true, subtree: true});
  navigateHandler = () => {
    lastMetadataKey = "";
    lastHref = location.href;
    attach();
    sendState(true);
  };
  popstateHandler = () => {
    lastMetadataKey = "";
    sendState(true);
  };
  window.addEventListener("yt-navigate-finish", navigateHandler);
  window.addEventListener("popstate", popstateHandler);
  attach();
  intervalId = setInterval(() => {
    if (location.href !== lastHref) {
      lastHref = location.href;
      lastMetadataKey = "";
      attach();
      sendState(true);
    } else {
      attach();
    }
  }, 1000);

  globalThis.__AMORA_CONTENT_SCRIPT__ = {
    cleanup() {
      mutationObserver?.disconnect();
      if (intervalId !== null) clearInterval(intervalId);
      if (unavailableTimer !== null) clearTimeout(unavailableTimer);
      if (messageHandler) chrome.runtime.onMessage.removeListener(messageHandler);
      if (navigateHandler) window.removeEventListener("yt-navigate-finish", navigateHandler);
      if (popstateHandler) window.removeEventListener("popstate", popstateHandler);
      for (const [videoElement, listeners] of attachedVideos) {
        for (const [event, listener] of listeners) videoElement.removeEventListener(event, listener);
      }
      for (const timer of cacheTimers) clearTimeout(timer);
      cacheTimers.clear();
      commandResponses.clear();
    }
  };
})();
