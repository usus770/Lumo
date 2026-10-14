// Lumo Mobile Web & iOS PWA Engine
// Developed by Ujjwal Singh (https://github.com/usus770)

class LumoPlayer {
  constructor() {
    this.audio = document.getElementById('audioElement');
    this.tracks = [];
    this.queue = [];
    this.unshuffledQueue = [];
    this.history = [];
    this.currentTrack = null;
    this.isShuffle = false;
    this.repeatMode = 'off'; // 'off' | 'all' | 'one'
    
    // Web Audio API for Kinetic Visualizer
    this.audioCtx = null;
    this.analyser = null;
    this.source = null;
    this.canvas = document.getElementById('visualizerCanvas');
    this.ctx = this.canvas.getContext('2d');
    
    this.initDemoTracks();
    this.initDOM();
    this.initAudioEvents();
    this.initMediaSession();
    this.initServiceWorker();
    this.render();
  }

  initDemoTracks() {
    this.tracks = [
      {
        id: '1',
        title: 'Mockingbird',
        artist: 'Eminem',
        duration: '4:11',
        artwork: './icon-192.png',
        url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
        lyrics: [
          { time: 1.0, text: "Yeah, I know sometimes things may not make sense to you right now" },
          { time: 6.0, text: "Now hush, little baby, don't you cry" },
          { time: 10.0, text: "Everything's gonna be alright", roman: "Everything's gonna be alright" }
        ]
      },
      {
        id: '2',
        title: 'Kesariya',
        artist: 'Arijit Singh, Pritam',
        duration: '4:28',
        artwork: './icon-192.png',
        url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
        lyrics: [
          { time: 2.0, text: "केसरिया तेरा इश्क़ है पिया", roman: "Kesariya tera ishq hai piya" },
          { time: 8.0, text: "रंग जाऊं जो मैं हाथ लगाऊं", roman: "Rang jaaun jo main haath lagaun" }
        ]
      },
      {
        id: '3',
        title: 'Better With You',
        artist: 'Ollie',
        duration: '3:17',
        artwork: './icon-192.png',
        url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3'
      },
      {
        id: '4',
        title: 'Darkside',
        artist: 'Alan Walker',
        duration: '3:31',
        artwork: './icon-192.png',
        url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3'
      }
    ];
  }

  initDOM() {
    // Navigation Tabs
    document.querySelectorAll('.tab-item').forEach(tab => {
      tab.addEventListener('click', () => {
        document.querySelectorAll('.tab-item').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.view-panel').forEach(p => p.classList.remove('active'));
        tab.classList.add('active');
        const viewId = tab.getAttribute('data-view');
        document.getElementById(viewId).classList.add('active');
      });
    });

    // File Input for iPhone Files App
    const fileInput = document.getElementById('audioFileInput');
    fileInput.addEventListener('change', (e) => this.handleLocalFiles(e.target.files));

    // Mini Player Click to open Full Player
    document.getElementById('mpInfo').addEventListener('click', () => this.openFullPlayer());
    document.getElementById('mpArtwork').addEventListener('click', () => this.openFullPlayer());
    document.getElementById('btnFpDismiss').addEventListener('click', () => this.closeFullPlayer());

    // Playback Buttons
    document.getElementById('btnMpPlayPause').addEventListener('click', (e) => {
      e.stopPropagation();
      this.togglePlayPause();
    });
    document.getElementById('btnFpPlayPause').addEventListener('click', () => this.togglePlayPause());
    document.getElementById('btnMpNext').addEventListener('click', (e) => {
      e.stopPropagation();
      this.next();
    });
    document.getElementById('btnFpNext').addEventListener('click', () => this.next());
    document.getElementById('btnFpPrev').addEventListener('click', () => this.prev());

    // Shuffle & Repeat
    document.getElementById('btnFpShuffle').addEventListener('click', () => this.toggleShuffle());
    document.getElementById('btnQueueShuffle').addEventListener('click', () => this.toggleShuffle());
    document.getElementById('btnQueueClear').addEventListener('click', () => this.clearQueue());

    // Scrubber
    const scrubber = document.getElementById('fpScrubber');
    scrubber.addEventListener('input', (e) => {
      if (this.audio.duration) {
        this.audio.currentTime = (e.target.value / 100) * this.audio.duration;
      }
    });

    // Lyrics Toggle in Full Player
    document.getElementById('btnFpLyrics').addEventListener('click', () => {
      const wrap = document.getElementById('fpLyricsWrap');
      const art = document.getElementById('fpArtworkWrap');
      wrap.classList.toggle('hidden');
      art.classList.toggle('hidden');
    });

    // Search Input
    document.getElementById('searchInput').addEventListener('input', (e) => {
      this.renderSongs(e.target.value);
    });
  }

  initAudioEvents() {
    this.audio.addEventListener('timeupdate', () => {
      if (!this.audio.duration) return;
      const pct = (this.audio.currentTime / this.audio.duration) * 100;
      document.getElementById('fpScrubber').value = pct;
      document.getElementById('fpCurrentTime').textContent = this.formatTime(this.audio.currentTime);
      document.getElementById('fpRemainingTime').textContent = '-' + this.formatTime(this.audio.duration - this.audio.currentTime);
      this.updateLyricsHighlight(this.audio.currentTime);
    });

    this.audio.addEventListener('ended', () => {
      this.next();
    });

    this.audio.addEventListener('play', () => this.updatePlayIcons(true));
    this.audio.addEventListener('pause', () => this.updatePlayIcons(false));
  }

  initMediaSession() {
    if ('mediaSession' in navigator) {
      navigator.mediaSession.setActionHandler('play', () => this.play());
      navigator.mediaSession.setActionHandler('pause', () => this.pause());
      navigator.mediaSession.setActionHandler('previoustrack', () => this.prev());
      navigator.mediaSession.setActionHandler('nexttrack', () => this.next());
      navigator.mediaSession.setActionHandler('seekto', (details) => {
        if (details.seekTime && this.audio.duration) {
          this.audio.currentTime = details.seekTime;
        }
      });
    }
  }

  updateMediaSession() {
    if (!('mediaSession' in navigator) || !this.currentTrack) return;
    navigator.mediaSession.metadata = new MediaMetadata({
      title: this.currentTrack.title,
      artist: this.currentTrack.artist,
      album: 'Lumo Player',
      artwork: [
        { src: this.currentTrack.artwork, sizes: '192x192', type: 'image/png' },
        { src: this.currentTrack.artwork, sizes: '512x512', type: 'image/png' }
      ]
    });
  }

  initWebAudio() {
    if (this.audioCtx) return;
    try {
      const AudioContext = window.AudioContext || window.webkitAudioContext;
      this.audioCtx = new AudioContext();
      this.analyser = this.audioCtx.createAnalyser();
      this.analyser.fftSize = 64;
      this.source = this.audioCtx.createMediaElementSource(this.audio);
      this.source.connect(this.analyser);
      this.analyser.connect(this.audioCtx.destination);
      this.drawVisualizer();
    } catch (e) {
      console.warn("Web Audio not supported or blocked", e);
    }
  }

  drawVisualizer() {
    requestAnimationFrame(() => this.drawVisualizer());
    if (!this.analyser) return;

    const bufferLength = this.analyser.frequencyBinCount;
    const dataArray = new Uint8Array(bufferLength);
    this.analyser.getByteFrequencyData(dataArray);

    const width = this.canvas.width;
    const height = this.canvas.height;
    this.ctx.clearRect(0, 0, width, height);

    const barWidth = (width / bufferLength) * 2;
    let x = 0;

    for (let i = 0; i < bufferLength; i++) {
      const barHeight = (dataArray[i] / 255) * height;
      const gradient = this.ctx.createLinearGradient(0, height, 0, 0);
      gradient.addColorStop(0, '#FF3D9A');
      gradient.addColorStop(1, '#FFC857');

      this.ctx.fillStyle = gradient;
      this.ctx.fillRect(x, height - barHeight, barWidth - 3, barHeight);
      x += barWidth;
    }
  }

  playTrack(track, list, index) {
    this.initWebAudio();
    if (this.audioCtx && this.audioCtx.state === 'suspended') {
      this.audioCtx.resume();
    }

    this.currentTrack = track;
    this.audio.src = track.url;
    this.audio.play();

    // Populate Queue
    if (list && index !== undefined) {
      this.history = list.slice(0, index);
      const upcoming = list.slice(index + 1);
      this.unshuffledQueue = [...upcoming];
      this.queue = this.isShuffle ? [...upcoming].sort(() => Math.random() - 0.5) : [...upcoming];
    }

    this.updateMediaSession();
    this.render();
  }

  togglePlayPause() {
    this.initWebAudio();
    if (this.audio.paused) {
      this.play();
    } else {
      this.pause();
    }
  }

  play() {
    if (this.currentTrack) {
      this.audio.play();
    } else if (this.tracks.length > 0) {
      this.playTrack(this.tracks[0], this.tracks, 0);
    }
  }

  pause() {
    this.audio.pause();
  }

  next() {
    if (this.queue.length > 0) {
      this.history.push(this.currentTrack);
      const next = this.queue.shift();
      const idx = this.unshuffledQueue.findIndex(t => t.id === next.id);
      if (idx !== -1) this.unshuffledQueue.splice(idx, 1);
      this.playTrack(next);
    } else if (this.repeatMode === 'all' && this.history.length > 0) {
      const all = [...this.history, this.currentTrack];
      this.history = [];
      this.playTrack(all[0], all, 0);
    } else {
      this.pause();
    }
    this.render();
  }

  prev() {
    if (this.audio.currentTime > 3.0) {
      this.audio.currentTime = 0;
      return;
    }
    if (this.history.length > 0) {
      const prev = this.history.pop();
      if (this.currentTrack) {
        this.queue.unshift(this.currentTrack);
        this.unshuffledQueue.unshift(this.currentTrack);
      }
      this.playTrack(prev);
    } else {
      this.audio.currentTime = 0;
    }
    this.render();
  }

  toggleShuffle() {
    this.isShuffle = !this.isShuffle;
    if (this.isShuffle) {
      this.queue = [...this.queue].sort(() => Math.random() - 0.5);
    } else {
      const activeIds = new Set(this.queue.map(t => t.id));
      this.queue = this.unshuffledQueue.filter(t => activeIds.has(t.id));
    }
    this.render();
  }

  clearQueue() {
    this.queue = [];
    this.unshuffledQueue = [];
    this.render();
  }

  handleLocalFiles(files) {
    Array.from(files).forEach((file, i) => {
      const url = URL.createObjectURL(file);
      const title = file.name.replace(/\.[^/.]+$/, "");
      const track = {
        id: 'local-' + Date.now() + '-' + i,
        title: title,
        artist: 'Local File',
        duration: '--:--',
        artwork: './icon-192.png',
        url: url
      };
      this.tracks.push(track);
    });
    this.render();
  }

  // MARK: - Reordering Logic (Drag & Drop)
  setupQueueDragAndDrop() {
    const list = document.getElementById('queueList');
    let draggedItem = null;

    list.querySelectorAll('.queue-row').forEach(row => {
      // Desktop drag
      row.addEventListener('dragstart', (e) => {
        draggedItem = row;
        row.classList.add('dragging');
        e.dataTransfer.effectAllowed = 'move';
      });

      row.addEventListener('dragend', () => {
        row.classList.remove('dragging');
        this.syncQueueFromDOM();
      });

      row.addEventListener('dragover', (e) => {
        e.preventDefault();
        const bounding = row.getBoundingClientRect();
        const offset = e.clientY - bounding.top;
        if (offset > bounding.height / 2) {
          row.after(draggedItem);
        } else {
          row.before(draggedItem);
        }
      });

      // Mobile Touch Drag Support
      let touchStartY = 0;
      row.addEventListener('touchstart', (e) => {
        draggedItem = row;
        touchStartY = e.touches[0].clientY;
      }, { passive: true });

      row.addEventListener('touchmove', (e) => {
        if (!draggedItem) return;
        const currentY = e.touches[0].clientY;
        const elementBelow = document.elementFromPoint(e.touches[0].clientX, currentY);
        const targetRow = elementBelow?.closest('.queue-row');
        if (targetRow && targetRow !== draggedItem) {
          const bounding = targetRow.getBoundingClientRect();
          if (currentY > bounding.top + bounding.height / 2) {
            targetRow.after(draggedItem);
          } else {
            targetRow.before(draggedItem);
          }
        }
      }, { passive: true });

      row.addEventListener('touchend', () => {
        if (draggedItem) {
          draggedItem = null;
          this.syncQueueFromDOM();
        }
      });
    });
  }

  syncQueueFromDOM() {
    const list = document.getElementById('queueList');
    const newQueue = [];
    list.querySelectorAll('.queue-row').forEach(row => {
      const id = row.getAttribute('data-id');
      const track = this.queue.find(t => t.id === id);
      if (track) newQueue.push(track);
    });
    this.queue = newQueue;
    if (!this.isShuffle) {
      this.unshuffledQueue = [...this.queue];
    }
    this.renderQueue();
  }

  // MARK: - Rendering
  render() {
    this.renderSongs();
    this.renderMiniPlayer();
    this.renderFullPlayer();
    this.renderQueue();
    this.renderVisualizerInfo();
  }

  renderSongs(filter = '') {
    const list = document.getElementById('songList');
    list.innerHTML = '';
    const filtered = this.tracks.filter(t => 
      t.title.toLowerCase().includes(filter.toLowerCase()) || 
      t.artist.toLowerCase().includes(filter.toLowerCase())
    );

    document.getElementById('trackCount').textContent = `${filtered.length} songs`;

    filtered.forEach((track, index) => {
      const isCurrent = this.currentTrack?.id === track.id;
      const row = document.createElement('div');
      row.className = `song-row ${isCurrent ? 'playing' : ''}`;
      row.innerHTML = `
        <img src="${track.artwork}" class="song-thumb" alt="Artwork">
        <div class="song-meta">
          <div class="song-title">${track.title}</div>
          <div class="song-artist">${track.artist}</div>
        </div>
        <div class="song-duration">${track.duration}</div>
      `;
      row.addEventListener('click', () => {
        this.playTrack(track, filtered, index);
      });
      list.appendChild(row);
    });
  }

  renderMiniPlayer() {
    const mp = document.getElementById('miniPlayer');
    if (!this.currentTrack) {
      mp.classList.add('hidden');
      return;
    }
    mp.classList.remove('hidden');
    document.getElementById('mpTitle').textContent = this.currentTrack.title;
    document.getElementById('mpArtist').textContent = this.currentTrack.artist;
    document.getElementById('mpArtwork').src = this.currentTrack.artwork;
  }

  renderFullPlayer() {
    if (!this.currentTrack) return;
    document.getElementById('fpTitle').textContent = this.currentTrack.title;
    document.getElementById('fpArtist').textContent = this.currentTrack.artist;
    document.getElementById('fpArtwork').src = this.currentTrack.artwork;
    
    // Lyrics
    const lyricsCont = document.getElementById('fpLyricsContainer');
    lyricsCont.innerHTML = '';
    if (this.currentTrack.lyrics && this.currentTrack.lyrics.length > 0) {
      this.currentTrack.lyrics.forEach(line => {
        const p = document.createElement('p');
        p.className = 'lyrics-line';
        p.setAttribute('data-time', line.time);
        p.innerHTML = `${line.text} ${line.roman ? `<span class="lyrics-romanized">${line.roman}</span>` : ''}`;
        lyricsCont.appendChild(p);
      });
    } else {
      lyricsCont.innerHTML = '<p class="no-lyrics">No synchronized lyrics available for this track.</p>';
    }
  }

  renderQueue() {
    const qBadge = document.getElementById('queueBadge');
    const tabBadge = document.getElementById('tabQueueBadge');
    qBadge.textContent = `${this.queue.length} upcoming`;
    tabBadge.textContent = this.queue.length;

    // Shuffle buttons
    document.getElementById('btnQueueShuffle').classList.toggle('active', this.isShuffle);
    document.getElementById('btnFpShuffle').style.color = this.isShuffle ? '#FF3D9A' : 'rgba(255,255,255,0.65)';

    // Now Playing card in queue
    if (this.currentTrack) {
      document.getElementById('qnpTitle').textContent = this.currentTrack.title;
      document.getElementById('qnpArtist').textContent = this.currentTrack.artist;
      document.getElementById('qnpArtwork').src = this.currentTrack.artwork;
      document.querySelector('.queue-now-playing-wrap').style.display = 'block';
    } else {
      document.querySelector('.queue-now-playing-wrap').style.display = 'none';
    }

    // Up Next Rows
    const list = document.getElementById('queueList');
    list.innerHTML = '';

    if (this.queue.length === 0) {
      list.innerHTML = '<p style="text-align:center; color:rgba(255,255,255,0.4); font-size:13px; padding:24px;">Queue is empty. Tap any song to play next.</p>';
      return;
    }

    this.queue.forEach((track, i) => {
      const row = document.createElement('div');
      row.className = 'queue-row';
      row.setAttribute('draggable', 'true');
      row.setAttribute('data-id', track.id);
      row.innerHTML = `
        <span class="drag-handle">☰</span>
        <span class="queue-num">${i + 1}</span>
        <div class="queue-meta">
          <div class="queue-title">${track.title}</div>
          <div class="queue-artist">${track.artist}</div>
        </div>
        <button class="btn-remove-queue" title="Remove">✕</button>
      `;

      row.querySelector('.queue-meta').addEventListener('click', () => {
        this.history.push(this.currentTrack);
        this.queue.splice(i, 1);
        this.playTrack(track);
      });

      row.querySelector('.btn-remove-queue').addEventListener('click', (e) => {
        e.stopPropagation();
        this.queue.splice(i, 1);
        this.unshuffledQueue = this.unshuffledQueue.filter(t => t.id !== track.id);
        this.renderQueue();
      });

      list.appendChild(row);
    });

    this.setupQueueDragAndDrop();
  }

  renderVisualizerInfo() {
    if (this.currentTrack) {
      document.getElementById('visTitle').textContent = this.currentTrack.title;
      document.getElementById('visArtist').textContent = this.currentTrack.artist;
      document.getElementById('visArtwork').src = this.currentTrack.artwork;
    }
  }

  updatePlayIcons(isPlaying) {
    const playSvg = '<polygon points="5 3 19 12 5 21 5 3"/>';
    const pauseSvg = '<rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/>';
    document.getElementById('mpPlayIcon').innerHTML = isPlaying ? pauseSvg : playSvg;
    document.getElementById('fpPlayIcon').innerHTML = isPlaying ? pauseSvg : playSvg;
  }

  updateLyricsHighlight(currentTime) {
    const lines = document.querySelectorAll('.lyrics-line');
    let activeLine = null;
    lines.forEach(l => {
      const t = parseFloat(l.getAttribute('data-time'));
      if (currentTime >= t) {
        activeLine = l;
      }
      l.classList.remove('active');
    });

    if (activeLine) {
      activeLine.classList.add('active');
      activeLine.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }

  openFullPlayer() {
    document.getElementById('fullPlayer').classList.remove('hidden');
  }

  closeFullPlayer() {
    document.getElementById('fullPlayer').classList.add('hidden');
  }

  formatTime(secs) {
    if (isNaN(secs)) return '0:00';
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60);
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  }

  initServiceWorker() {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('./sw.js').catch(err => console.log('SW failed', err));
    }
  }
}

document.addEventListener('DOMContentLoaded', () => {
  window.lumoPlayer = new LumoPlayer();
});
