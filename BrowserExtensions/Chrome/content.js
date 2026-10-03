(function () {
  let lastSent = 0;
  const send = () => {
    const video = document.querySelector("video");
    if (!video) return;
    const now = Date.now();
    if (now - lastSent < 250 && !video.paused) return;
    lastSent = now;
    const channel = document.querySelector("ytd-channel-name a")?.textContent?.trim() || "";
    chrome.runtime.sendMessage({
      type: "mediaState",
      browser: "Chrome",
      provider: "YouTube",
      title: document.title || "",
      channel,
      isPlaying: !video.paused,
      currentTime: Number.isFinite(video.currentTime) ? video.currentTime : null,
      duration: Number.isFinite(video.duration) ? video.duration : null,
      url: location.href,
      controlAvailable: true
    });
  };
  const attach = () => {
    const video = document.querySelector("video");
    if (!video || video.__amoraAttached) return;
    video.__amoraAttached = true;
    ["play", "pause", "loadedmetadata", "durationchange", "seeked", "timeupdate"].forEach(e => video.addEventListener(e, send));
    send();
  };
  new MutationObserver(attach).observe(document.documentElement, {childList: true, subtree: true});
  attach();
  chrome.runtime.onMessage.addListener((message) => {
    if (message?.type !== "playPause") return;
    const video = document.querySelector("video");
    if (video) video.paused ? video.play() : video.pause();
  });
})();
