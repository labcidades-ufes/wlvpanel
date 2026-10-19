'use strict';
// Smoke público após a troca; gera uma visita de validação identificada por campanha.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
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
const {chromium} = require(path.join(campaign, 'scratch/browser/node_modules/playwright'));
const destination = path.join(campaign, 'results/analytics-production.json');
assert.ok(!fs.existsSync(destination));
const marker = 'analytics-production-validation-' + new Date().toISOString().replace(/[^0-9]/g, '');
const result = {marker, site_id: 1, real_http_transport: true, events: [], errors: [], checks: []};
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
let browser;
function sanitize(value) { return String(value).replace(/\/session\/[^\s/?]+/g, '/session/[redacted]').split('\n')[0]; }
async function ready(page, tab) {
  await page.waitForFunction(tab => window.Shiny?.shinyapp?.isConnected() && Boolean(window.Shiny.shinyapp.config?.sessionId) &&
    document.body.dataset.wlvTab === tab && !document.documentElement.classList.contains('shiny-busy'), tab);
  assert.equal(await page.locator('.shiny-output-error:visible').count(), 0);
}
(async () => {
  const previousTemporary = Object.fromEntries(['TEMP', 'TMP', 'TMPDIR'].map(key => [key, process.env[key]]));
  // Playwright cria o perfil pelo Node antes de iniciar o Chromium.
  for (const key of ['TEMP', 'TMP', 'TMPDIR']) process.env[key] = browserTemporary;
  try {
    browser = await chromium.launch({executablePath: '/usr/bin/chromium', headless: true,
      env: {...process.env}, args: ['--no-sandbox', '--disable-dev-shm-usage']});
  } finally {
    Object.assign(process.env, previousTemporary);
  }
  const context = await browser.newContext({locale: 'pt-BR', viewport: {width: 1440, height: 1000}, acceptDownloads: true});
  context.setDefaultTimeout(90000);
  await context.route(url => ['worldlabourvalues.org', 'panel.worldlabourvalues.org'].includes(url.hostname), async route => {
    const request = route.request(), url = new URL(request.url());
    try {
      if (url.pathname === '/estatisticas/matomo.php') {
        const data = new URLSearchParams(request.postData() || url.search);
        assert.equal(data.get('idsite'), '1');
        assert.equal(request.method(), 'POST');
        assert.ok(!data.has('token_auth') && !data.has('uid'));
        const page = new URL(data.get('url'));
        const event = {tab: page.searchParams.get('tab'), campaign: page.searchParams.get('utm_campaign'),
          category: data.get('e_c'), action: data.get('e_a'), name: data.get('e_n'), value: data.get('e_v')};
        const response = await route.fetch();
        event.status = response.status(); result.events.push(event);
        assert.equal(response.status(), 204);
        assert.ok(!response.headers()['set-cookie']);
        await route.fulfill({response}); return;
      }
      const response = await route.fetch({timeout: 90000, maxRedirects: 0});
      if (response.status() >= 400) result.errors.push({path: url.pathname, status: response.status()});
      await route.fulfill({response});
    } catch (error) {
      result.errors.push({path: url.pathname.replace(/\/session\/[^/]+/, '/session/[redacted]'), error: sanitize(error.message)});
      await route.abort().catch(() => {});
    }
  });
  const page = await context.newPage();
  page.on('pageerror', error => result.errors.push({error: sanitize(error.message)}));
  await page.goto('https://panel.worldlabourvalues.org/?utm_source=validacao&utm_medium=operacao&utm_campaign=' + marker,
    {timeout: 120000});
  await ready(page, 'about');
  await page.waitForFunction(() => window.wlvAnalytics?.status().enabled);
  await page.locator('#main_nav a[data-value="map"]').click(); await ready(page, 'map');
  await page.waitForFunction(() => window.WLVMap?.stats('map')?.layers > 0 && window.wlvAnalytics?.status().enabled);
  const config = JSON.parse(await page.locator('#wlv-analytics-config').textContent());
  assert.equal(config.site_id, 1);
  assert.equal(new URL(page.url()).hostname, 'worldlabourvalues.org');
  assert.equal(new URL(page.url()).searchParams.get('wlv_entry'), 'panel');
  await page.locator('#settings_toggle').click();
  await page.locator('#wlv-privacy-open-settings').click();
  await page.locator('#wlv-privacy-dialog').waitFor({state: 'visible'});
  await page.locator('#wlv-privacy-close').click();
  result.checks.push('privacidade acessível nas configurações do Mapa');
  await page.bringToFront(); await page.mouse.move(220, 240); await pause(17000);
  await page.locator('#main_nav a[data-value="about"]').click(); await ready(page, 'about');
  assert.ok(result.events.some(event => event.category === 'Engagement' && Number(event.value) >= 15));
  assert.ok(result.events.some(event => event.category === 'Acquisition' && event.action === 'entry_origin' && event.name === 'panel'));
  assert.equal(result.events.filter(event => !event.category && event.tab === 'map').length, 1);
  assert.equal(result.events.find(event => !event.category).tab, 'about');
  assert.equal(result.events.find(event => !event.category).campaign, marker);
  result.checks.push('redirecionamento público para Sobre, navegação ao Mapa, site1, campanha e origem panel', 'visualizações e tempo recebidos pelo coletor');
  await page.setViewportSize({width: 390, height: 900});
  await page.locator('#wlv-privacy-open').click();
  const buttonStyle = await page.locator('#wlv-privacy-toggle').evaluate(node => {
    const style = getComputedStyle(node); return {color: style.color, background: style.backgroundColor};
  });
  assert.deepEqual(buttonStyle, {color: 'rgb(35, 52, 58)', background: 'rgb(241, 245, 246)'});
  await page.screenshot({path: path.join(campaign, 'results/analytics-production-privacy-mobile.png')});
  result.checks.push('diálogo móvel com contraste de botão focado corrigido');
  await page.locator('#wlv-privacy-toggle').click();
  await page.waitForFunction(() => window.wlvAnalytics.status().optedOut && window.Shiny.shinyapp.$inputValues.wlv_analytics_enabled === false);
  await page.locator('#wlv-privacy-close').click(); await page.setViewportSize({width: 1440, height: 1000}); await pause(500);
  const count = result.events.length;
  await page.locator('#main_nav a[data-value="download"]').click(); await ready(page, 'download');
  result.checks.push('optout aplicado e aba Download conectada');
  // A exportação exige uma seleção explícita; os controles começam vazios.
  for (const [id, value] of [['dl_method', 'WIOD13'], ['dl_country', 'BRA'], ['dl_indicator', 'surplus_value.empe_p.r.pc']]) {
    await page.waitForFunction(({id, value}) => !!document.getElementById(id)?.selectize?.options[value], {id, value});
    await page.locator('[id="' + id + '"]').evaluate((node, value) => node.selectize.setValue(value), value);
    await page.waitForFunction(({id, value}) => window.Shiny.shinyapp.$inputValues[id] === value &&
      !document.documentElement.classList.contains('shiny-busy'), {id, value});
  }
  await page.waitForFunction(() => document.getElementById('dl_file')?.getAttribute('href') && !document.getElementById('dl_file').classList.contains('disabled'));
  const pending = page.waitForEvent('download'); await page.locator('#dl_file').click();
  const download = await pending, bytes = fs.readFileSync(await download.path());
  assert.ok(bytes.length > 100); assert.equal(bytes.subarray(0, 2).toString(), 'PK');
  result.download = {filename: download.suggestedFilename(), bytes: bytes.length};
  await download.delete(); await pause(500); assert.equal(result.events.length, count);
  const cookies = (await context.cookies()).map(cookie => cookie.name);
  assert.ok(!cookies.some(name => /^(_pk_|mtm)/i.test(name)));
  result.cookies = cookies;
  assert.equal(await page.evaluate(() => localStorage.getItem('wlv_analytics_optout')), 'true');
  result.checks.push('optout impede novos eventos e preserva download real', 'nenhum cookie de identificação analítica');
  assert.deepEqual(result.errors, []);
  result.status = 'passed';
  await context.unrouteAll({behavior: 'ignoreErrors'}); await context.close();
})().catch(error => { result.status = 'failed'; result.failure = sanitize(error.message); process.exitCode = 1; })
  .finally(async () => {
    if (browser) await browser.close();
    result.finished_at_utc = new Date().toISOString();
    fs.writeFileSync(destination, JSON.stringify(result, null, 2) + '\n');
    console.log(JSON.stringify(result, null, 2));
  });
