// BrowserExtension/background.js - Service worker for Lumo browser extension
// Manages local WebSocket connection to Lumo Mac app (127.0.0.1:19847) with Native Messaging fallback.

const WS_URL = 'ws://127.0.0.1:19847/ws';
const NATIVE_HOST = 'com.lumo.native';

let ws = null;
let nativePort = null;
let isWsConnected = false;
let isNativeConnected = false;
let reconnectTimer = null;
let lastKnownState = null;

function connectWebSocket() {
  if (ws && (ws.readyState === WebSocket.CONNECTING || ws.readyState === WebSocket.OPEN)) {
    return;
  }

  try {
    ws = new WebSocket(WS_URL);

    ws.onopen = () => {
      console.log('[Lumo Background] WebSocket connected to Mac app');
      isWsConnected = true;
      if (reconnectTimer) clearTimeout(reconnectTimer);

      // Handshake
      sendToMacApp({
        type: 'HANDSHAKE',
        version: chrome.runtime.getManifest().version,
        source: 'BrowserExtension',
        timestamp: Date.now()
      });

      // Send last state if available
      if (lastKnownState) {
        sendToMacApp(lastKnownState);
      }
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        handleMacAppMessage(msg);
      } catch (e) {
        console.error('[Lumo Background] Failed to parse message:', e);
      }
    };

    ws.onclose = () => {
      console.log('[Lumo Background] WebSocket disconnected');
      isWsConnected = false;
      ws = null;
      scheduleReconnect();
    };

    ws.onerror = (err) => {
      console.debug('[Lumo Background] WebSocket error:', err);
      isWsConnected = false;
    };
  } catch (err) {
    scheduleReconnect();
  }
}

function connectNativeMessaging() {
  if (nativePort || isWsConnected) return;

  try {
    nativePort = chrome.runtime.connectNative(NATIVE_HOST);
    isNativeConnected = true;

    nativePort.onMessage.addListener((msg) => {
      handleMacAppMessage(msg);
    });

    nativePort.onDisconnect.addListener(() => {
      console.log('[Lumo Background] Native messaging host disconnected');
      isNativeConnected = false;
      nativePort = null;
    });

    sendToMacApp({
      type: 'HANDSHAKE',
      version: chrome.runtime.getManifest().version,
      source: 'NativeHost',
      timestamp: Date.now()
    });
  } catch (err) {
    console.debug('[Lumo Background] Native messaging unavailable:', err);
  }
}

function scheduleReconnect() {
  if (reconnectTimer) clearTimeout(reconnectTimer);
  reconnectTimer = setTimeout(() => {
    connectWebSocket();
    if (!isWsConnected) {
      connectNativeMessaging();
    }
  }, 2000);
}

function sendToMacApp(data) {
  const jsonStr = JSON.stringify(data);

  if (isWsConnected && ws && ws.readyState === WebSocket.OPEN) {
    ws.send(jsonStr);
    return;
  }

  if (isNativeConnected && nativePort) {
    try {
      nativePort.postMessage(data);
      return;
    } catch (e) {
      isNativeConnected = false;
      nativePort = null;
    }
  }

  // If not connected, attempt connection
  connectWebSocket();
}

function handleMacAppMessage(msg) {
  if (msg.type === 'CONTROL') {
    forwardControlToTabs(msg.action, msg);
  } else if (msg.type === 'PING') {
    sendToMacApp({ type: 'PONG', timestamp: Date.now() });
  }
}

function forwardControlToTabs(action, payload) {
  chrome.tabs.query({ url: '*://music.youtube.com/*' }, (tabs) => {
    for (const tab of tabs) {
      chrome.tabs.sendMessage(tab.id, {
        type: 'CONTROL',
        action: action,
        time: payload.time
      }).catch(() => {});
    }
  });
}

// Listen for messages from content script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'PLAYBACK_STATE') {
    lastKnownState = message;
    sendToMacApp(message);
    sendResponse({ status: 'sent' });
  }
  return true;
});

// Periodic heartbeat
setInterval(() => {
  if (isWsConnected && ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'PING', timestamp: Date.now() }));
  } else {
    connectWebSocket();
  }
}, 15000);

// Start
connectWebSocket();