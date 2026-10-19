'use strict';
// Relógio e transporte controlados: verifica intervalos e privacidade sem gerar visitas reais.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../..');
const source = fs.readFileSync(path.join(root, 'www/wlv-analytics.js'), 'utf8');
const campaign = process.env.WLV_CAMPAIGN_ROOT;
if (!campaign || !path.resolve(campaign).startsWith(path.join(root, 'temp') + path.sep)) throw Error('Defina WLV_CAMPAIGN_ROOT dentro de temp/.');
const tests = [];
function test(name, run) { run(); tests.push({name, passed: true}); }
function target() {
  const listeners = new Map();
  return {listeners, addEventListener(name, callback) { if (!listeners.has(name)) listeners.set(name, []); listeners.get(name).push(callback); },
    dispatch(name, extra = {}) { for (const fn of listeners.get(name) || []) fn({type: name, ...extra}); }};
}
function make(options = {}) {
  let now = 0, seq = 0, active = options.tab || 'about', focused = options.focused !== false;
  const timers = new Map(), sent = [], commands = [], stored = new Map(Object.entries(options.storage || {}));
  const scripts = [], jquery = [], inputs = [], handlers = {};
  const elements = {};
  const config = options.config || {enabled: true, site_id: 2, tracker_url: '/estatisticas/matomo.php', script_url: '/estatisticas/matomo.js',
    dimensions: Object.fromEntries(['kind', 'format', 'method', 'country', 'partner', 'indicator', 'years', 'sector', 'release', 'filename'].map((key, i) => [key, i + 1]))};
  const document = Object.assign(target(), {
    readyState: 'complete', visibilityState: 'visible', referrer: options.referrer || '',
    hasFocus() { return focused; }, getElementById(id) { return id === 'wlv-analytics-config' ? {textContent: JSON.stringify(config)} : elements[id] || null; },
    querySelector(selector) { return selector === '#main_nav li.active > a[data-value]' ? {dataset: {value: active}} : null; },
    querySelectorAll() { return []; }, createElement() { return {}; }, head: {appendChild(node) { scripts.push(node); }}
  });
  if (options.ui) {
    for (const id of ['wlv-privacy-dialog', 'wlv-privacy-open', 'wlv-privacy-open-settings', 'wlv-privacy-close', 'wlv-privacy-toggle', 'wlv-settings', 'settings_toggle']) {
      elements[id] = Object.assign(target(), {id, attributes: {}, disabled: false,
        focus() { document.activeElement = this; },
        // Chromium pode conservar retângulos de layout dentro de details fechado.
        getClientRects() { return [{}]; },
        setAttribute(key, value) { this.attributes[key] = value; }, removeAttribute(key) { delete this.attributes[key]; },
        closest(selector) { return id === 'wlv-privacy-open-settings' && selector === 'details' ? elements['wlv-settings'] : null; }});
    }
    elements['wlv-privacy-dialog'].showModal = function () { this.attributes.open = ''; };
    elements['wlv-privacy-dialog'].close = function () { delete this.attributes.open; };
    elements['wlv-privacy-dialog'].querySelectorAll = () => [elements['wlv-privacy-toggle'], elements['wlv-privacy-close']].filter(node => !node.disabled);
  }
  Object.defineProperty(document, 'cookie', {get() { return ''; }, set() { throw Error('A integração não deve escrever cookies.'); }});
  const localStorage = {getItem(key) { if (options.blockStorage) throw Error('blocked'); return stored.get(key) || null; },
    setItem(key, value) { if (options.blockStorage) throw Error('blocked'); stored.set(key, value); }};
  const window = Object.assign(target(), {
    document, navigator: {doNotTrack: options.dnt || '', globalPrivacyControl: options.gpc || false},
    location: new URL(options.url || 'https://worldlabourvalues.org/'), localStorage,
    setTimeout(fn, delay) { const id = ++seq; timers.set(id, {at: now + delay, fn, repeat: 0}); return id; },
    clearTimeout(id) { timers.delete(id); }, setInterval(fn, delay) { const id = ++seq; timers.set(id, {at: now + delay, fn, repeat: delay}); return id; },
    jQuery() { return {on(name, selector, callback) { jquery.push({name, selector: typeof selector === 'string' ? selector : '', callback: callback || selector}); }}; },
    Shiny: {setInputValue(name, value) { inputs.push({name, value}); }, addCustomMessageHandler(name, fn) { handlers[name] = fn; }}
  });
  if (options.bus) window.BroadcastChannel = class {
    constructor(name) { this.name = name; options.bus.push(this); }
    postMessage(data) { for (const peer of options.bus) if (peer !== this && peer.name === this.name && peer.onmessage) peer.onmessage({data}); }
  };
  let dimensions = {}, url = '', referrer = '', title = '';
  const tracker = Object.fromEntries(['disableCookies', 'setDoNotTrack', 'disableBrowserFeatureDetection', 'disablePerformanceTracking', 'disableQueueRequest', 'setRequestMethod']
    .map(name => [name, (...args) => { commands.push({name, args}); }]));
  Object.assign(tracker, {
    setCustomUrl(value) { url = value; }, setReferrerUrl(value) { referrer = value; }, setDocumentTitle(value) { title = value; },
    setCustomDimension(id, value) { dimensions[id] = value; }, deleteCustomDimension(id) { delete dimensions[id]; },
    trackPageView() { sent.push({type: 'page', title, url, referrer, dimensions: {...dimensions}}); },
    trackEvent(category, action, name, value) { sent.push({type: 'event', category, action, name, value, url, dimensions: {...dimensions}}); }
  });
  window.Matomo = {getTracker(trackerUrl, siteId) { assert.equal(trackerUrl, '/estatisticas/matomo.php'); assert.equal(siteId, 2); return tracker; }};
  const context = vm.createContext({window, document, navigator: window.navigator, performance: {now: () => now}, URL, URLSearchParams});
  vm.runInContext(source, context);
  const instance = {
    window, document, scripts, sent, commands, stored, inputs, handlers, elements,
    ready() { scripts[scripts.length - 1].onload(); }, fail() { scripts[scripts.length - 1].onerror(); }, rerun() { vm.runInContext(source, context); },
    advance(ms) {
      const end = now + ms;
      while (true) {
        const next = [...timers.entries()].filter(([, timer]) => timer.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
        if (!next) break;
        now = next[1].at;
        if (next[1].repeat) next[1].at += next[1].repeat; else timers.delete(next[0]);
        next[1].fn();
      }
      now = end;
    },
    tab(value) { active = value; for (const handler of jquery) if (handler.name.startsWith('shown.bs.tab')) handler.callback({target: {dataset: {value}}}); },
    connect() { for (const handler of jquery) if (handler.name.startsWith('shiny:connected')) handler.callback(); },
    focus(value) { focused = value; window.dispatch(value ? 'focus' : 'blur'); },
    visible(value) { document.visibilityState = value ? 'visible' : 'hidden'; document.dispatch('visibilitychange'); },
    pages() { return sent.filter(item => item.type === 'page'); },
    seconds(tab) { return sent.filter(item => item.action === 'active_seconds' && (!tab || item.name === tab)).reduce((sum, item) => sum + item.value, 0); }
  };
  return instance;
}

test('Aba efetiva inicial, atribuição única e URL sem token, consulta arbitrária ou fragmento', () => {
  const app = make({tab: 'map', url: 'https://worldlabourvalues.org/?tab=map&utm_campaign=paper_2026&utm_source=newsletter&wlv_entry=panel&token_auth=SECRET&query=private#private', referrer: 'https://research.example/private/user?email=SECRET'});
  assert.equal(app.sent.length, 0); app.ready();
  assert.equal(app.pages().length, 1); assert.equal(app.pages()[0].title, 'WLVD / map');
  assert.equal(app.pages()[0].referrer, 'https://research.example/');
  assert.deepEqual([...new URL(app.pages()[0].url).searchParams.keys()].sort(), ['tab', 'utm_campaign', 'utm_source']);
  assert.equal(app.sent.filter(item => item.action === 'entry_origin').length, 1);
  assert.deepEqual(app.commands.slice(0, 3).map(item => item.name), ['disableCookies', 'setDoNotTrack', 'disableBrowserFeatureDetection']);
  assert.deepEqual(app.commands[1].args, [true]);
  assert.equal(app.stored.size, 0); assert.equal(JSON.stringify(app.sent).includes('SECRET'), false);
});
test('Transição de aba efetiva, controles, eventos repetidos e reconexão não duplicam pageviews', () => {
  const app = make({tab: 'map'}); app.ready(); app.advance(5000); app.tab('country');
  assert.equal(app.seconds('map'), 5); assert.equal(app.pages().length, 2);
  app.tab('country'); app.connect(); app.connect(); app.document.dispatch('pointerdown'); app.rerun();
  assert.equal(app.pages().length, 2); app.advance(10000); assert.equal(app.seconds('country'), 10);
  assert.equal(app.inputs.at(-1).value, true);
  app.tab('nested-series'); assert.equal(app.pages().length, 2);
});
test('Fonte e meio da campanha ficam disponíveis sem nome de campanha e priorizam mtm', () => {
  const app = make({url: 'https://worldlabourvalues.org/?utm_source=newsletter&utm_medium=email&mtm_source=faculty&mtm_medium=research'});
  app.ready(); app.tab('map'); app.connect();
  const events = app.sent.filter(item => item.category === 'Acquisition');
  assert.equal(events.length, 2);
  assert.deepEqual(events.map(item => [item.action, item.name]), [['campaign_source', 'faculty'], ['campaign_medium', 'research']]);
  assert.equal(new URL(app.pages()[1].url).searchParams.size, 1);
  const utm = make({url: 'https://worldlabourvalues.org/?utm_source=newsletter&utm_medium=email'}); utm.ready();
  assert.deepEqual(utm.sent.filter(item => item.category === 'Acquisition').map(item => item.name), ['newsletter', 'email']);
});
test('Inatividade limita a contagem a 120 segundos e interação reinicia somente tempo futuro', () => {
  const app = make(); app.ready(); app.advance(165000); assert.equal(app.seconds(), 120);
  app.document.dispatch('pointerdown'); app.advance(15000); assert.equal(app.seconds(), 135);
  assert.ok(app.sent.filter(item => item.action === 'active_seconds').every(item => item.value > 0 && item.value <= 15));
});
test('Ocultar, perder foco e pagehide descontam uma única vez e bfcache retoma sem novo pageview', () => {
  const app = make(); app.ready(); app.advance(4000); app.visible(false); app.window.dispatch('pagehide');
  assert.equal(app.seconds(), 4); app.advance(60000); assert.equal(app.seconds(), 4);
  app.window.dispatch('pageshow', {persisted: true}); app.visible(true); app.advance(3000); app.focus(false);
  assert.equal(app.seconds(), 7); app.advance(50000); assert.equal(app.seconds(), 7); assert.equal(app.pages().length, 1);
});
test('Optout inicial não carrega Matomo; desativação limpa intervalos e impede eventos e downloads', () => {
  const app = make({storage: {wlv_analytics_optout: 'true'}});
  assert.equal(app.scripts.length, 0); assert.equal(app.window.wlvAnalytics.status().enabled, false);
  app.window.wlvAnalytics.setOptOut(false); app.ready(); assert.equal(app.pages().length, 1);
  app.advance(7000); app.window.wlvAnalytics.setOptOut(true); app.advance(30000);
  app.handlers['wlv-analytics-download']({event_id: 'one', status: 'generated', filename: 'data.xlsx'});
  assert.equal(app.sent.length, 1); assert.equal(app.inputs.at(-1).value, false);
  assert.deepEqual([...app.stored], [['wlv_analytics_optout', 'true']]);
  app.window.wlvAnalytics.setOptOut(false); app.window.dispatch('storage', {key: 'wlv_analytics_optout', newValue: 'false'});
  assert.equal(app.pages().length, 2); app.advance(15000); assert.equal(app.seconds(), 8);
});
test('Do Not Track e Global Privacy Control interrompem coleta antes de carregar qualquer tracker', () => {
  for (const options of [{dnt: '1'}, {dnt: 'yes'}, {gpc: true}]) {
    const app = make(options); app.advance(60000); app.window.wlvAnalytics.setOptOut(false);
    assert.equal(app.scripts.length, 0); assert.equal(app.sent.length, 0); assert.equal(app.inputs.at(-1).value, false);
  }
});
test('Armazenamento bloqueado conserva escolha em memória e não impede navegação', () => {
  const app = make({blockStorage: true}); app.ready(); app.window.wlvAnalytics.setOptOut(true); app.tab('map');
  assert.equal(app.window.wlvAnalytics.status().optedOut, true); assert.equal(app.pages().length, 1);
  app.window.wlvAnalytics.setOptOut(false); assert.equal(app.pages().at(-1).title, 'WLVD / map');
});
test('Downloads possuem dez dimensões isoladas, três estados, deduplicação efêmera e sem URL de sessão', () => {
  const app = make({tab: 'download'}); app.ready();
  const payload = {event_id: 'request-1', status: 'requested', kind: 'aggregate', format: 'xlsx', method: 'WIOD16', country: 'BRA,ARG',
    partner: 'USA', indicator: 'gdp.s.mv', years: '2000-2014', sector: 'C10-C12', release: 'release-20260913', filename: 'WorldLabourValues.xlsx', token_auth: 'SECRET', url: '/session/SECRET/download'};
  app.handlers['wlv-analytics-download'](payload); app.window.wlvAnalytics.onDownload(payload);
  app.window.wlvAnalytics.onDownload({...payload, status: 'generated'}); app.window.wlvAnalytics.onDownload({...payload, status: 'failed'});
  const events = app.sent.filter(item => item.category === 'Download'); assert.equal(events.length, 3);
  assert.equal(Object.keys(events[0].dimensions).length, 10); assert.equal(events[0].dimensions[4], 'BRA,ARG');
  assert.equal(JSON.stringify(events).includes('request-1'), false); assert.equal(JSON.stringify(events).includes('SECRET'), false);
  app.advance(15000); assert.deepEqual(app.sent.at(-1).dimensions, {});
  app.window.wlvAnalytics.onDownload({...payload, event_id: 'request-2', filename: '/session/SECRET/data.xlsx'});
  assert.equal(app.sent.at(-1).name, 'aggregate'); assert.equal(app.sent.at(-1).dimensions[10], undefined);
  app.window.wlvAnalytics.onDownload({...payload, status: 'anything'}); assert.equal(app.sent.filter(item => item.category === 'Download').length, 4);
});
test('Tracker indisponível ou endpoint inválido não causa erro ou ciclo de tentativas', () => {
  const app = make(); app.fail(); app.advance(180000); app.tab('map');
  assert.equal(app.sent.length, 0); assert.equal(app.scripts.length, 1); assert.equal(app.inputs.at(-1).value, false);
  const invalid = make({config: {enabled: true, site_id: 2, tracker_url: 'https://outside.example/matomo.php', script_url: '/estatisticas/matomo.js'}});
  assert.equal(invalid.scripts.length, 0);
  const timeout = make(); timeout.advance(10000); timeout.ready(); assert.equal(timeout.sent.length, 0);
});
test('Fila antes do carregamento tem limite e não cresce sem controle', () => {
  const app = make(); for (let i = 0; i < 150; i++) app.tab(i % 2 ? 'about' : 'map'); app.ready();
  assert.equal(app.pages().length, 64);
});
test('Outra janela em foco interrompe tempo e optout propaga sem criar identificador', () => {
  const bus = [], first = make({bus}); first.ready(); first.advance(3000);
  const second = make({bus}); second.ready(); first.advance(15000); second.advance(15000);
  assert.equal(first.seconds(), 3); assert.equal(second.seconds(), 15);
  second.window.wlvAnalytics.setOptOut(true); assert.equal(first.window.wlvAnalytics.status().optedOut, true);
  second.window.wlvAnalytics.setOptOut(false); const count = first.pages().length;
  first.window.dispatch('storage', {key: 'wlv_analytics_optout', newValue: 'false'}); assert.equal(first.pages().length, count);
  assert.deepEqual([...second.stored.keys()], ['wlv_analytics_optout']);
});
test('Diálogo abre pelo rodapé e pela engrenagem e devolve foco ao controle acessível', () => {
  const app = make({ui: true}); app.ready();
  const nodes = app.elements;
  nodes['wlv-privacy-open'].dispatch('click');
  assert.equal('open' in nodes['wlv-privacy-dialog'].attributes, true);
  assert.equal(app.document.activeElement.id, 'wlv-privacy-toggle');
  nodes['wlv-privacy-close'].dispatch('click');
  assert.equal('open' in nodes['wlv-privacy-dialog'].attributes, false);
  assert.equal(app.document.activeElement.id, 'wlv-privacy-open');
  nodes['wlv-settings'].setAttribute('open', '');
  nodes['wlv-privacy-open-settings'].dispatch('click');
  assert.equal('open' in nodes['wlv-settings'].attributes, false);
  assert.equal('open' in nodes['wlv-privacy-dialog'].attributes, true);
  nodes['wlv-privacy-toggle'].dispatch('click');
  assert.equal(app.window.wlvAnalytics.status().optedOut, true);
  nodes['wlv-privacy-dialog'].dispatch('cancel', {preventDefault() {}});
  assert.equal('open' in nodes['wlv-privacy-dialog'].attributes, false);
  assert.equal(app.document.activeElement.id, 'settings_toggle');
});

fs.mkdirSync(path.join(campaign, 'results'), {recursive: true});
const report = {passed: tests.length, failed: 0, tests};
fs.writeFileSync(path.join(campaign, 'results', 'analytics-state-tests.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
