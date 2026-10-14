// BrowserExtension/content.js - Content script for YouTube Music
// Extracts high-res metadata, mediaSession state, <video> element progress, and handles controls.

(function () {
  'use strict';

  let lastReportedState = null;
  let lastTimeUpdate = 0;
  let currentVideo = null;

  function getVideoElement() {
    if (currentVideo && document.contains(currentVideo)) {
      return currentVideo;
    }
    const videos = document.querySelectorAll('video');
    for (const v of videos) {
      if (v.src || v.currentSrc || !v.paused || v.currentTime > 0) {
        currentVideo = v;
        return v;
      }
    }
    currentVideo = videos[0] || null;
    return currentVideo;
  }

  function upscaleArtworkUrl(url) {
    if (!url) return null;
    return url
      .replace(/=w\d+-h\d+/, '=w1200-h1200')
      .replace(/=s\d+(-c)?/, '=s1200$1')
      .replace(/hqdefault\.jpg/, 'maxresdefault.jpg')
      .replace(/mqdefault\.jpg/, 'maxresdefault.jpg');
  }

  function getHighResArtwork() {
    // 1. mediaSession artwork (highest resolution)
    if (navigator.mediaSession?.metadata?.artwork?.length) {
      const artworks = navigator.mediaSession.metadata.artwork;
      let best = artworks[artworks.length - 1];
      for (const item of artworks) {
        if (item.sizes && parseInt(item.sizes) >= 512) {
          best = item;
          break;
        }
      }
      if (best?.src) return upscaleArtworkUrl(best.src);
    }

    // 2. DOM player bar thumbnail
    const thumbImg = document.querySelector('#song-image img, ytmusic-player-bar .image img');
    if (thumbImg && thumbImg.src && !thumbImg.src.startsWith('data:')) {
      return upscaleArtworkUrl(thumbImg.src);
    }

    return null;
  }

  function getVideoId() {
    try {
      const url = new URL(window.location.href);
      return url.searchParams.get('v') || '';
    } catch (e) {
      return '';
    }
  }

  function extractState() {
    const video = getVideoElement();
    const meta = navigator.mediaSession?.metadata;

    const currentTime = video ? video.currentTime : 0;
    const duration = video ? video.duration : 0;
    const isPaused = video ? video.paused : true;
    const playbackRate = video ? video.playbackRate : 1.0;

    // Title & Artist fallback
    let title = meta?.title || '';
    let artist = meta?.artist || '';
    let album = meta?.album || '';

    if (!title) {
      const titleElem = document.querySelector('ytmusic-player-bar .title, .ytmusic-player-bar.title');
      if (titleElem) title = titleElem.textContent.trim();
    }

    if (!artist) {
      const bylineElem = document.querySelector('ytmusic-player-bar .byline, .ytmusic-player-bar.byline');
      if (bylineElem) {
        const parts = bylineElem.textContent.split('•');
        artist = parts[0]?.trim() || '';
        if (parts.length > 1 && !album) {
          album = parts[1]?.trim() || '';
        }
      }
    }

    const artworkUrl = getHighResArtwork();
    const videoId = getVideoId();

    return {
      type: 'PLAYBACK_STATE',
      isPlaying: !isPaused,
      trackName: title || 'Unknown Title',
      artistName: artist || 'YouTube Music',
      albumName: album || '',
      duration: isFinite(duration) ? duration : 0,
      currentTime: isFinite(currentTime) ? currentTime : 0,
      playbackRate: playbackRate,
      artworkUrl: artworkUrl,
      url: window.location.href,
      videoId: videoId,
      appName: 'YouTube Music',
      timestamp: Date.now()
    };
  }

  function sendState(force = false) {
    const state = extractState();
    const now = Date.now();

    if (!force && lastReportedState) {
      const sameTrack =
        lastReportedState.trackName === state.trackName &&
        lastReportedState.artistName === state.artistName &&
        lastReportedState.isPlaying === state.isPlaying;

      const timeDelta = Math.abs(state.currentTime - lastReportedState.currentTime);
      if (sameTrack && timeDelta < 0.4 && now - lastTimeUpdate < 480) {
        return; // Throttle time updates to at most once per 480-500ms
      }
    }

    lastReportedState = state;
    lastTimeUpdate = now;

    try {
      chrome.runtime.sendMessage(state).catch(() => {
        // Extension background may be reloading
      });
    } catch (e) {
      // Ignored
    }
  }

  // MARK: - Playback Controls

  function handleControl(action, payload = {}) {
    const video = getVideoElement();

    switch (action) {
      case 'play':
        if (video) video.play().catch(() => {});
        else clickSelector('#play-pause-button, button[aria-label="Play"]');
        break;

      case 'pause':
        if (video) video.pause();
        else clickSelector('#play-pause-button, button[aria-label="Pause"]');
        break;

      case 'togglePlayPause':
        clickSelector('#play-pause-button, button[aria-label="Play"], button[aria-label="Pause"]', () => {
          if (video) {
            video.paused ? video.play().catch(() => {}) : video.pause();
          }
        });
        break;

      case 'next':
        clickSelector('.next-button, button[aria-label="Next song"], button[aria-label="Next"]');
        break;

      case 'previous':
        clickSelector('.previous-button, button[aria-label="Previous song"], button[aria-label="Previous"]');
        break;

      case 'seek':
        if (video && typeof payload.time === 'number') {
          video.currentTime = payload.time;
        }
        break;

      case 'like':
        clickSelector('#like-button-renderer tp-yt-paper-icon-button.like, button[aria-label="Like"]');
        break;

      case 'dislike':
        clickSelector('#like-button-renderer tp-yt-paper-icon-button.dislike, button[aria-label="Dislike"]');
        break;
    }

    // Immediately notify state update after action
    setTimeout(() => sendState(true), 150);
  }

  function clickSelector(selector, fallback = null) {
    const btn = document.querySelector(selector);
    if (btn) {
      btn.click();
    } else if (fallback) {
      fallback();
    }
  }

  // MARK: - Event Listeners

  function attachVideoListeners() {
    const video = getVideoElement();
    if (!video) return;

    video.removeEventListener('play', onPlayEvent);
    video.removeEventListener('pause', onPauseEvent);
    video.removeEventListener('seeked', onSeekedEvent);
    video.removeEventListener('ratechange', onRateChangeEvent);
    video.removeEventListener('timeupdate', onTimeUpdateEvent);

    video.addEventListener('play', onPlayEvent);
    video.addEventListener('pause', onPauseEvent);
    video.addEventListener('seeked', onSeekedEvent);
    video.addEventListener('ratechange', onRateChangeEvent);
    video.addEventListener('timeupdate', onTimeUpdateEvent);
  }

  function onPlayEvent() { sendState(true); }
  function onPauseEvent() { sendState(true); }
  function onSeekedEvent() { sendState(true); }
  function onRateChangeEvent() { sendState(true); }
  function onTimeUpdateEvent() { sendState(false); }

  // Listen for mediaSession metadata updates
  if (navigator.mediaSession) {
    try {
      const origSet = Object.getOwnPropertyDescriptor(Navigator.prototype, 'mediaSession')?.set;
      const proxy = new Proxy(navigator.mediaSession, {
        set(target, prop, value) {
          target[prop] = value;
          if (prop === 'metadata' || prop === 'playbackState') {
            setTimeout(() => sendState(true), 100);
          }
          return true;
        }
      });
    } catch (e) {
      // Fallback
    }
  }

  // Listen for DOM changes in player bar (track changes)
  const observer = new MutationObserver(() => {
    sendState(false);
  });
  observer.observe(document.body, { childList: true, subtree: true, attributes: false });

  // Handle messages from background worker
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === 'CONTROL') {
      handleControl(message.action, message);
      sendResponse({ status: 'ok' });
    } else if (message.type === 'GET_STATE') {
      sendResponse(extractState());
    }
    return true;
  });

  // Init
  function init() {
    attachVideoListeners();
    setInterval(attachVideoListeners, 3000);
    // Ensure state is emitted at least every 500 ms while playing
    setInterval(() => {
      const v = getVideoElement();
      if (v && !v.paused) {
        sendState(false);
      }
    }, 500);
    sendState(true);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();