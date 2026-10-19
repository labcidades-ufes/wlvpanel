'use strict';
// Validação administrativa com credencial somente em memória; sem traces/storageState.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const campaign = process.env.WLV_CAMPAIGN_ROOT;
assert.ok(campaign && path.resolve(campaign).startsWith(path.join(root, 'temp') + path.sep), 'Configure a campanha do painel.');
const {chromium} = require(path.join(campaign, 'scratch/browser/node_modules/playwright'));
const credential = JSON.parse(fs.readFileSync('/home/franklin/.local/share/server-credentials/worldlabourvalues-matomo-admin.json', 'utf8'));
const secrets = Object.values(credential).filter(value => typeof value === 'string' && value.length > 3);
function safe(value) {
  let text = String(value || '');
  for (const secret of secrets) text = text.split(secret).join('[redacted]').split(encodeURIComponent(secret)).join('[redacted]');
  return text.replace(/([?&](?:token_auth|form_nonce|nonce|password|form_password)=)[^&\s]*/gi, '$1[redacted]');
}
function address(value) {
  try { const url = new URL(value); return url.origin + url.pathname; } catch (_) { return '[invalid URL]'; }
}
const base = 'https://worldlabourvalues.org/estatisticas/';
const dashboard = base + 'index.php?module=CoreHome&action=index&idSite=2&period=day&date=today#?idSite=2&period=day&date=today&category=Dashboard_Dashboard&subcategory=1';
const report = {site_id: 2, real_http_transport: true, checks: [], failures: [], page_errors: [], http_errors: [], expected_denials: [], request_failures: [], transport_cancellations: 0};
let step = 'inicialização';
function checkpoint(name) {
  step = name;
  console.log('Verificação: ' + name);
  fs.writeFileSync(path.join(campaign, 'results', 'matomo-admin-validation.json'), JSON.stringify({...report, in_progress: name}, null, 2) + '\n');
}
(async () => {
  const browser = await chromium.launch({headless: true, executablePath: '/usr/bin/chromium', args: ['--no-sandbox', '--disable-dev-shm-usage', '--wlv-admin-validation']});
  let context;
  try {
    context = await browser.newContext({locale: 'pt-BR', viewport: {width: 1440, height: 1100}});
    await context.route('**/*', async route => {
      try {
        const response = await route.fetch({timeout: 60000});
        await route.fulfill({response});
      } catch (error) {
        if (/already handled|has been closed|ERR_ABORTED|NS_BINDING_ABORTED/i.test(error.message)) report.transport_cancellations++;
        else report.request_failures.push({url: address(route.request().url()), error: safe(error.message).split('\n')[0]});
        try { await route.abort(); } catch (_) { /* A navegação já pode ter cancelado a requisição. */ }
      }
    });
    const page = await context.newPage();
    page.on('pageerror', error => report.page_errors.push({step, error: safe(error.message), stack: safe(error.stack).split('\n').slice(0, 5)}));
    page.on('response', response => {
      if (response.status() >= 400) {
        const value = {url: address(response.url()), status: response.status(), step};
        const query = new URL(response.url()).searchParams;
        value.module = query.get('module'); value.action = query.get('action');
        if (response.status() === 403 && ['proteção antes do login', 'logout'].includes(step)) report.expected_denials.push(value);
        else report.http_errors.push(value);
      }
    });
    checkpoint('proteção antes do login');
    await page.goto(dashboard, {timeout: 90000});
    await page.locator('#login_form_login').waitFor({state: 'visible', timeout: 60000});
    report.checks.push({name: 'relatório protegido antes do login', passed: true});
    checkpoint('login');
    await page.locator('#login_form_login').fill(credential.username);
    await page.locator('#login_form_password').fill(credential.password);
    await page.locator('#login_form_rememberme').uncheck();
    await page.locator('#login_form_submit').click();
    await page.waitForFunction(() => !document.querySelector('#login_form_login') && Boolean(window.piwik), null, {timeout: 90000});
    await page.goto(dashboard, {timeout: 90000});
    await page.waitForFunction(() => Boolean(window.piwik) && String(window.piwik.idSite) === '2', null, {timeout: 90000});
    await page.waitForLoadState('networkidle', {timeout: 60000});
    // Fecha apenas a sobreposição informativa desta sessão; sem salvar preferências.
    await page.keyboard.press('Escape');
    const modalClose = page.locator('.ui-dialog-titlebar-close:visible');
    if (await modalClose.count()) await modalClose.first().click();
    await page.waitForFunction(() => Array.from(document.querySelectorAll('.widgetTop')).some(node => !!node.getClientRects().length), null, {timeout: 60000});
    report.checks.push({name: 'login real e site de homologação', passed: true});
    checkpoint('dashboard');
    report.dashboard = await page.evaluate(() => ({
      site: String(window.piwik.idSite),
      navigation: Array.from(document.querySelectorAll('a[href^="#?"]')).map(el => ({text: el.textContent.trim(), href: el.getAttribute('href')}))
        .filter(item => item.text).slice(0, 100),
      widgets: Array.from(document.querySelectorAll('.widgetTop')).map(el => ({text: el.textContent.trim(), visible: !!el.getClientRects().length,
        parent: el.parentElement.className, id: el.parentElement.id})),
      headings: Array.from(document.querySelectorAll('h1,h2,h3,.widgetName,.widgetTop')).map(el => el.textContent.trim()).filter(Boolean).slice(0, 60),
      links: Array.from(document.querySelectorAll('a[href]')).map(el => ({text: el.textContent.trim(), href: el.getAttribute('href')}))
        .filter(item => /país|countr|refer|orig|evento|event|pág|page|download|hora|time|sair|logout/i.test(item.text)).slice(0, 50)
    }));
    report.dashboard.headings = report.dashboard.headings.map(safe);
    report.dashboard.links = report.dashboard.links.map(item => ({text: safe(item.text), href: safe(item.href)}));
    report.dashboard.navigation = report.dashboard.navigation.map(item => ({text: safe(item.text), href: safe(item.href)}));
    const screenshot = path.join(campaign, 'results', 'matomo-admin-site2.png');
    await page.screenshot({path: screenshot, fullPage: true, mask: [page.locator('.userMenu, .currentUser')]});
    report.screenshot = screenshot;
    const widgetsPassed = report.dashboard.widgets.length === 11 && report.dashboard.widgets.every(widget => widget.visible && !/Widget não encontrado|Widget not found/i.test(widget.text));
    report.checks.push({name: 'onze widgets configurados renderizam', passed: widgetsPassed});
    if (!widgetsPassed) report.failures.push({step, error: 'Um ou mais widgets não renderizaram.'});
    checkpoint('relatórios');
    report.reports = [];
    const categories = [
      ['países e cidades', 'UserCountry_SubmenuLocations'], ['horários', 'VisitTime_SubmenuTimes'],
      ['origens', 'Referrers_WidgetGetAll'], ['abas', 'Actions_SubmenuPageTitles'],
      ['eventos e duração ativa', 'Events_Events'], ['arquivos exportados', 'customdimension10']
    ];
    let reportNumber = 0;
    for (const [name, category] of categories) {
      checkpoint('relatório: ' + name);
      const link = report.dashboard.navigation.find(item => item.href.includes('subcategory=' + category));
      assert.ok(link, 'Relatório disponível: ' + name);
      await page.mouse.move(0, 0);
      // Documento novo evita desmontar gráficos animados no meio da transição SPA.
      await page.goto(dashboard.split('#')[0] + '&wlv_admin_check=' + (++reportNumber) + link.href, {timeout: 90000});
      await page.waitForLoadState('networkidle', {timeout: 60000});
      await page.keyboard.press('Escape');
      if (await modalClose.count()) await modalClose.first().click();
      await page.waitForFunction(subcategory => {
        const selected = new URLSearchParams(window.location.hash.replace(/^#\?/, '')).get('subcategory');
        const headings = Array.from(document.querySelectorAll('h1,h2,h3,.widgetName')).some(el => el.getClientRects().length && el.textContent.trim());
        const reports = Array.from(document.querySelectorAll('.dataTable,.dataTableGraph,.jqplot-target,canvas')).some(el => el.getClientRects().length);
        return selected === subcategory && headings && reports;
      }, category, {timeout: 60000});
      await page.waitForLoadState('networkidle', {timeout: 60000});
      const state = await page.evaluate(() => ({site: String(window.piwik.idSite),
        headings: Array.from(document.querySelectorAll('h1,h2,h3,.widgetName')).filter(el => el.getClientRects().length).map(el => el.textContent.trim().split('Como podemos melhorar')[0]).filter(Boolean),
        tables: Array.from(document.querySelectorAll('.dataTable')).filter(el => el.getClientRects().length).length,
        charts: Array.from(document.querySelectorAll('.dataTableGraph,.jqplot-target,canvas')).filter(el => el.getClientRects().length).length,
        errors: Array.from(document.querySelectorAll('.notification.error,.pk-emptyDataTable')).filter(el => el.getClientRects().length).map(el => el.textContent.trim())}));
      report.reports.push({name, ...state});
      assert.equal(state.site, '2');
      assert.ok(state.headings.length && (state.tables || state.charts), 'Relatório carregado: ' + name);
      assert.equal(state.errors.filter(text => /exception|error|erro|not found|não encontrado/i.test(text)).length, 0, 'Relatório sem erro: ' + name);
    }
    report.checks.push({name: 'seis áreas de relatórios disponíveis sob /estatisticas/', passed: true});
    // logout é uma ação de sessão, sem alterar configuração ou relatórios.
    checkpoint('logout');
    const logout = page.locator('a[href*="module=Login"][href*="action=logout"]:visible');
    assert.ok(await logout.count() >= 1, 'Um link de logout deve estar disponível.');
    await logout.first().click();
    await page.locator('#login_form_login').waitFor({state: 'visible', timeout: 60000});
    await page.goto(dashboard, {timeout: 90000});
    await page.locator('#login_form_login').waitFor({state: 'visible', timeout: 60000});
    report.checks.push({name: 'logout e relatório novamente protegido', passed: true});
  } catch (error) {
    report.failures.push({step, error: safe(error.message).split('\n').slice(0, 4).join('\n')});
    process.exitCode = 1;
  } finally {
    try { if (context) { await context.unrouteAll({behavior: 'ignoreErrors'}); await context.close(); } }
    finally { await browser.close(); }
    report.passed = !report.failures.length && !report.page_errors.length && !report.http_errors.length && !report.request_failures.length;
    if (!report.passed) process.exitCode = 1;
    fs.writeFileSync(path.join(campaign, 'results', 'matomo-admin-validation.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
  }
})().catch(error => { console.error(safe(error.message).split('\n')[0]); process.exitCode = 1; });
