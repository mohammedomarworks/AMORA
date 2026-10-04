const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const root = process.cwd();
const workerSource = fs.readFileSync(`${root}/BrowserExtensions/Chrome/service-worker.js`, 'utf8');
const contentSource = fs.readFileSync(`${root}/BrowserExtensions/Chrome/content.js`, 'utf8');
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
const event = () => ({items: [], addListener(fn) { this.items.push(fn); }});
const youtubeURL = url => /^https:\/\/(www\.)?(youtube\.com\/(watch|shorts)\b|youtu\.be\/)/i.test(url || '');
const patternMatches = (url, patterns) => !patterns || patterns.some(pattern =>
  pattern.includes('youtube.com/watch') ? url.includes('youtube.com/watch') :
  pattern.includes('youtube.com/shorts') ? url.includes('youtube.com/shorts/') :
  pattern.includes('youtu.be') ? url.includes('youtu.be/') : false
);
const asyncCallback = fn => queueMicrotask(fn);
const longTimerUnref = (fn, ms) => {
  const timer = setTimeout(fn, ms);
  if (ms >= 30000) timer.unref();
  return timer;
};

async function testContentScript() {
  const videoListeners = new Map();
  const video = {
    paused: false, currentTime: 14, duration: 80, readyState: 4,
    currentSrc: 'https://media.invalid/player', src: '', playCalls: 0, pauseCalls: 0,
    addEventListener(name, fn) { if (!videoListeners.has(name)) videoListeners.set(name, new Set()); videoListeners.get(name).add(fn); },
    removeEventListener(name, fn) { videoListeners.get(name)?.delete(fn); },
    pause() { this.pauseCalls += 1; this.paused = true; },
    play() { this.playCalls += 1; this.paused = false; return Promise.resolve(); }
  };
  const runtimeListeners = [];
  class MutationObserver { constructor(fn) { this.fn = fn; } observe() {} disconnect() {} }
  const document = {title: 'Demo video', documentElement: {}, querySelector: selector => selector === 'video' ? video : null};
  const window = {handlers: new Map(), addEventListener(name, fn) { this.handlers.set(name, fn); }, removeEventListener(name, fn) { if (this.handlers.get(name) === fn) this.handlers.delete(name); }};
  const chrome = {runtime: {
    lastError: null,
    sendMessage(_message, callback) { callback?.(); },
    onMessage: {addListener(fn) { runtimeListeners.push(fn); }, removeListener(fn) { const i = runtimeListeners.indexOf(fn); if (i >= 0) runtimeListeners.splice(i, 1); }}
  }};
  const context = {chrome, document, window, location: {href: 'https://www.youtube.com/watch?v=demo'}, MutationObserver,
    console: {info() {}, warn() {}, error() {}}, setTimeout, clearTimeout, setInterval, clearInterval,
    Date, Number, Promise, Map, Set, String, JSON};
  vm.createContext(context);
  const invoke = message => new Promise((resolve, reject) => {
    try {
      const keepOpen = runtimeListeners[0](message, {}, resolve);
      if (!keepOpen) reject(new Error('content command did not keep its response channel open'));
    } catch (error) { reject(error); }
  });
  try {
    vm.runInContext(contentSource, context);
    assert.equal(runtimeListeners.length, 1);
    const pause = await invoke({type: 'mediaCommand', provider: 'youtube', action: 'pause', requestId: 'content-pause', tabId: 11});
    assert.equal(pause.type, 'mediaCommandResult');
    assert.equal(pause.success, true); assert.equal(pause.requestId, 'content-pause'); assert.equal(pause.action, 'pause'); assert.equal(pause.tabId, 11); assert.equal(video.paused, true);
    const play = await invoke({type: 'mediaCommand', provider: 'youtube', action: 'play', requestId: 'content-play', tabId: 11});
    assert.equal(play.success, true); assert.equal(video.paused, false); assert.equal(video.playCalls, 1);
    const duplicate = await invoke({type: 'mediaCommand', provider: 'youtube', action: 'play', requestId: 'content-play', tabId: 11});
    assert.deepEqual(duplicate, play); assert.equal(video.playCalls, 1, 'duplicate request must reuse acknowledgement');
    vm.runInContext(contentSource, context);
    assert.equal(runtimeListeners.length, 1, 'reinjection must not leave duplicate runtime listeners');
    assert.equal(videoListeners.get('pause').size, 1, 'reinjection must remove old video handlers');
    const afterReinject = await invoke({type: 'mediaCommand', provider: 'youtube', action: 'pause', requestId: 'content-reinject', tabId: 11});
    assert.equal(afterReinject.success, true); assert.equal(afterReinject.requestId, 'content-reinject');
    console.log('content.js mocked-DOM: PASS (video pause/play, response identity, duplicate idempotency, safe reinjection)');
  } finally {
    context.__AMORA_CONTENT_SCRIPT__?.cleanup?.();
  }
}

async function testWorker() {
  const tabs = new Map([
    [11, {id: 11, windowId: 2, active: true, url: 'https://www.youtube.com/watch?v=a'}],
    [22, {id: 22, windowId: 2, active: false, url: 'https://www.youtube.com/watch?v=b'}],
    [33, {id: 33, windowId: 2, active: false, url: 'https://example.org/'}]
  ]);
  const media = new Map([
    [11, {provider: 'YouTube', title: 'A', isPlaying: true, currentTime: 8, duration: 100, url: tabs.get(11).url}],
    [22, {provider: 'YouTube', title: 'B', isPlaying: false, currentTime: 0, duration: 80, url: tabs.get(22).url}]
  ]);
  const posted = []; const commands = []; const logs = []; const storage = {};
  let failNextCommand = true;
  const nativeMessage = event();
  const nativePort = {onMessage: nativeMessage, onDisconnect: event(), postMessage(message) { posted.push(message); }};
  const runtimeMessage = event();
  const chrome = {
    runtime: {lastError: null, connectNative() { return nativePort; }, onMessage: runtimeMessage},
    storage: {session: {get(_key, callback) { asyncCallback(() => callback(storage)); }, set(value, callback) { Object.assign(storage, value); asyncCallback(() => callback?.()); }}},
    tabs: {
      onActivated: event(), onUpdated: event(), onRemoved: event(), onReplaced: event(),
      query(query, callback) {
        asyncCallback(() => {
          let result = [...tabs.values()].filter(tab => patternMatches(tab.url, query.url));
          if (query.active) result = result.filter(tab => tab.active);
          if (query.windowId != null) result = result.filter(tab => tab.windowId === query.windowId);
          callback(result);
        });
      },
      get(tabId, callback) { asyncCallback(() => callback(tabs.get(tabId) || null)); },
      sendMessage(tabId, message, _options, callback) {
        asyncCallback(() => {
          if (message.type === 'contentPing') {
            const state = media.get(tabId); chrome.runtime.lastError = null;
            callback({type: 'contentPong', requestId: message.requestId, tabId: message.tabId, success: true, url: tabs.get(tabId)?.url || '', hasVideo: !!state, state: state || null});
          } else if (message.type === 'mediaCommand') {
            commands.push({tabId, action: message.action, requestId: message.requestId});
            if (failNextCommand) {
              failNextCommand = false; chrome.runtime.lastError = {message: 'Could not establish connection. Receiving end does not exist.'};
              callback(null); chrome.runtime.lastError = null; return;
            }
            chrome.runtime.lastError = null;
            const state = media.get(tabId);
            if (!state) { callback(null); return; }
            state.isPlaying = message.action === 'play';
            callback({type: 'mediaCommandResult', success: true, requestId: message.requestId, action: message.action, tabId, state: {...state}});
          }
        });
      }
    },
    scripting: {executeScript(_details, callback) { asyncCallback(() => { chrome.runtime.lastError = null; callback(); }); }},
    windows: {WINDOW_ID_NONE: -1, onFocusChanged: event(), getLastFocused(_options, callback) { asyncCallback(() => callback({id: 2, focused: true})); }}
  };
  vm.runInNewContext(workerSource, {chrome,
    console: {info(...args) { logs.push(args.join(' ')); }, debug() {}, warn() {}, error() {}},
    setTimeout: longTimerUnref, clearTimeout, Date, Map, Set, Promise, Number, String, Object, Array});
  const waitFor = async (predicate, label, maxMs = 1500) => {
    const started = Date.now();
    while (!predicate()) {
      if (Date.now() - started > maxMs) throw new Error(`timed out waiting for ${label}`);
      await wait(5);
    }
  };
  const latest = type => posted.filter(item => item.type === type).at(-1);
  try {
    await waitFor(() => latest('mediaState')?.tabId === 11, 'initial YouTube state');
    assert.equal(latest('mediaState').isPlaying, true);
    chrome.tabs.onActivated.items[0]({tabId: 33, windowId: 2}); await wait(15);
    assert.equal(latest('mediaState').tabId, 11); assert.equal(latest('mediaState').isInBackground, true);
    nativeMessage.items[0]({type: 'mediaCommand', provider: 'youtube', action: 'pause', requestId: 'worker-pause', tabId: 11});
    await waitFor(() => latest('mediaCommandResult')?.requestId === 'worker-pause', 'pause acknowledgement');
    assert.equal(latest('mediaCommandResult').success, true); assert.equal(latest('mediaCommandResult').tabId, 11);
    assert.equal(media.get(11).isPlaying, false); assert.equal(commands.length, 2, 'first send error should cause one recovery retry');
    nativeMessage.items[0]({type: 'mediaCommand', provider: 'youtube', action: 'play', requestId: 'worker-play', tabId: 11});
    await waitFor(() => latest('mediaCommandResult')?.requestId === 'worker-play', 'play acknowledgement');
    assert.equal(latest('mediaCommandResult').success, true); assert.equal(media.get(11).isPlaying, true);
    chrome.tabs.onUpdated.items[0](11, {status: 'loading'}, tabs.get(11)); await wait(10);
    chrome.tabs.onUpdated.items[0](11, {status: 'complete'}, tabs.get(11));
    await waitFor(() => latest('mediaState')?.tabId === 11 && latest('mediaState').isPlaying, 'YouTube tab reload recovery');
    media.get(11).isPlaying = false;
    runtimeMessage.items[0]({type: 'mediaState', ...media.get(11)}, {tab: tabs.get(11)}); await wait(10);
    media.get(22).isPlaying = true;
    runtimeMessage.items[0]({type: 'mediaState', ...media.get(22)}, {tab: tabs.get(22)});
    await waitFor(() => latest('mediaState')?.tabId === 22, 'second playing tab selection');
    nativeMessage.items[0]({type: 'mediaCommand', provider: 'youtube', action: 'pause', requestId: 'worker-second-tab', tabId: 22});
    await waitFor(() => latest('mediaCommandResult')?.requestId === 'worker-second-tab', 'second-tab pause acknowledgement');
    assert.equal(latest('mediaCommandResult').success, true); assert.equal(latest('mediaCommandResult').tabId, 22); assert.equal(media.get(22).isPlaying, false);
    tabs.delete(22); chrome.tabs.onRemoved.items[0](22); await wait(15);
    assert.equal(latest('mediaState').tabId, 11, 'closed selected tab must fall back to remaining tracked media tab');
    tabs.delete(11); chrome.tabs.onRemoved.items[0](11); await wait(15);
    assert.equal(latest('clear').type, 'clear');
    assert(logs.some(line => line.includes('Could not establish connection. Receiving end does not exist.')), 'exact Chrome error must be logged');
    assert(logs.some(line => line.includes('content script recovery verified; retrying command once')));
    assert(logs.some(line => line.includes('trackedYouTubeTab')));
    console.log('service-worker mocked Chrome APIs: PASS (background targeting, send failure diagnostics, reinjection + one retry, correlated acks, multi-tab selection, reload and close cleanup)');
  } finally {
    for (const item of posted) void item;
  }
}

(async () => {
  await testContentScript();
  await testWorker();
})().catch(error => { console.error(error); process.exitCode = 1; });
