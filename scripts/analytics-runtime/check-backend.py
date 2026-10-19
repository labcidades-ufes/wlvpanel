#!/usr/bin/env python3
"""Valida login/API HTTP e privacidade com eventos identificáveis só no site 2."""
import hashlib
import json
from pathlib import Path
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = 'http://127.0.0.1:8093/'
HEADERS = {'Host': 'worldlabourvalues.org', 'X-Forwarded-Host': 'worldlabourvalues.org',
           'X-Forwarded-Proto': 'https', 'X-Forwarded-Uri': '/estatisticas',
           'X-Forwarded-For': '8.8.8.8',
           'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/140.0.0.0 Safari/537.36'}

def post(path, data, extra=None):
    headers = HEADERS | (extra or {})
    request = urllib.request.Request(ROOT + path, urllib.parse.urlencode(data).encode(), headers)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.read(), response.headers
    except urllib.error.HTTPError as error:
        if error.code == 401:
            return error.read(), error.headers
        raise

def api(method, token=None, **kwargs):
    request = {'module': 'API', 'method': method, 'format': 'JSON'} | kwargs
    if token:
        request['token_auth'] = token
    content, _ = post('index.php', request)
    return json.loads(content)

credential = json.loads(Path('/home/franklin/.local/share/server-credentials/worldlabourvalues-matomo-admin.json').read_text())
token = api('UsersManager.createAppSpecificTokenAuth', userLogin=credential['username'],
            passwordConfirmation=credential['password'], description='Verificação local WLV (expira em 1 hora)',
            expireHours=1, secureOnly=1)
if isinstance(token, dict) and 'value' in token:
    token = token['value']
if not isinstance(token, str) or len(token) < 32:
    raise RuntimeError('Autenticação API falhou; resposta omitida por segurança.')
sites = api('SitesManager.getAllSitesId', token)
assert [int(x) for x in sites] == [1, 2], sites
anonymous = api('VisitsSummary.get', idSite=1, period='day', date='today')
assert anonymous.get('result') == 'error'
visitor = secrets.token_hex(8)
blocked = secrets.token_hex(8)
marker = 'WLV runtime check ' + secrets.token_hex(4)
base = {'idsite': 2, 'rec': 1, 'apiv': 1, 'url': 'http://127.0.0.1:8094/?tab=about',
        'action_name': marker, 'cookie': 0, 'send_image': 0, '_id': visitor,
        'e_c': 'RuntimeCheck', 'e_a': 'privacy', 'e_n': marker, 'dimension1': 'RuntimeCheck',
        'dimension10': 'runtime-check.txt'}
_, response_headers = post('matomo.php', base)
assert 'Set-Cookie' not in response_headers
post('matomo.php', base | {'_id': blocked, 'action_name': marker + ' DNT', 'e_n': marker + ' DNT'}, {'DNT': '1'})
time.sleep(1)
visits = api('Live.getLastVisitsDetails', token, idSite=2, period='day', date='today', filter_limit=100)
tracked = [v for v in visits if any(a.get('eventName') == marker for a in v.get('actionDetails', []))]
assert len(tracked) == 1
assert tracked[0]['visitIp'] == '8.8.0.0'
assert tracked[0].get('countryCode') == 'us'
assert not any(a.get('eventName') == marker + ' DNT' for v in visits for a in v.get('actionDetails', [])), 'DNT não respeitado'
assert any(a.get('customDimensions') or a.get('dimension1') for a in tracked[0]['actionDetails']), 'Dimensões não recebidas'
report = {'sites': sites, 'admin_http_api_authenticated': True, 'anonymous_reports_denied': True,
          'collector_sets_cookies': False, 'ip_masked': tracked[0]['visitIp'],
          'geo_country': tracked[0]['countryCode'], 'geo_city': tracked[0].get('city'),
          'dnt_requests_not_recorded': True, 'custom_dimensions_received': True,
          'test_site': 2, 'marker': marker, 'token_persisted': False}
print(json.dumps(report, ensure_ascii=False, indent=2))
