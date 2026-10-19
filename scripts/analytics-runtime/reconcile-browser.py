#!/usr/bin/env python3
"""Confere eventos do ensaio site 2 no Matomo, sem gravar IDs de visitantes."""
import collections
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlparse, parse_qs

repo = Path(__file__).resolve().parents[2]
campaign = Path(os.environ['WLV_CAMPAIGN_ROOT']).resolve(strict=True)
assert campaign.parent == repo / 'temp'
assert json.loads((campaign / '.campaign.json').read_text())['status'] == 'active'
evidence = Path(sys.argv[1]).resolve(strict=True)
assert evidence.is_relative_to(campaign / 'results')
browser = json.loads(evidence.read_text())
assert browser['status'] == 'passed'
marker = browser['marker']
assert marker.startswith('analytics-') and all(c.isalnum() or c == '-' for c in marker)


def api(parameters):
    command = ['sudo', '-S', '-p', '', 'python3', str(repo / 'scripts/analytics-runtime/query-api.py'),
               json.dumps(parameters)]
    credential = Path('/home/franklin/.local/share/server-credentials/salas.grupo.pro.br.sudo')
    with credential.open('rb') as stream:
        response = subprocess.run(command, stdin=stream, capture_output=True, check=True)
    return json.loads(response.stdout)


visits = api({'method': 'Live.getLastVisitsDetails', 'idSite': 2, 'period': 'day',
              'date': 'today', 'filter_limit': 500, 'segment': 'referrerName=@' + marker})
assert isinstance(visits, list) and visits
assert all(str(visit['idSite']) == '2' for visit in visits)
visits = [visit for visit in visits if str(visit.get('referrerName', '')).startswith(marker)]
actions = [action for visit in visits for action in visit['actionDetails']]


def signature(action):
    if action.get('type') == 'event':
        return ('event', action.get('eventCategory'), action.get('eventAction'),
                action.get('eventName'), round(float(action.get('eventValue', 0)), 3),
                tuple((key, str(value)) for key, value in sorted(action.items())
                      if key.startswith('dimension') and value is not None))
    return ('page', parse_qs(urlparse(action.get('url', '')).query).get('tab', [''])[0])


actual = collections.Counter(signature(action) for action in actions)
expected = collections.Counter()
for record in browser['requests']:
    if record.get('httpStatus') != 204 or record.get('blocked'):
        continue
    assert str(record['site']) == '2'
    event = record.get('event')
    if event:
        expected[('event', event['category'], event['action'], event['name'],
                  round(float(event['value']), 3), tuple(sorted(record['dimensions'].items())))] += 1
    else:
        expected[('page', record['tab'])] += 1
missing = expected - actual
assert not missing, 'Alguns eventos HTTP204 não constam do registro: ' + str(missing)
download_actions = [action for action in actions if action.get('eventCategory') == 'Download']
generated = [action for action in download_actions if action.get('eventAction') == 'generated']
assert len({action.get('dimension1') for action in generated}) == 6
assert all(action.get('dimension10') == action.get('eventName') for action in download_actions)
assert all(action.get('dimension9', '').startswith('release-') for action in download_actions)
tabs = {signature(action)[1] for action in actions if action.get('type') == 'action'}
assert tabs == {'about', 'map', 'country', 'indicators', 'trade', 'download', 'publications'}
seconds = collections.defaultdict(float)
for action in actions:
    if action.get('eventCategory') == 'Engagement' and action.get('eventAction') == 'active_seconds':
        seconds[action['eventName']] += float(action['eventValue'])
assert seconds['map'] >= 15
assert all(not visit.get('userId') for visit in visits)
record = {'status': 'passed', 'checked_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'marker': marker, 'site_id': 2, 'browser_evidence': str(evidence.relative_to(campaign)),
          'visits': len(visits), 'received_actions': len(actions),
          'http204_events_reconciled': sum(expected.values()), 'tabs': sorted(tabs),
          'generated_downloads': [{'kind': action['dimension1'], 'filename': action['dimension10'],
                                  'release': action['dimension9']} for action in generated],
          'active_seconds_by_tab': {tab: round(value, 3) for tab, value in sorted(seconds.items())},
          'identifiers_stored_in_evidence': False}
destination = evidence.parent / 'matomo-reconciliation.json'
destination.write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(record, ensure_ascii=False, indent=2))
