(function () {
  'use strict';
  // Uma única instância por documento, inclusive após reconexões do Shiny.
  if (window.wlvAnalytics) return;
  var TAB_NAMES = ['about', 'map', 'country', 'indicators', 'trade', 'download', 'publications'];
  var CAMPAIGNS = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term',
    'mtm_source', 'mtm_medium', 'mtm_campaign', 'mtm_content', 'mtm_keyword'];
  var DIMENSIONS = ['kind', 'format', 'method', 'country', 'partner', 'indicator', 'years', 'sector', 'release', 'filename'];
  var STORAGE_KEY = 'wlv_analytics_optout', HEARTBEAT_MS = 15000, IDLE_MS = 120000, MAX_QUEUE = 64;
  var config = {enabled: false}, tracker = null, loading = false, failed = false, queue = [];
  var optout = false, channel = null, foreignFocus = false, ended = false, initialized = false;
  var currentTab = '', previousUrl = '', pageCount = 0, pendingMs = 0, accruing = false;
  var lastTick = performance.now(), lastActivity = lastTick, lastPointer = -Infinity;
  var downloadSeen = new Set(), connectionInput = null;
  var entryParams = new URLSearchParams(window.location.search);
  var entryOrigin = entryParams.get('wlv_entry') === 'panel' ? 'panel' : '';
  var entryReferrer = '';
  try {
    var referring = new URL(document.referrer);
    if (/^https?:$/.test(referring.protocol)) entryReferrer = referring.origin + '/';
  } catch (_) { /* Referência ausente ou inválida é tráfego direto. */ }
  try { optout = window.localStorage.getItem(STORAGE_KEY) === 'true'; } catch (_) { /* Preferência em memória. */ }

  function browserSignal() {
    return navigator.globalPrivacyControl === true || [navigator.doNotTrack, window.doNotTrack, navigator.msDoNotTrack]
      .some(function (value) { return value === '1' || value === 'yes'; });
  }
  function allowed() { return config.enabled === true && !optout && !browserSignal() && !failed; }
  function eligible() {
    return allowed() && !!currentTab && !ended && !foreignFocus &&
      document.visibilityState === 'visible' && document.hasFocus();
  }
  function cleanCampaign(value) {
    return typeof value === 'string' && /^[\p{L}\p{N} .,_~-]{1,120}$/u.test(value) ? value : '';
  }
  function pageUrl(tab, withCampaign) {
    var url = new URL('/', window.location.origin);
    url.searchParams.set('tab', tab);
    if (withCampaign) CAMPAIGNS.forEach(function (key) {
      var value = cleanCampaign(entryParams.get(key));
      if (value) url.searchParams.set(key, value);
    });
    return url.href;
  }
  function readConfig() {
    try {
      var node = document.getElementById('wlv-analytics-config');
      var value = JSON.parse(node ? node.textContent : '{}');
      if (value.enabled !== true || !Number.isSafeInteger(value.site_id) || value.site_id < 1 || value.site_id > 1000000 ||
          value.tracker_url !== '/estatisticas/matomo.php' || value.script_url !== '/estatisticas/matomo.js') return;
      config = {enabled: true, site_id: value.site_id, tracker_url: value.tracker_url,
        script_url: value.script_url, dimensions: {}};
      DIMENSIONS.forEach(function (name) {
        var id = value.dimensions && value.dimensions[name];
        if (Number.isSafeInteger(id) && id > 0 && id <= 1000000) config.dimensions[name] = id;
      });
    } catch (_) { /* Configuração ausente ou inválida desativa somente as estatísticas. */ }
  }
  function updateInput(force) {
    var enabled = allowed() && !!tracker;
    if (!window.Shiny || typeof window.Shiny.setInputValue !== 'function') return;
    if (force || connectionInput !== enabled) {
      try {
        window.Shiny.setInputValue('wlv_analytics_enabled', enabled, {priority: 'event'});
        connectionInput = enabled;
      } catch (_) { /* O próximo evento de conexão sincroniza a preferência. */ }
    }
  }
  function updatePrivacy() {
    var status = browserSignal() ? 'browser' : optout ? 'optout' : !allowed() || !tracker ? 'unavailable' : 'enabled';
    document.querySelectorAll('[data-analytics-status]').forEach(function (node) {
      node.hidden = node.getAttribute('data-analytics-status') !== status;
    });
    document.querySelectorAll('[data-analytics-choice]').forEach(function (node) {
      node.hidden = node.getAttribute('data-analytics-choice') !== (optout ? 'enable' : 'disable');
    });
    var toggle = document.getElementById('wlv-privacy-toggle');
    if (toggle) toggle.disabled = browserSignal() || !config.enabled;
    updateInput(false);
  }
  function unavailable() {
    failed = true; loading = false; queue = []; pendingMs = 0; accruing = false;
    updatePrivacy();
  }
  function deliver(item) {
    if (!allowed() || !tracker) return;
    var installed = [];
    try {
      tracker.setCustomUrl(item.url);
      if (item.type === 'page') {
        tracker.setReferrerUrl(item.referrer);
        tracker.setDocumentTitle('WLVD / ' + item.tab);
        tracker.trackPageView();
      } else {
        DIMENSIONS.forEach(function (name) {
          var id = config.dimensions[name], value = item.metadata && item.metadata[name];
          if (id && value && typeof tracker.setCustomDimension === 'function') {
            tracker.setCustomDimension(id, value); installed.push(id);
          }
        });
        tracker.trackEvent(item.category, item.action, item.name, item.value);
      }
    } catch (_) { unavailable(); }
    finally {
      installed.forEach(function (id) {
        try { tracker.deleteCustomDimension(id); } catch (_) { /* Sem impacto na interface. */ }
      });
    }
  }
  function emit(item) {
    if (!allowed()) return;
    if (tracker) deliver(item);
    else if (queue.length < MAX_QUEUE) queue.push(item);
  }
  function loadTracker() {
    if (!allowed() || loading || tracker) return;
    loading = true;
    var script = document.createElement('script');
    script.async = true; script.src = config.script_url; script.id = 'wlv-matomo-script';
    var timeout = window.setTimeout(unavailable, 10000);
    script.onerror = function () { window.clearTimeout(timeout); unavailable(); };
    script.onload = function () {
      window.clearTimeout(timeout); loading = false;
      if (!allowed()) return;
      try {
        tracker = window.Matomo.getTracker(config.tracker_url, config.site_id);
        tracker.disableCookies();
        tracker.setDoNotTrack(true);
        if (typeof tracker.disableBrowserFeatureDetection === 'function') tracker.disableBrowserFeatureDetection();
        if (typeof tracker.disablePerformanceTracking === 'function') tracker.disablePerformanceTracking();
        if (typeof tracker.disableQueueRequest === 'function') tracker.disableQueueRequest();
        tracker.setRequestMethod('POST');
        // Eventos próprios medem tempo ativo; nenhum listener automático de links ou heartbeat paralelo.
        var waiting = queue; queue = [];
        waiting.forEach(deliver);
        updatePrivacy();
      } catch (_) { tracker = null; unavailable(); }
    };
    document.head.appendChild(script);
  }
  function account(now) {
    if (accruing) pendingMs += Math.max(0, Math.min(now, lastActivity + IDLE_MS) - lastTick);
    lastTick = now;
    accruing = eligible() && now < lastActivity + IDLE_MS;
  }
  function flush() {
    if (!currentTab || pendingMs < 1) return;
    var seconds = Math.round(pendingMs) / 1000;
    pendingMs = 0;
    if (seconds > 0) emit({type: 'event', category: 'Engagement', action: 'active_seconds',
      name: currentTab, value: seconds, url: pageUrl(currentTab, false)});
  }
  function selectTab() {
    var active = document.querySelector('#main_nav li.active > a[data-value]');
    var tab = active && active.dataset.value;
    if (TAB_NAMES.indexOf(tab) === -1 || tab === currentTab) return;
    var now = performance.now();
    account(now); flush(); currentTab = tab; lastActivity = now; accruing = eligible();
    if (!allowed()) return;
    var first = pageCount === 0, url = pageUrl(tab, first);
    emit({type: 'page', tab: tab, url: url, referrer: first ? entryReferrer : previousUrl});
    pageCount += 1; previousUrl = pageUrl(tab, false);
    if (first && entryOrigin) emit({type: 'event', category: 'Acquisition', action: 'entry_origin',
      name: entryOrigin, value: 1, url: previousUrl});
    if (first) ['source', 'medium'].forEach(function (key) {
      var value = cleanCampaign(entryParams.get('mtm_' + key)) || cleanCampaign(entryParams.get('utm_' + key));
      if (value) emit({type: 'event', category: 'Acquisition', action: 'campaign_' + key,
        name: value, value: 1, url: previousUrl});
    });
  }
  function activity(event) {
    var now = performance.now();
    if (event && event.type === 'pointermove' && now - lastPointer < 250) return;
    lastPointer = now; account(now); lastActivity = now;
    if (foreignFocus && document.hasFocus()) { foreignFocus = false; broadcast({type: 'focus'}); }
    accruing = eligible();
  }
  function broadcast(value) { try { if (channel) channel.postMessage(value); } catch (_) { /* Canal opcional. */ } }
  function setOptOut(value, persist) {
    if (typeof value !== 'boolean') return;
    if (value === optout) { updatePrivacy(); return; }
    optout = value;
    // Não descarrega intervalos pendentes ao desativar: a escolha já deve valer.
    queue = []; pendingMs = 0; lastTick = lastActivity = performance.now(); accruing = false;
    if (persist !== false) {
      try { window.localStorage.setItem(STORAGE_KEY, String(value)); } catch (_) { /* Preferência em memória. */ }
      broadcast({type: 'preference', optout: value});
    }
    if (allowed()) {
      currentTab = ''; selectTab(); loadTracker();
    }
    updatePrivacy();
  }
  function cleanDownload(payload) {
    if (!payload || typeof payload !== 'object' || Array.isArray(payload) ||
        !['requested', 'generated', 'failed'].includes(payload.status) ||
        typeof payload.event_id !== 'string' || !/^[A-Za-z0-9_.:-]{1,120}$/.test(payload.event_id)) return null;
    var result = {status: payload.status, event_id: payload.event_id, metadata: {}};
    DIMENSIONS.forEach(function (name) {
      var value = payload[name], max = name === 'filename' ? 180 : name === 'release' ? 128 : 255;
      if (typeof value !== 'string' || !value || value.length > max) return;
      var pattern = name === 'filename' ? /^[\p{L}\p{N}_. ()-]+$/u : name === 'years' ? /^[0-9,-]+$/ : /^[A-Za-z0-9_.,:+ -]+$/;
      if (pattern.test(value)) result.metadata[name] = value;
    });
    return result;
  }
  function onDownload(payload) {
    if (!allowed()) return;
    var item = cleanDownload(payload);
    if (!item) return;
    var key = item.event_id + ':' + item.status;
    if (downloadSeen.has(key)) return;
    downloadSeen.add(key);
    if (downloadSeen.size > 128) downloadSeen.delete(downloadSeen.values().next().value);
    emit({type: 'event', category: 'Download', action: item.status,
      name: item.metadata.filename || item.metadata.kind || 'download', value: 1,
      metadata: item.metadata, url: pageUrl(currentTab || 'download', false)});
  }
  function privacyDialog() {
    var dialog = document.getElementById('wlv-privacy-dialog');
    var openers = ['wlv-privacy-open', 'wlv-privacy-open-settings'].map(function (id) {
      return document.getElementById(id);
    }).filter(Boolean);
    var lastOpener = null;
    var close = document.getElementById('wlv-privacy-close'), toggle = document.getElementById('wlv-privacy-toggle');
    if (!dialog || !openers.length || !close || !toggle) return;
    function hide() {
      if (typeof dialog.close === 'function') dialog.close();
      else dialog.removeAttribute('open');
      var returnTo = lastOpener;
      if (returnTo && returnTo.id === 'wlv-privacy-open-settings') {
        returnTo = document.getElementById('settings_toggle');
      }
      if (returnTo && returnTo.getClientRects().length) returnTo.focus();
    }
    openers.forEach(function (open) {
      open.addEventListener('click', function () {
        lastOpener = open;
        var settings = open.closest('details');
        if (settings) settings.removeAttribute('open');
        updatePrivacy();
        if (typeof dialog.showModal === 'function') dialog.showModal();
        else { dialog.setAttribute('open', ''); dialog.setAttribute('role', 'dialog'); dialog.setAttribute('aria-modal', 'true'); }
        (toggle.disabled ? close : toggle).focus();
      });
    });
    close.addEventListener('click', hide);
    toggle.addEventListener('click', function () { setOptOut(!optout); });
    dialog.addEventListener('cancel', function (event) { event.preventDefault(); hide(); });
    dialog.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') { event.preventDefault(); hide(); return; }
      if (event.key !== 'Tab') return;
      var buttons = Array.from(dialog.querySelectorAll('button:not([disabled])'));
      var first = buttons[0], last = buttons[buttons.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    });
  }
  function initialize() {
    if (initialized) return;
    initialized = true; readConfig(); privacyDialog();
    try {
      if (window.BroadcastChannel) {
        channel = new window.BroadcastChannel('wlv-analytics');
        channel.onmessage = function (event) {
          var value = event.data;
          if (!value || typeof value !== 'object') return;
          if (value.type === 'preference' && typeof value.optout === 'boolean') setOptOut(value.optout, false);
          else if (value.type === 'focus') {
            account(performance.now()); flush(); foreignFocus = true; accruing = false;
          }
        };
      }
    } catch (_) { /* document.hasFocus continua evitando contagem de janelas sem foco. */ }
    if (window.jQuery) {
      window.jQuery(document).on('shown.bs.tab.wlvAnalytics', '#main_nav a[data-value]', selectTab);
      window.jQuery(document).on('shiny:connected.wlvAnalytics', function () { updateInput(true); });
    }
    if (window.Shiny && typeof window.Shiny.addCustomMessageHandler === 'function') {
      window.Shiny.addCustomMessageHandler('wlv-analytics-download', onDownload);
    }
    // wlv-panel.js seleciona URL/cookie no DOMContentLoaded antes deste listener.
    selectTab(); loadTracker(); updatePrivacy();
    ['pointerdown', 'pointermove', 'keydown', 'scroll', 'touchstart'].forEach(function (name) {
      document.addEventListener(name, activity, {passive: true, capture: true});
    });
    document.addEventListener('visibilitychange', function () {
      var now = performance.now(); account(now); flush();
      if (document.visibilityState === 'visible' && document.hasFocus()) activity();
      else accruing = false;
    });
    window.addEventListener('focus', function () {
      foreignFocus = false; activity(); broadcast({type: 'focus'});
    });
    window.addEventListener('blur', function () { account(performance.now()); flush(); accruing = false; });
    window.addEventListener('pagehide', function () { account(performance.now()); flush(); ended = true; accruing = false; });
    window.addEventListener('pageshow', function (event) {
      if (!event.persisted) return;
      ended = false; lastTick = lastActivity = performance.now(); accruing = eligible();
    });
    window.addEventListener('storage', function (event) {
      if (event.key === STORAGE_KEY) setOptOut(event.newValue === 'true', false);
    });
    window.setInterval(function () { account(performance.now()); flush(); updateInput(false); }, HEARTBEAT_MS);
    if (document.hasFocus()) broadcast({type: 'focus'});
  }
  window.wlvAnalytics = {
    onDownload: onDownload,
    setOptOut: function (value) { setOptOut(value); },
    status: function () { return {enabled: allowed() && !!tracker, optedOut: optout, browserSignal: browserSignal(), tab: currentTab}; }
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initialize);
  else initialize();
})();
