// Ensaio integrado: navegador real, Shiny real e Matomo de homologação.
// Nunca persiste tokens Shiny, IDs de visitantes, cookies ou URLs de downloads.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {createRequire} = require('node:module');

if (process.argv.includes('--help')) {
  console.log('Uso: configure WLV_CAMPAIGN_ROOT, TEMP/TMP/TMPDIR e WLVPANEL_URL=http://127.0.0.1:8094/; execute node tests/manual/check-analytics-browser.cjs <fase>.');
  console.log('Exige site Matomo2 de homologação. WLVPANEL_ANALYTICS_CASES seleciona casos separados por vírgula: desktop,mobile,dnt,gpc,script-blocked,collector-blocked.');
  process.exit(0);
}

const root = fs.realpathSync(path.join(__dirname, '../..'));
const campaign = fs.realpathSync(process.env.WLV_CAMPAIGN_ROOT || '');
assert.equal(path.dirname(campaign), path.join(root, 'temp'));
const campaignRecord = JSON.parse(fs.readFileSync(path.join(campaign, '.campaign.json')));
assert.equal(campaignRecord.schema, 'wlv-campaign/1');
assert.equal(campaignRecord.id, path.basename(campaign));
assert.equal(campaignRecord.status, 'active');
for (const key of ['TEMP', 'TMP', 'TMPDIR']) assert.equal(fs.realpathSync(process.env[key] || ''), path.join(campaign, 'scratch'));
const browserTemporary = fs.realpathSync(process.env.WLV_BROWSER_TMPDIR || path.join(campaign, 'scratch'));
const browserCampaign = path.dirname(browserTemporary);
assert.equal(path.basename(browserTemporary), 'scratch');
assert.ok(campaign === browserCampaign || campaign.startsWith(browserCampaign + path.sep),
  'Temporários do navegador devem ficar na campanha de teste ou em sua campanha ancestral.');
const browserRecord = JSON.parse(fs.readFileSync(path.join(browserCampaign, '.campaign.json')));
assert.equal(browserRecord.schema, 'wlv-campaign/1');
assert.equal(browserRecord.id, path.basename(browserCampaign));
assert.equal(browserRecord.status, 'active');
const phase = process.argv[2];
assert.match(phase || '', /^[a-z0-9][a-z0-9_-]*$/);
const target = new URL(process.env.WLVPANEL_URL || 'http://127.0.0.1:8094/');
assert.ok(target.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(target.hostname));
assert.equal(target.pathname, '/');
assert.ok(!target.search && !target.hash && !target.username && !target.password);
const output = path.join(campaign, 'results', 'analytics-browser-' + phase);
fs.mkdirSync(output);
const marker = 'analytics-' + new Date().toISOString().replace(/[^0-9]/g, '') + '-' + phase;
const audit = {marker, target: target.origin, startedAt: new Date().toISOString(), expectedSite: '2',
  transport: 'HTTP real via route.fetch/fulfill; WebSocket direto; bloqueios e sinais do navegador apenas nos cenários identificados.',
  cases: [], requests: [], downloads: [], layouts: []};
const evidence = () => fs.writeFileSync(path.join(output, 'audit.json'), JSON.stringify(audit, null, 2));
const redact = value => String(value).replace(/\/session\/[^/\s]+/g, '/session/[redigido]')
  .replace(/([?&](?:token_auth|_id|visitorId)=)[^&\s]+/gi, '$1[redigido]');
const label = url => { const parsed = new URL(url); return parsed.origin + redact(parsed.pathname); };
const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
async function until(predicate, message, timeout = 30000) {
  const started = Date.now();
  while (!predicate()) {
    assert.ok(Date.now() - started < timeout, message);
    await wait(150);
  }
}
const requireBrowser = createRequire(path.join(campaign, 'scratch/browser/package.json'));
const {chromium} = requireBrowser('playwright');
let browser;

function trackerRecord(request, name) {
  const url = new URL(request.url());
  const params = new URLSearchParams(request.postData() || url.search);
  const record = {case: name, at: new Date().toISOString(), method: request.method(), site: params.get('idsite'),
    parameters: [...params.keys()].sort(), event: null, dimensions: {}};
  assert.equal(record.site, '2', 'O ensaio deve enviar somente ao site Matomo 2.');
  if (params.get('url')) {
    const page = new URL(params.get('url'));
    record.tab = page.searchParams.get('tab');
    record.page = page.origin + '/?tab=' + record.tab;
    record.campaign = page.searchParams.get('utm_campaign');
    record.source = page.searchParams.get('utm_source');
    record.medium = page.searchParams.get('utm_medium');
    assert.ok(!params.get('url').includes('/session/'));
  }
  if (params.has('e_c')) record.event = {category: params.get('e_c'), action: params.get('e_a'), name: params.get('e_n'), value: Number(params.get('e_v'))};
  for (const [key, value] of params) if (/^dimension\d+$/.test(key)) record.dimensions[key] = value;
  assert.ok(!params.has('token_auth') && !params.has('uid'));
  audit.requests.push(record);
  return record;
}
function records(name) { return audit.requests.filter(record => record.case === name); }
function pageviews(name) { return records(name).filter(record => !record.event); }
function downloads(name, filename, action) {
  return records(name).filter(record => record.event?.category === 'Download' &&
    (!filename || record.event.name === filename) && (!action || record.event.action === action));
}

async function contextFor(name, options = {}) {
  const context = await browser.newContext({locale: 'pt-BR', viewport: {width: options.width || 1440, height: 900}, acceptDownloads: true});
  context.setDefaultTimeout(90000); context.setDefaultNavigationTimeout(120000);
  const state = {name, expectedBlock: options.block || '', errors: [], httpErrors: [], failures: [], scripts: 0,
    sockets: 0, framesReceived: 0, startedAt: new Date().toISOString()};
  if (options.signal) await context.addInitScript(signal => {
    Object.defineProperty(navigator, signal === 'dnt' ? 'doNotTrack' : 'globalPrivacyControl',
      {configurable: true, get: () => signal === 'dnt' ? '1' : true});
  }, options.signal);
  context.on('page', page => {
    page.on('pageerror', error => state.errors.push(redact(error.message)));
    page.on('requestfailed', request => {
      const url = new URL(request.url());
      if (options.block === 'script' && url.pathname === '/estatisticas/matomo.js' ||
          options.block === 'collector' && url.pathname === '/estatisticas/matomo.php') return;
      state.failures.push({request: label(request.url()), error: request.failure()?.errorText});
    });
    page.on('websocket', socket => { state.sockets++; socket.on('framereceived', () => state.framesReceived++); });
  });
  await context.route(url => url.origin === target.origin, async route => {
    const request = route.request(), url = new URL(request.url());
    let record;
    if (url.pathname === '/estatisticas/matomo.js') state.scripts++;
    if (url.pathname === '/estatisticas/matomo.php') record = trackerRecord(request, name);
    if (options.block === 'script' && url.pathname === '/estatisticas/matomo.js' ||
        options.block === 'collector' && url.pathname === '/estatisticas/matomo.php') {
      if (record) record.blocked = true;
      await route.abort('blockedbyclient'); return;
    }
    try {
      const response = await route.fetch({timeout: 90000});
      if (record) record.httpStatus = response.status();
      if (response.status() >= 400) state.httpErrors.push({request: label(request.url()), status: response.status()});
      await route.fulfill({response});
    } catch (error) {
      state.failures.push({request: label(request.url()), error: redact(error.message)});
      await route.abort('failed').catch(() => {});
    }
  });
  return {context, state};
}
async function ready(page, tab) {
  await page.waitForFunction(tab => window.Shiny?.shinyapp?.isConnected() &&
    window.Shiny.shinyapp.$inputValues.main_nav === tab && document.body.dataset.wlvTab === tab &&
    !document.documentElement.classList.contains('shiny-busy'), tab);
  if (tab === 'map') await page.waitForFunction(() => window.WLVMap?.stats('map')?.layers > 0 && document.querySelector('#map[aria-busy="false"]'));
  await page.waitForFunction(() => !document.documentElement.classList.contains('shiny-busy') &&
    [...document.querySelectorAll('.shiny-output-error')].every(node => !node.offsetWidth || !node.offsetHeight));
}
async function nav(page, tab) {
  console.log('Aba:', tab);
  if (page.viewportSize().width < 768 && !await page.locator('.navbar-collapse').evaluate(node => node.classList.contains('in'))) await page.locator('.navbar-toggle').click();
  await page.locator('#main_nav a[data-value="' + tab + '"]').click();
  if (page.viewportSize().width < 768) await page.locator('.navbar-collapse').waitFor({state: 'hidden'});
  await ready(page, tab);
}
async function choose(page, id, value) {
  const values = Array.isArray(value) ? value : value ? [value] : [];
  await page.waitForFunction(({id, values}) => {
    const node = document.getElementById(id);
    return node && values.every(value => node.selectize ? !!node.selectize.options[value] : [...node.options].some(option => option.value === value));
  }, {id, values});
  await page.locator('[id="' + id + '"]').evaluate((node, value) => {
    if (node.selectize) node.selectize.setValue(value);
    else { node.value = value; window.jQuery(node).trigger('change'); }
  }, value);
  await page.waitForFunction(({id, value}) => JSON.stringify(window.Shiny.shinyapp.$inputValues[id]) === JSON.stringify(value), {id, value});
  await page.waitForFunction(() => !document.documentElement.classList.contains('shiny-busy'));
}
async function layout(page, name) {
  const value = await page.evaluate(() => ({tab: document.body.dataset.wlvTab, width: innerWidth,
    scrollWidth: document.documentElement.scrollWidth,
    visibleErrors: [...document.querySelectorAll('.shiny-output-error')].filter(node => node.offsetWidth && node.offsetHeight).map(node => node.textContent),
    hiddenErrors: Object.entries(window.Shiny.shinyapp.$errors || {}).filter(([id]) => {
      const node = document.getElementById(id); return !node || !node.offsetWidth || !node.offsetHeight;
    }).map(([id, error]) => ({id, message: String(error.message || '').slice(0, 300), type: error.type}))}));
  assert.ok(value.scrollWidth <= value.width + 1, JSON.stringify(value));
  assert.deepEqual(value.visibleErrors, []);
  audit.layouts.push({case: name, ...value});
}
async function storage(context, page) {
  const cookies = (await context.cookies()).map(cookie => cookie.name);
  assert.ok(!cookies.some(name => /^(_pk_|mtm)/i.test(name)), 'Cookie de identificação inesperado.');
  const local = await page.evaluate(() => Object.keys(localStorage).map(key => ({key,
    value: key === 'wlv_analytics_optout' ? localStorage.getItem(key) : '[valor não registrado]'})));
  assert.ok(local.every(item => item.key === 'wlv_analytics_optout' && ['true', 'false'].includes(item.value)), 'Identificador inesperado no localStorage.');
  return {cookies, local};
}
async function saveDownload(page, name, id, expected, retain = false) {
  await page.locator('[id="' + id + '"]').waitFor({state: 'visible'});
  await page.waitForFunction(id => document.getElementById(id)?.getAttribute('href') &&
    !document.getElementById(id).classList.contains('disabled'), id);
  const pending = page.waitForEvent('download');
  await page.locator('[id="' + id + '"]').click();
  const download = await pending;
  const filename = download.suggestedFilename();
  if (expected) assert.equal(filename, expected);
  const file = await download.path(), bytes = fs.readFileSync(file);
  assert.ok(bytes.length > 100);
  if (filename.endsWith('.xlsx')) assert.equal(bytes.subarray(0, 2).toString(), 'PK');
  else { assert.ok(filename.endsWith('.csv')); assert.ok(bytes.toString('utf8').includes('country')); }
  const result = {case: name, control: id, filename, bytes: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex')};
  if (retain) { result.artifact = name + '-' + filename; await download.saveAs(path.join(output, result.artifact)); }
  audit.downloads.push(result); await download.delete();
  console.log('Arquivo:', filename, bytes.length, 'bytes');
  return result;
}
async function validateDownload(name, result, expected, dimensions) {
  await until(() => downloads(name, result.filename, 'generated').length === 1, 'Evento generated ausente: ' + result.filename);
  const events = downloads(name, result.filename);
  assert.deepEqual(events.map(item => item.event.action).sort(), ['generated', 'requested']);
  for (const record of events) {
    assert.equal(record.method, 'POST');
    for (const [key, value] of Object.entries({...expected, filename: result.filename})) assert.equal(record.dimensions['dimension' + dimensions[key]], value, key);
  }
}
async function aggregate(page) {
  await nav(page, 'download'); await choose(page, 'dl_method', 'WIOD13');
  await choose(page, 'dl_country', 'BRA'); await choose(page, 'dl_indicator', 'surplus_value.empe_p.r.pc');
}
async function openPrivacy(page) {
  let opener = 'wlv-privacy-open';
  if (await page.locator('#wlv-privacy-open').isVisible()) await page.locator('#wlv-privacy-open').click();
  else {
    opener = 'wlv-privacy-open-settings';
    await page.locator('#settings_toggle').click();
    await page.locator('#wlv-privacy-open-settings').click();
    assert.equal(await page.locator('#wlv-settings').getAttribute('open'), null);
  }
  await page.locator('#wlv-privacy-dialog').waitFor({state: 'visible'});
  assert.equal(await page.locator('#wlv-privacy-dialog').evaluate(node => !!node.closest('footer')), false);
  return opener;
}
async function closePrivacy(page, opener, escape = false) {
  if (escape) await page.keyboard.press('Escape');
  else await page.locator('#wlv-privacy-close').click();
  const expected = opener === 'wlv-privacy-open-settings' ? 'settings_toggle' : opener;
  assert.equal(await page.evaluate(() => document.activeElement.id), expected);
}
async function toggle(page, optedOut) {
  const opener = await openPrivacy(page);
  await page.locator('#wlv-privacy-toggle').click();
  await page.waitForFunction(value => window.wlvAnalytics.status().optedOut === value &&
    window.Shiny.shinyapp.$inputValues.wlv_analytics_enabled === !value, optedOut);
  await closePrivacy(page, opener);
}
async function runCase(name, options, body) {
  console.log('Iniciando:', name);
  const {context, state} = await contextFor(name, options);
  const page = await context.newPage();
  try {
    await body({page, context, state, name});
    state.storage = await storage(context, page);
    assert.deepEqual(state.errors, []); assert.deepEqual(state.httpErrors, []); assert.deepEqual(state.failures, []);
    assert.ok(state.sockets > 0 && state.framesReceived > 0);
    state.status = 'passed'; console.log('OK:', name);
  } catch (error) {
    state.status = 'failed'; state.failure = redact(error.message); state.stack = redact(error.stack);
    console.error('FALHA:', name, state.failure);
    if (!page.isClosed()) {
      state.lastState = await page.evaluate(() => ({tab: document.body.dataset.wlvTab,
        busy: document.documentElement.classList.contains('shiny-busy'),
        connected: window.Shiny?.shinyapp?.isConnected(),
        errors: Object.entries(window.Shiny?.shinyapp?.$errors || {}).map(([id, error]) => ({id,
          message: String(error.message || '').slice(0, 300), type: error.type}))})).catch(() => ({}));
      await page.screenshot({path: path.join(output, name + '-failure.png'), fullPage: true}).catch(() => {});
    }
  } finally {
    await context.unrouteAll({behavior: 'wait'}); await context.close();
    state.finishedAt = new Date().toISOString(); audit.cases.push(state); evidence();
  }
}

(async () => {
  const previousTemporary = Object.fromEntries(['TEMP', 'TMP', 'TMPDIR'].map(key => [key, process.env[key]]));
  // Playwright cria o perfil pelo Node antes de iniciar o Chromium.
  for (const key of ['TEMP', 'TMP', 'TMPDIR']) process.env[key] = browserTemporary;
  try {
    browser = await chromium.launch({headless: true, executablePath: process.env.WLVPANEL_CHROMIUM || '/usr/bin/chromium',
      env: {...process.env}, args: JSON.parse(process.env.WLVPANEL_CHROMIUM_ARGS || '[]')});
  } finally {
    Object.assign(process.env, previousTemporary);
  }
  const selected = (process.env.WLVPANEL_ANALYTICS_CASES || 'desktop,mobile,dnt,gpc,script-blocked,collector-blocked').split(',');
  if (selected.includes('desktop')) await runCase('desktop', {}, async ({page, context, name, state}) => {
    await page.goto(target.href + '?tab=map&utm_source=ensaio&utm_medium=browser&utm_campaign=' + marker);
    await ready(page, 'about'); await page.bringToFront();
    await page.waitForFunction(() => window.wlvAnalytics?.status().enabled && window.Shiny.shinyapp.$inputValues.wlv_analytics_enabled === true);
    const config = await page.locator('#wlv-analytics-config').textContent();
    const dimensions = JSON.parse(config).dimensions;
    await until(() => pageviews(name).length >= 1, 'Pageview inicial ausente.');
    assert.equal(pageviews(name).length, 1); assert.equal(pageviews(name)[0].tab, 'about');
    assert.equal(pageviews(name)[0].campaign, marker);
    assert.equal(pageviews(name)[0].source, 'ensaio'); assert.equal(pageviews(name)[0].medium, 'browser');
    await nav(page, 'map');
    await page.mouse.move(220, 240); await wait(17000);
    await nav(page, 'about');
    await until(() => records(name).filter(item => item.event?.category === 'Engagement' && item.event.name === 'map').reduce((sum, item) => sum + item.event.value, 0) >= 15,
      'Tempo ativo de Mapa inferior a15s.');
    for (const tab of ['about', 'country', 'indicators', 'trade', 'download', 'publications']) {
      if (tab !== 'about') await nav(page, tab);
      if (tab === 'trade') await page.waitForFunction(() => document.getElementById('trade-app')?.dataset.ready === 'true' &&
        document.getElementById('trade-rank')?.data?.some(trace => Array.from(trace.x || []).some(Number.isFinite)));
      await layout(page, name);
    }
    await until(() => pageviews(name).length >= 8, 'Abas não chegaram ao Matomo.');
    assert.deepEqual(pageviews(name).slice(0, 8).map(item => item.tab), ['about', 'map', 'about', 'country', 'indicators', 'trade', 'download', 'publications']);
    assert.ok(pageviews(name).slice(1).every(item => !item.campaign));
    await aggregate(page);
    let result = await saveDownload(page, name, 'dl_file', 'BRA.surplus_value.empe_p.r.pc.WIOD13.xlsx', true);
    await validateDownload(name, result, {kind: 'aggregate', format: 'xlsx', country: 'BRA', method: 'WIOD13', indicator: 'surplus_value.empe_p.r.pc'}, dimensions);
    await choose(page, 'dl_ml_method', 'WIOD13'); await choose(page, 'dl_ml_country', 'BRA'); await choose(page, 'dl_ml_partner', 'USA');
    result = await saveDownload(page, name, 'dl_ml_file', 'BRA.USA.WIOD13.xlsx', true);
    await validateDownload(name, result, {kind: 'bilateral', format: 'xlsx', country: 'BRA', partner: 'USA', method: 'WIOD13'}, dimensions);
    await choose(page, 'dl_ml_partner', ''); await choose(page, 'dl_ml_ind_cat', 'CX.');
    await choose(page, 'dl_ml_ind_scope', 'T.'); await choose(page, 'dl_ml_ind_un', 'MP');
    result = await saveDownload(page, name, 'dl_ml_file', 'BRA.CX.T.MP.WIOD13.xlsx', true);
    await validateDownload(name, result, {kind: 'multilateral', format: 'xlsx', country: 'BRA', method: 'WIOD13', indicator: 'CX.T.MP'}, dimensions);
    await nav(page, 'indicators');
    await page.locator('[id="indicators-catalogue_surplus_value.empe_p.r.pc"]').click();
    await choose(page, 'indicators-methods', ['WIOD16']); await choose(page, 'indicators-countries', ['BRA']);
    result = await saveDownload(page, name, 'indicators-download', 'WLVD-surplus_value.empe_p.r.pc.csv', true);
    await validateDownload(name, result, {kind: 'indicators_csv', format: 'csv', country: 'BRA', method: 'WIOD16', indicator: 'surplus_value.empe_p.r.pc'}, dimensions);
    await nav(page, 'trade'); await choose(page, 'trade-method', 'WIOD16');
    await choose(page, 'trade-country', 'BRA'); await choose(page, 'trade-partner', 'USA');
    result = await saveDownload(page, name, 'trade-download', 'WLVD-trade-BRA-WIOD16-2007.xlsx', true);
    await validateDownload(name, result, {kind: 'trade_selection', format: 'xlsx', country: 'BRA', partner: 'USA', method: 'WIOD16', years: '2007'}, dimensions);
    result = await saveDownload(page, name, 'trade-download_series', 'WLVD-trade-BRA-WIOD16-series.xlsx', true);
    await validateDownload(name, result, {kind: 'trade_series', format: 'xlsx', country: 'BRA', partner: 'USA', method: 'WIOD16', years: '2000-2014'}, dimensions);
    await nav(page, 'about'); await page.mouse.move(260, 230); await wait(1600);
    const beforeBlur = records(name).filter(item => item.event?.action === 'active_seconds').length;
    const foreground = await context.newPage(); await foreground.goto('about:blank'); await foreground.bringToFront();
    // Playwright força foco em cada página headless. Desativar essa emulação
    // permite observar o blur real da página anterior, sem alterar código do app.
    const devtools = await context.newCDPSession(page);
    await devtools.send('Emulation.setFocusEmulationEnabled', {enabled: false});
    state.focusTest = 'DevTools desativa foco forçado do headless; ativação real da segunda página e retorno à primeira.';
    state.background = await page.evaluate(() => ({visibility: document.visibilityState, focus: document.hasFocus()}));
    assert.ok(state.background.visibility === 'hidden' || !state.background.focus, 'A janela não perdeu o foco.');
    await until(() => records(name).filter(item => item.event?.action === 'active_seconds').length > beforeBlur, 'Troca de foco não descarregou tempo pendente.');
    const backgroundCount = records(name).length; await wait(16000);
    assert.equal(records(name).length, backgroundCount, 'Tempo foi contado em segundo plano.');
    await foreground.close(); await page.bringToFront();
    await toggle(page, true); await wait(300);
    const optedOutCount = records(name).length;
    await aggregate(page); await saveDownload(page, name, 'dl_file');
    assert.equal(records(name).length, optedOutCount, 'Optout enviou estatísticas.');
    const scripts = state.scripts; await page.reload(); await ready(page, 'download');
    await page.waitForFunction(() => window.wlvAnalytics.status().optedOut && !window.wlvAnalytics.status().enabled);
    assert.equal(state.scripts, scripts); assert.equal(records(name).length, optedOutCount);
    await nav(page, 'map');
    const settingsOpener = await openPrivacy(page);
    assert.equal(settingsOpener, 'wlv-privacy-open-settings');
    await page.screenshot({path: path.join(output, 'desktop-privacy.png')});
    await closePrivacy(page, settingsOpener, true);
    const acquisitionCount = records(name).filter(item => item.event?.category === 'Acquisition').length;
    await toggle(page, false);
    await until(() => records(name).length > optedOutCount, 'Reativação não retomou coleta.');
    // Matomo retarda os eventos que seguem o primeiro pageview em cerca de800ms.
    // Aguardar o envio já solicitado evita confundir requisições anteriores com
    // coleta de ações realizadas depois da nova desativação.
    await until(() => {
      const acquisition = records(name).filter(item => item.event?.category === 'Acquisition');
      return acquisition.length === acquisitionCount + 2 && acquisition.slice(-2).every(item => item.httpStatus === 204);
    }, 'Atribuição da reativação ainda não terminou.');
    await toggle(page, true);
    const mapOptoutCount = records(name).length; await nav(page, 'publications');
    assert.equal(records(name).length, mapOptoutCount, 'Optout pelo Mapa não foi respeitado.');
    state.checked = ['7 abas', 'entrada Sobre e navegação explícita ao Mapa', 'campanha', 'tempo ativo>=15s', 'pausa fora de foco', '6 downloads reais', 'optout e reload', 'reativação pela engrenagem', 'optout no Mapa', 'retorno de foco'];
  });
  if (selected.includes('mobile')) await runCase('mobile', {width: 390}, async ({page, context, name}) => {
    await page.goto(target.href + '?tab=map&utm_campaign=' + marker + '-mobile'); await ready(page, 'about'); await nav(page, 'map');
    for (const tab of ['map', 'about', 'trade', 'publications']) { if (tab !== 'map') await nav(page, tab); await layout(page, name); }
    await page.locator('#wlv-privacy-open').click(); await page.locator('#wlv-privacy-dialog').waitFor({state: 'visible'});
    await layout(page, name); await page.screenshot({path: path.join(output, 'mobile-privacy.png')});
    await page.locator('#wlv-privacy-close').click(); await toggle(page, true);
    const count = records(name).length; await nav(page, 'map'); assert.equal(records(name).length, count);
    await storage(context, page);
  });
  for (const signal of ['dnt', 'gpc']) if (selected.includes(signal)) await runCase(signal, {signal}, async ({page, state, name}) => {
    await page.goto(target.href + '?tab=map&utm_campaign=' + marker + '-' + signal); await ready(page, 'about'); await nav(page, 'map');
    await page.waitForFunction(() => window.wlvAnalytics.status().browserSignal && !window.wlvAnalytics.status().enabled);
    await aggregate(page); await saveDownload(page, name, 'dl_file');
    assert.equal(state.scripts, 0); assert.equal(records(name).length, 0);
    await page.locator('#wlv-privacy-open').click(); assert.ok(await page.locator('#wlv-privacy-toggle').isDisabled());
    await page.locator('#wlv-privacy-close').click();
  });
  for (const block of ['script', 'collector']) if (selected.includes(block + '-blocked')) await runCase(block + '-blocked', {block}, async ({page, name}) => {
    await page.goto(target.href + '?tab=map&utm_campaign=' + marker + '-' + block); await ready(page, 'about'); await nav(page, 'map');
    if (block === 'script') await page.waitForFunction(() => !window.wlvAnalytics.status().enabled);
    await aggregate(page); await saveDownload(page, name, 'dl_file'); await nav(page, 'about'); await layout(page, name);
    if (block === 'script') assert.equal(records(name).length, 0);
    else assert.ok(records(name).length > 0 && records(name).every(item => item.blocked));
  });
  audit.finishedAt = new Date().toISOString();
  audit.status = audit.cases.every(item => item.status === 'passed') ? 'passed' : 'failed';
  evidence(); console.log(JSON.stringify({marker, output, status: audit.status, cases: audit.cases.map(item => ({name: item.name, status: item.status}))}));
  if (audit.status !== 'passed') process.exitCode = 1;
})().catch(error => { audit.status = 'failed'; audit.failure = redact(error.message); evidence(); console.error(redact(error.message)); process.exitCode = 1; })
  .finally(async () => { if (browser) await browser.close(); });
