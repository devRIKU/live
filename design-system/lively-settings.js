/* ═══════════════════════════════════════════════════════════════════════════
   LIVELY · lively-settings.js
   ---------------------------------------------------------------------------
   The account menu and the settings dialog, shared by the app
   ("Chat UI v3.html") and the milestone mockups (openall-mockups/).

   One implementation, two consumers. The mockups are the same product, so
   the settings surface must be the same product too.

   Usage:
     LivelySettings.init({
       accountBtn, accountMenu, settingsItem, shortcutsItem, resetItem,
       onPrefs(prefs) {},        // called whenever a preference changes
       onClearAll() {},          // called when the user confirms a wipe
       onReset() {}              // called when the user confirms a reset
     });

   Preferences live in localStorage under "lively.prefs" so a choice survives
   a reload — which is the whole point of a settings panel.
   ═══════════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  const KEY = 'lively.prefs';
  const DEFAULTS = {
    theme: 'system',        // system | light | dark
    enterToSend: true,
    showEffort: true,
    reduceMotion: false,
    name: 'Lively Franklin',
    instructions: '',
    improve: false
  };

  let prefs = Object.assign({}, DEFAULTS, load());
  let opts = {};
  let settingsEl = null;

  function load() { try { return JSON.parse(localStorage.getItem(KEY)) || {}; } catch (e) { return {}; } }
  function save() { try { localStorage.setItem(KEY, JSON.stringify(prefs)); } catch (e) {} }

  function initials(name) {
    return (name || '?').trim().split(/\s+/).slice(0, 2).map(w => w[0]).join('').toUpperCase() || '?';
  }

  /* ── Apply ─────────────────────────────────────────────────────────────── */
  function apply() {
    const html = document.documentElement;
    if (prefs.theme === 'system') delete html.dataset.theme;
    else html.dataset.theme = String(prefs.theme).toLowerCase();
    if (prefs.reduceMotion) html.dataset.reduceMotion = 'true';
    else delete html.dataset.reduceMotion;

    const name = document.getElementById('acctName');
    const avatar = document.getElementById('acctAvatar');
    if (name) name.textContent = prefs.name || 'Guest';
    if (avatar) avatar.textContent = initials(prefs.name);

    if (opts.onPrefs) opts.onPrefs(prefs);
  }

  /* ── Toast ─────────────────────────────────────────────────────────────── */
  function toast(msg) {
    const t = document.createElement('div');
    t.className = 'toast';
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(() => { t.dataset.leaving = 'true'; setTimeout(() => t.remove(), 200); }, 2200);
  }

  /* ── Icons ─────────────────────────────────────────────────────────────── */
  const ICON = {
    gear: '<circle cx="12" cy="12" r="3.2"/><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1A1.6 1.6 0 0 0 9 19.4a1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1A1.6 1.6 0 0 0 4.6 9a1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H9a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1Z"/>',
    user: '<circle cx="12" cy="8" r="3.6"/><path d="M4.8 20a7.2 7.2 0 0 1 14.4 0"/>',
    shield: '<path d="M12 3.5 5 6v6c0 4 3 7 7 8.5 4-1.5 7-4.5 7-8.5V6z"/>',
    keys: '<rect x="3" y="6" width="18" height="12" rx="2.6"/><path d="M7 10h.01M11 10h.01M15 10h.01M8 14h8"/>',
    info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8.2v.1"/>'
  };

  const TABS = [
    { id: 'general', label: 'General', icon: 'gear' },
    { id: 'providers', label: 'Providers & Keys', icon: 'shield' },
    { id: 'personal', label: 'Personalization', icon: 'user' },
    { id: 'data', label: 'Data controls', icon: 'shield' },
    { id: 'shortcuts', label: 'Shortcuts', icon: 'keys' },
    { id: 'about', label: 'About', icon: 'info' }
  ];

  const SHORTCUTS = [
    ['Enter', 'Send the message'],
    ['Shift + Enter', 'New line'],
    ['Ctrl / ⌘ + K', 'Focus the composer'],
    ['/', 'Focus the composer'],
    ['Esc', 'Close a menu or panel'],
    ['Ctrl / ⌘ + Shift + O', 'Toggle the theme']
  ];

  /* ── Settings panel ────────────────────────────────────────────────────── */
  function build() {
    if (settingsEl) return settingsEl;

    const row = (title, note, control) =>
      '<div class="set-row"><div class="set-row-text"><div class="set-row-title">' + title + '</div>' +
      (note ? '<div class="set-row-note">' + note + '</div>' : '') + '</div>' +
      '<div class="set-control">' + control + '</div></div>';

    const seg = (id, optsList, current) =>
      '<div class="seg" role="radiogroup" aria-label="' + id + '" data-seg="' + id + '">' +
      optsList.map(o => '<button class="seg-opt" role="radio" data-val="' + o + '" aria-checked="' +
        (o === current) + '">' + o + '</button>').join('') + '</div>';

    const sw = (id, on) =>
      '<button class="switch" role="switch" data-switch="' + id + '" aria-checked="' + on + '" aria-label="Toggle ' + id + '"></button>';

    const el = document.createElement('div');
    el.className = 'settings';
    el.id = 'settings';
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-modal', 'true');
    el.setAttribute('aria-labelledby', 'settingsTitle');
    el.innerHTML =
      '<div class="settings-panel">' +
        '<div class="settings-head">' +
          '<span class="settings-title" id="settingsTitle">Settings</span>' +
          '<button class="act" id="settingsClose" title="Close" aria-label="Close settings">' +
            '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="m6 6 12 12M18 6 6 18"/></svg>' +
          '</button>' +
        '</div>' +
        '<nav class="settings-nav" role="tablist" aria-label="Settings sections">' +
          '<div class="ms-search" style="margin:0 0 var(--s-2)">' +
            '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m16.5 16.5 4 4"/></svg>' +
            '<input type="search" placeholder="Search settings" aria-label="Search settings" id="settingsSearch" />' +
          '</div>' +
          TABS.map((t, i) => '<button class="settings-nav-item" role="tab" data-tab="' + t.id +
            '" aria-current="' + (i === 0) + '"><span class="n-ico"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
            ICON[t.icon] + '</svg></span>' + t.label + '</button>').join('') +
        '</nav>' +
        '<div class="settings-main">' +

          '<section class="settings-section" data-panel="general">' +
            '<h3 class="settings-h">Appearance</h3>' +
            row('Theme', 'System follows your device. Light and Dark override it.', seg('theme', ['System', 'Light', 'Dark'], prefs.theme)) +
            row('Reduce motion', 'Removes travel from every animation. The streaming caret stays visible.', sw('reduceMotion', prefs.reduceMotion)) +
            '<h3 class="settings-h" style="margin-top:var(--s-5)">Composer</h3>' +
            row('Press Enter to send', 'When off, use Ctrl / ⌘ + Enter to send.', sw('enterToSend', prefs.enterToSend)) +
            row('Show reasoning effort', 'Hides the effort control in the composer.', sw('showEffort', prefs.showEffort)) +
          '</section>' +

          '<section class="settings-section" data-panel="providers" hidden>' +
            '<h3 class="settings-h">Providers & Keys</h3>' +
            '<div class="set-row-note" style="margin-bottom:var(--s-3)">' +
              'Keys are saved to the backend proxy and local storage. Upstream requests are authenticated automatically.' +
            '</div>' +
            [
              { id: 'groq', name: 'Groq', env: 'GROQ_API_KEY', desc: 'Ultra-fast inference (Llama 3.3 70B, Llama 3.1 8B)' },
              { id: 'openrouter', name: 'OpenRouter', env: 'OPENROUTER_API_KEY', desc: 'Claude Sonnet 4, GPT-4.1, Gemini 2.5 Pro' },
              { id: 'google', name: 'Google AI Studio', env: 'GOOGLE_AI_KEY', desc: 'Gemini 2.5 Flash & Pro (1M context)' },
              { id: 'mistral', name: 'Mistral AI', env: 'MISTRAL_API_KEY', desc: 'Mistral Large & Pixtral' },
              { id: 'ollama', name: 'Ollama (Local)', env: 'OLLAMA_HOST', desc: 'Local private models (default http://localhost:11434)' }
            ].map(p => {
              const customKeys = JSON.parse(localStorage.getItem('lively.provider_keys') || '{}');
              const hasKey = !!customKeys[p.id];
              return '<div class="set-row">' +
                '<div class="set-row-text" style="flex:1">' +
                  '<div class="set-row-title">' + p.name + '</div>' +
                  '<div class="set-row-note">' + p.desc + '</div>' +
                '</div>' +
                '<div class="set-control" style="display:flex;gap:var(--s-2);align-items:center">' +
                  '<input type="password" class="set-input" data-provider-key="' + p.id + '" style="width:160px" placeholder="' + (hasKey ? '••••••••' : 'paste key') + '" />' +
                  '<button class="act" data-save-provider="' + p.id + '" style="padding:4px 10px;font-size:12px;border:1px solid var(--border-subtle);border-radius:var(--r-fixed-sm);">Save</button>' +
                '</div>' +
              '</div>';
            }).join('') +
            '<div class="set-row" style="margin-top:var(--s-3);background:var(--fill-1);padding:var(--s-3);border-radius:var(--r-fixed-md);">' +
              '<div class="set-row-text">' +
                '<div class="set-row-title">Lively Prototype Engine</div>' +
                '<div class="set-row-note">Built-in zero-config streaming engine. Always active as an offline fallback.</div>' +
              '</div>' +
              '<span class="ms-badge" data-tone="ok">Active</span>' +
            '</div>' +
          '</section>' +

          '<section class="settings-section" data-panel="personal" hidden>' +
            '<h3 class="settings-h">Identity</h3>' +
            '<div class="set-row"><div class="set-row-text" style="flex:1">' +
              '<div class="set-row-title">Display name</div>' +
              '<div class="set-row-note">Shown next to your conversations.</div></div>' +
              '<div class="set-control" style="width:220px"><input class="set-input" id="prefName" value="' +
                (prefs.name || '').replace(/"/g, '&quot;') + '" aria-label="Display name" /></div></div>' +
            '<h3 class="settings-h" style="margin-top:var(--s-5)">Custom instructions</h3>' +
            '<div class="set-row"><div class="set-row-text" style="flex:1">' +
              '<div class="set-row-note" style="margin:0 0 var(--s-2)">Added to every conversation you start. Saved on this device.</div>' +
              '<textarea class="set-textarea" id="prefInstructions" placeholder="e.g. Answer in British English, keep replies under 200 words, cite sources.">' +
                (prefs.instructions || '').replace(/</g, '&lt;') + '</textarea></div></div>' +
            '<div style="display:flex;justify-content:flex-end;margin-top:var(--s-3)">' +
              '<button class="btn" data-tone="primary" id="prefSave">Save</button></div>' +
          '</section>' +

          '<section class="settings-section" data-panel="data" hidden>' +
            '<h3 class="settings-h">Controls</h3>' +
            row('Improve the model for everyone', 'Allow your conversations to be used to improve the model.', sw('improve', prefs.improve)) +
            row('Clear all conversations', 'Removes every thread on this device. This cannot be undone.', '<button class="btn" data-tone="danger" id="clearAll">Clear all</button>') +
          '</section>' +

          '<section class="settings-section" data-panel="shortcuts" hidden>' +
            '<h3 class="settings-h">Keyboard</h3>' +
            SHORTCUTS.map(s => '<div class="shortcut"><span class="sc-key">' + s[0] +
              '</span><span class="sc-desc">' + s[1] + '</span></div>').join('') +
          '</section>' +

          '<section class="settings-section" data-panel="about" hidden>' +
            '<h3 class="settings-h">About</h3>' +
            row('Lively', 'A local-first AI workstation prototype.', '<span class="ms-badge">v1.0.0</span>') +
            row('Design system', 'Apple HIG structure, Sarvam flow spectrum, Mistral pixel motif.', '<span class="ms-badge">Lively DS</span>') +
            row('Motion', 'One authored moment. Everything else supports it.', '<span class="ms-badge">5 jobs</span>') +
          '</section>' +

        '</div>' +
      '</div>';

    document.body.appendChild(el);
    settingsEl = el;
    wire(el);
    return el;
  }

  function wire(el) {
    const searchInput = el.querySelector('#settingsSearch');
    if (searchInput) {
      searchInput.addEventListener('input', () => {
        const q = searchInput.value.trim().toLowerCase();
        el.querySelectorAll('.settings-nav-item').forEach(btn => {
          const label = btn.textContent.trim().toLowerCase();
          btn.hidden = q !== '' && !label.includes(q);
        });
        // if the active tab is hidden, switch to the first visible
        const active = el.querySelector('.settings-nav-item[aria-current="true"]');
        if (active && active.hidden) {
          const first = el.querySelector('.settings-nav-item:not([hidden])');
          if (first) first.click();
        }
      });
    }

    el.addEventListener('click', (e) => {
      if (e.target === el) { closeSettings(); return; }              // the scrim

      const nav = e.target.closest('[data-tab]');
      if (nav) {
        el.querySelectorAll('[data-tab]').forEach(t => t.setAttribute('aria-current', String(t === nav)));
        el.querySelectorAll('[data-panel]').forEach(p => p.hidden = p.dataset.panel !== nav.dataset.tab);
        return;
      }

      const segBtn = e.target.closest('.seg-opt');
      if (segBtn) {
        const group = segBtn.closest('.seg');
        group.querySelectorAll('.seg-opt').forEach(o => o.setAttribute('aria-checked', String(o === segBtn)));
        prefs[group.dataset.seg] = segBtn.dataset.val;
        save(); apply();
        toast(group.dataset.seg === 'theme'
          ? 'Theme set to ' + segBtn.dataset.val.toLowerCase()
          : 'Updated');
        return;
      }

      const swBtn = e.target.closest('[data-switch]');
      if (swBtn) {
        const on = swBtn.getAttribute('aria-checked') !== 'true';
        swBtn.setAttribute('aria-checked', String(on));
        prefs[swBtn.dataset.switch] = on;
        save(); apply();
        toast(swBtn.dataset.switch === 'reduceMotion'
          ? (on ? 'Motion reduced' : 'Motion restored')
          : (on ? 'Enabled' : 'Disabled'));
        return;
      }

      if (e.target.closest('#settingsClose')) { closeSettings(); return; }

      if (e.target.closest('#prefSave')) {
        const name = document.getElementById('prefName');
        const inst = document.getElementById('prefInstructions');
        prefs.name = (name && name.value.trim()) || 'Guest';
        prefs.instructions = inst ? inst.value : '';
        save(); apply();
        toast('Preferences saved');
        return;
      }

      const saveProvBtn = e.target.closest('[data-save-provider]');
      if (saveProvBtn) {
        const pid = saveProvBtn.dataset.saveProvider;
        const inp = el.querySelector('[data-provider-key="' + pid + '"]');
        const val = inp ? inp.value.trim() : '';
        const keys = JSON.parse(localStorage.getItem('lively.provider_keys') || '{}');
        if (val) {
          keys[pid] = val;
        } else {
          delete keys[pid];
        }
        localStorage.setItem('lively.provider_keys', JSON.stringify(keys));
        window.dispatchEvent(new CustomEvent('lively:keys-updated', { detail: { providerId: pid, hasKey: !!val } }));
        fetch('/api/providers/keys', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ providerId: pid, key: val })
        }).catch(() => {});
        toast(val ? 'Key saved for ' + pid : 'Key removed for ' + pid);
        if (inp) inp.value = '';
        return;
      }

      if (e.target.closest('#clearAll')) {
        const b = e.target.closest('#clearAll');
        if (b.dataset.armed !== 'true') {
          b.dataset.armed = 'true';
          b.textContent = 'Tap again to confirm';
          setTimeout(() => { b.dataset.armed = 'false'; b.textContent = 'Clear all'; }, 4000);
          return;
        }
        b.dataset.armed = 'false';
        b.textContent = 'Clear all';
        if (opts.onClearAll) opts.onClearAll();
        closeSettings();
        toast('All conversations cleared');
      }
    });
  }

  function openSettings(tab) {
    build();
    if (tab) {
      const btn = settingsEl.querySelector('[data-tab="' + tab + '"]');
      if (btn) btn.click();
    }
    settingsEl.hidden = false;
    const focusTarget = settingsEl.querySelector('#settingsClose');
    if (focusTarget) focusTarget.focus();
  }

  function closeSettings() { if (settingsEl) settingsEl.hidden = true; }

  /* ── Account menu ──────────────────────────────────────────────────────── */
  function init(o) {
    opts = o || {};
    const accountBtn = opts.accountBtn || document.getElementById('acctBtn');
    const accountMenu = opts.accountMenu || document.getElementById('acctMenu');
    if (!accountBtn || !accountMenu) return;

    function closeMenu() {
      accountMenu.dataset.open = 'false';
      accountBtn.setAttribute('aria-expanded', 'false');
    }
    opts.closeMenu = closeMenu;

    accountBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      const open = accountMenu.dataset.open === 'true';
      if (opts.closePopovers) opts.closePopovers();
      accountMenu.dataset.open = String(!open);
      accountBtn.setAttribute('aria-expanded', String(!open));
    });

    document.addEventListener('click', (e) => {
      if (!e.target.closest('#acctMenu') && !e.target.closest('#acctBtn')) closeMenu();
    });

    const settingsItem = opts.settingsItem || document.getElementById('miSettings');
    const shortcutsItem = opts.shortcutsItem || document.getElementById('miShortcuts');
    const resetItem = opts.resetItem || document.getElementById('miReset');

    if (settingsItem) settingsItem.addEventListener('click', () => { closeMenu(); openSettings('general'); });
    if (shortcutsItem) shortcutsItem.addEventListener('click', () => { closeMenu(); openSettings('shortcuts'); });
    if (resetItem) resetItem.addEventListener('click', () => {
      closeMenu();
      if (resetItem.dataset.armed !== 'true') {
        resetItem.dataset.armed = 'true';
        const label = resetItem.querySelector('.m-label');
        if (label) label.textContent = 'Tap again to reset everything';
        setTimeout(() => {
          resetItem.dataset.armed = 'false';
          const l = resetItem.querySelector('.m-label');
          if (l) l.textContent = 'Reset demo';
        }, 4000);
        return;
      }
      resetItem.dataset.armed = 'false';
      const l = resetItem.querySelector('.m-label');
      if (l) l.textContent = 'Reset demo';
      try { localStorage.removeItem(KEY); } catch (e) {}
      Object.assign(prefs, DEFAULTS);
      if (opts.onReset) opts.onReset();
      apply();
      toast('Demo reset');
    });

    document.addEventListener('keydown', (e) => {
      if (e.key !== 'Escape') return;
      if (settingsEl && !settingsEl.hidden) { closeSettings(); return; }
      closeMenu();
    });

    apply();
  }

  window.LivelySettings = {
    init: init,
    toast: toast,
    openSettings: openSettings,
    closeSettings: closeSettings,
    apply: apply,
    get prefs() { return prefs; }
  };
})();
