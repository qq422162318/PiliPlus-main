'use strict';

// Exercises the actual embedded page with fake media, DASH/HLS, and timers.
// No CDN, browser, or Flutter package download is needed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const source = fs.readFileSync(path.resolve(__dirname,
  '../../../lib/plugin/pl_player/js_web_video.dart'), 'utf8');
const html = source.match(/const html = r'''([\s\S]*?)''';/)[1];
const script = html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];

function page() {
  const messages = [], players = [], intervals = new Map(), timeouts = new Map();
  const listeners = new Map();
  let timerId = 0;
  const ranges = [];
  const media = {
    paused: true, ended: false, seeking: false, readyState: 0,
    currentTime: 0, duration: 120, volume: 1, playbackRate: 1,
    videoWidth: 1920, videoHeight: 1080, style: {},
    buffered: { get length() { return ranges.length; },
      start(i) { return ranges[i][0]; }, end(i) { return ranges[i][1]; } },
    addEventListener(name, fn) {
      if (!listeners.has(name)) listeners.set(name, []);
      listeners.get(name).push(fn);
    },
    playCalls: 0, allowPlay: true,
    play() { this.playCalls++; if (this.allowPlay) this.paused = false; },
    pause() { this.paused = true; },
  };
  const events = Object.fromEntries([
    'ERROR', 'MANIFEST_LOADED', 'PLAYBACK_METADATA_LOADED', 'PLAYBACK_PLAYING',
    'PLAYBACK_PAUSED', 'PLAYBACK_WAITING', 'PLAYBACK_ENDED', 'PLAYBACK_TIME_UPDATED',
    'PLAYBACK_STALLED', 'BUFFER_LEVEL_STATE_CHANGED', 'PLAYBACK_SEEKED',
    'PLAYBACK_NOT_ALLOWED',
  ].map(name => [name, name]));
  function MediaPlayer() {
    return { create() {
      const player = {
        callbacks: new Map(), seeks: [],
        on(name, fn) {
          if (!this.callbacks.has(name)) this.callbacks.set(name, []);
          this.callbacks.get(name).push(fn);
        },
        initialize(...args) { this.initialization = args; },
        updateSettings(settings) { this.settings = settings; },
        play() {}, pause() { media.pause(); }, reset() {},
        seek(time) { this.seeks.push(time); media.currentTime = time; },
        getAutoPlay() { return !!this.initialization?.[2]; },
        isPaused() { return media.paused; }, isReady() { return true; },
      };
      players.push(player);
      return player;
    } };
  }
  MediaPlayer.events = events;
  class Hls {
    static isSupported() { return true; }
    static Events = { ERROR: 'error', MANIFEST_PARSED: 'manifest', LEVEL_LOADED: 'level' };
    on() {} loadSource() {} attachMedia() {} destroy() {}
  }
  const windowListeners = new Map();
  const window = {
    innerWidth: 1920, innerHeight: 1080, devicePixelRatio: 1,
    dashjs: { MediaPlayer }, Hls,
    flutter_inappwebview: { callHandler(_, message) { messages.push(message); } },
    addEventListener(name, fn) {
      if (!windowListeners.has(name)) windowListeners.set(name, []);
      windowListeners.get(name).push(fn);
    },
  };
  const context = vm.createContext({ window, dashjs: window.dashjs,
    document: { getElementById() { return media; } },
    URL: { createObjectURL() { return 'blob:test'; }, revokeObjectURL() {} },
    Blob: class {}, Date, Math, Number, String, Error, isFinite,
    setInterval(fn, delay) { const id = ++timerId; intervals.set(id, { fn, delay }); return id; },
    clearInterval(id) { intervals.delete(id); },
    setTimeout(fn, delay) { const id = ++timerId; timeouts.set(id, { fn, delay }); return id; },
    clearTimeout(id) { timeouts.delete(id); },
  });
  vm.runInContext(script, context, { filename: 'embedded-dash-player.js' });
  function emit(name) { for (const fn of [...(listeners.get(name) || [])]) fn(); }
  function open(overrides = {}) {
    window.__dashOpen({ video: 'https://example.invalid/video', duration: 120,
      videoTrack: { segmentBase: { Initialization: '0-500', indexRange: '501-900' } },
      start: 0, autoplay: false, volume: 1, rate: 1, ...overrides });
  }
  function tick(delay) {
    for (const [id, task] of [...intervals]) {
      if (task.delay === delay && intervals.has(id)) task.fn();
    }
  }
  return { window, media, ranges, messages, players, listeners, intervals, timeouts,
    emit, open, tick, command(message) { window.__dashCommand(message); },
    resize(width, height, dpr = window.devicePixelRatio) {
      Object.assign(window, { innerWidth: width, innerHeight: height, devicePixelRatio: dpr });
      for (const fn of windowListeners.get('resize') || []) fn();
    } };
}

test('resume position is supplied to DASH before autoplay begins', () => {
  const p = page();
  p.open({ start: 79000, autoplay: true });
  assert.equal(p.players[0].initialization[3], 79);
});

test('an old resume callback cannot seek a newly opened video', () => {
  const p = page();
  p.open({ start: 79000 });
  p.open({ start: 0 });
  p.media.readyState = 1;
  p.emit('loadedmetadata');
  assert.equal(p.media.currentTime, 0);
  for (const timer of [...p.timeouts.values()]) {
    if (timer.delay === 5000) timer.fn();
  }
  assert.equal(p.media.currentTime, 0);
});

test('media state listeners do not grow across source switches', () => {
  const p = page();
  for (let i = 0; i < 10; i++) p.open();
  assert.equal(p.listeners.get('playing')?.length, 1);
});

test('HLS reports playing, buffering, and pause through media events', () => {
  const p = page();
  p.open({ video: 'https://example.invalid/live.m3u8' });
  p.command({ type: 'play' });
  p.emit('playing');
  p.emit('waiting');
  p.media.paused = true;
  p.emit('pause');
  const states = p.messages.filter(m => m.type === 'state').map(m =>
    [m.data.playing, m.data.buffering]);
  assert.deepEqual(states.slice(-3), [[true, false], [true, true], [false, false]]);
});

test('pause before metadata prevents delayed internal autoplay', () => {
  const p = page();
  p.open({ autoplay: true });
  p.command({ type: 'pause' });
  p.media.paused = false; // dash.js executes an already queued initial play.
  p.emit('play');
  assert.equal(p.media.paused, true);
  p.emit('playing');
  for (const callback of p.players[0].callbacks.get('PLAYBACK_PLAYING')) callback();
  assert.equal(p.messages.some(m => m.type === 'state' && m.data.playing), false);
});

test('pending play actually retries and pause cancels it', () => {
  const p = page();
  p.media.allowPlay = false;
  p.open({ autoplay: true });
  const firstCalls = p.media.playCalls;
  p.tick(150);
  assert.ok(p.media.playCalls > firstCalls, 'a poll is not a play retry');
  p.command({ type: 'pause' });
  const pausedCalls = p.media.playCalls;
  p.tick(150);
  assert.equal(p.media.playCalls, pausedCalls);
  assert.equal([...p.intervals.values()].filter(t => t.delay === 150).length, 0);
});

test('unpaused without playable data is not reported as successful startup', () => {
  const p = page();
  p.open({ autoplay: true });
  p.tick(150);
  assert.equal(p.messages.some(m => m.type === 'log' &&
    /pending play satisfied/.test(m.data)), false);
  p.media.readyState = 4;
  p.emit('playing');
  assert.equal([...p.intervals.values()].filter(t => t.delay === 150).length, 0);
});

test('switching sources clears per-open trace and startup timers', () => {
  const p = page();
  p.media.allowPlay = false;
  p.open({ autoplay: true });
  p.open({ autoplay: false });
  assert.equal([...p.intervals.values()].filter(t => t.delay === 150).length, 0);
  assert.equal([...p.timeouts.values()].filter(t => t.delay === 8000).length, 0);
  assert.equal([...p.intervals.values()].filter(t => t.delay === 1000).length, 1);
});

test('ending playback cancels the startup retry', () => {
  const p = page();
  p.media.allowPlay = false;
  p.open({ autoplay: true });
  p.emit('ended');
  const calls = p.media.playCalls;
  p.tick(150);
  assert.equal(p.media.playCalls, calls);
  assert.equal([...p.intervals.values()].filter(t => t.delay === 150).length, 0);
});

test('native and DASH ended events report one completion', () => {
  const p = page();
  p.open({ autoplay: true });
  p.emit('ended');
  for (const callback of p.players[0].callbacks.get('PLAYBACK_ENDED') || []) callback();
  assert.equal(p.messages.filter(m => m.type === 'ended').length, 1);
});

test('seek uses the DASH API so its scheduling follows the new position', () => {
  const p = page();
  p.open();
  p.command({ type: 'seek', time: 70 });
  assert.deepEqual(p.players[0].seeks, [70]);
  assert.equal(p.media.currentTime, 70);
});

test('live metadata does not send Infinity across the Flutter bridge', () => {
  const p = page();
  p.open({ video: 'https://example.invalid/live.m3u8' });
  p.media.duration = Infinity;
  p.emit('loadedmetadata');
  assert.equal(p.messages.filter(m => m.type === 'meta').at(-1).data.duration, 0);
});

test('HLS restores playback rate when opening a stream', () => {
  const p = page();
  p.open({ video: 'https://example.invalid/live.m3u8', rate: 1.5 });
  assert.equal(p.media.playbackRate, 1.5);
});

test('automatic fit preserves landscape and portrait video proportions', () => {
  const p = page();
  p.open();
  assert.equal(p.media.style.width, '1920px');
  assert.equal(p.media.style.height, '1080px');
  p.media.videoWidth = 1080;
  p.media.videoHeight = 1920;
  p.emit('loadedmetadata');
  assert.equal(p.media.style.width, '607.5px');
  assert.equal(p.media.style.height, '1080px');
  assert.equal(p.media.style.left, '656.25px');
});

test('fit modes and explicit ratios change the element, not the WebView viewport', () => {
  const p = page();
  p.open();
  p.resize(1600, 1000);
  function layout(fit, extra = {}) {
    p.command({ type: 'layout', fit, alignmentX: 0, alignmentY: 0, ...extra });
    return [p.media.style.width, p.media.style.height];
  }
  assert.deepEqual(layout('contain'), ['1600px', '900px']);
  assert.deepEqual(layout('cover'), ['1777.7777777777778px', '1000px']);
  assert.deepEqual(layout('fill'), ['1600px', '1000px']);
  assert.deepEqual(layout('fitWidth'), ['1600px', '900px']);
  assert.deepEqual(layout('fitHeight'), ['1777.7777777777778px', '1000px']);
  assert.deepEqual(layout('none'), ['1920px', '1080px']);
  assert.deepEqual(layout('scaleDown'), ['1600px', '900px']);
  assert.deepEqual(layout('contain', { aspectRatio: 4 / 3 }), ['1333.3333333333333px', '1000px']);
  assert.equal(p.window.innerWidth, 1600);
  assert.equal(p.window.innerHeight, 1000);
});

test('original-size video maps source pixels to physical pixels at high DPI', () => {
  const p = page();
  p.open({ layout: { fit: 'none' } });
  p.resize(1920, 1080, 1.5);
  assert.equal(p.media.style.width, '1280px');
  assert.equal(p.media.style.height, '720px');
  assert.ok(p.messages.some(m => m.type === 'log' &&
    /render viewport=1920x1080 dpr=1.5 targetPixels=2880x1620/.test(m.data)));
});

test('layout is reapplied on viewport resize without reopening playback', () => {
  const p = page();
  p.open();
  const player = p.players[0];
  p.resize(2560, 1440);
  assert.equal(p.media.style.width, '2560px');
  assert.equal(p.media.style.height, '1440px');
  assert.equal(p.players.length, 1);
  assert.equal(p.players[0], player);
});

test('a requested aspect ratio is retained while metadata arrives', () => {
  const p = page();
  p.media.videoWidth = p.media.videoHeight = 0;
  p.open({ layout: { fit: 'contain', aspectRatio: 4 / 3 } });
  assert.equal(p.media.style.objectFit, 'contain');
  p.media.videoWidth = 1920;
  p.media.videoHeight = 1080;
  p.emit('loadedmetadata');
  assert.equal(p.media.style.width, '1440px');
  assert.equal(p.media.style.height, '1080px');
  assert.equal(p.media.style.objectFit, 'fill');
});

test('buffer reports the range at the playhead, not a disconnected later range', () => {
  const p = page();
  p.open();
  p.ranges.push([0, 10], [100, 110]);
  p.media.currentTime = 5;
  p.emit('seeked');
  assert.equal(p.messages.filter(m => m.type === 'time').at(-1).data.buffer, 10);
  p.media.currentTime = 50;
  p.emit('seeked');
  assert.equal(p.messages.filter(m => m.type === 'time').at(-1).data.buffer, 0);
});
