// Injected into the live site by the iOS app. The website itself is never changed.
(() => {
  if (window.__squishApp) return;
  window.__squishApp = true;
  const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.squishSave;

  // App feel: no pinch zoom / zoom-on-focus, bigger touch targets, tighter top spacing.
  const vp = document.querySelector('meta[name=viewport]');
  if (vp) vp.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no';
  const style = document.createElement('style');
  style.textContent = `
    * { -webkit-tap-highlight-color: transparent; }
    html { -webkit-text-size-adjust: 100%; }
    body { -webkit-user-select: none; user-select: none; -webkit-touch-callout: none; }
    main { padding-top: 24px; padding-bottom: 40px; }
    .drop { min-height: 200px; align-content: center; }
    .drop:active { background: var(--soft); }
    select, button:not(.link) { min-height: 44px; }
    #controls button.main { flex: 1; white-space: nowrap; }
  `;
  document.head.append(style);

  const $ = (id) => document.getElementById(id);
  const drop = $('drop');
  if (drop && drop.children.length >= 2) {
    drop.children[0].textContent = 'Tap to choose a video';
    drop.children[1].textContent = 'From Photos, Files, or the camera';
  }
  const footer = document.querySelector('footer');
  if (footer) footer.textContent = 'Runs entirely on this device. Your video is never uploaded.';

  if (!bridge) return;

  // Rename the site's "Download (12 MB)" button to "Save to Photos (12 MB)".
  const dl = $('download');
  if (dl) {
    const relabel = () => {
      if (dl.textContent.startsWith('Download')) dl.textContent = dl.textContent.replace(/^Download/, 'Save to Photos');
    };
    new MutationObserver(relabel).observe(dl, { childList: true, characterData: true, subtree: true });
    relabel();
  }

  function setStatus(text, error = false) {
    const s = $('status');
    if (!s) return;
    s.textContent = text;
    s.classList.toggle('error', error);
  }

  function toBase64(blob) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result).split(',')[1] || '');
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(blob);
    });
  }

  let saving = false;
  async function save(url, name) {
    if (saving) return;
    saving = true;
    const label = dl ? dl.textContent : '';
    if (dl) dl.disabled = true;
    const progress = (t) => { if (dl) dl.textContent = t; };
    try {
      progress('Saving…');
      const blob = await (await fetch(url)).blob();
      await bridge.postMessage({ op: 'begin', name });
      const CHUNK = 3 * 1024 * 1024;
      for (let i = 0; i < blob.size; i += CHUNK) {
        await bridge.postMessage({ op: 'chunk', data: await toBase64(blob.slice(i, i + CHUNK)) });
        progress(`Saving… ${Math.min(99, Math.floor(((i + CHUNK) / blob.size) * 100))}%`);
      }
      const result = await bridge.postMessage({ op: 'end' });
      if (result === 'saved') setStatus('Saved to Photos.');
      else if (result === 'denied') setStatus('Squish isn’t allowed to add to Photos, so the share menu opened instead. You can allow it in Settings › Squish › Photos.', true);
      else setStatus('Photos can’t take this format, so the share menu opened instead. Use “Save to Files”.');
    } catch (err) {
      setStatus(`Couldn’t save: ${err && err.message ? err.message : err}`, true);
    } finally {
      saving = false;
      if (dl) { dl.disabled = false; dl.textContent = label; }
    }
  }

  // The site saves by clicking a temporary <a download href="blob:...">. Catch that and save natively.
  const nativeClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    if (this.hasAttribute('download') && this.href.startsWith('blob:')) {
      save(this.href, this.getAttribute('download') || 'squished.mp4');
      return;
    }
    return nativeClick.call(this);
  };
})();
