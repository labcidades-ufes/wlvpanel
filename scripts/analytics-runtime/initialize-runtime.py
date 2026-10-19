#!/usr/bin/env python3
"""Cria estrutura operacional e segredos; não instala nem altera outros serviços."""
import json
import os
from pathlib import Path
import secrets
import shutil

ROOT = Path('/srv/worldlabourvalues-analytics')
SOURCE = Path(__file__).resolve().parent
CREDENTIAL = Path('/home/franklin/.local/share/server-credentials/worldlabourvalues-matomo-admin.json')
if os.geteuid() != 0:
    raise SystemExit('Execute como root.')
if ROOT.exists() or CREDENTIAL.exists():
    raise SystemExit('Destino existente: operação recusada para preservar dados e credenciais.')
ROOT.mkdir(mode=0o750)
for name in ['db', 'html', 'secrets', 'bin', 'backups']:
    (ROOT / name).mkdir(mode=0o700 if name in ['secrets', 'backups'] else 0o750)
for name in ['compose.yaml', 'apache.conf', 'php.ini']:
    shutil.copyfile(SOURCE / name, ROOT / name)
for path in SOURCE.iterdir():
    if path.suffix in ['.php', '.sh', '.py'] and path.name != Path(__file__).name:
        shutil.copyfile(path, ROOT / 'bin' / path.name)
        (ROOT / 'bin' / path.name).chmod(0o644 if path.name == 'local-api.php' else 0o750)
(ROOT / 'bin').chmod(0o755)
db_password = secrets.token_hex(32)
for name, value in [('db-password', db_password), ('db-root-password', secrets.token_hex(32))]:
    path = ROOT / 'secrets' / name
    path.write_text(value + '\n', encoding='utf-8')
    path.chmod(0o600)
admin = {'url': 'https://worldlabourvalues.org/estatisticas/', 'username': 'franklin',
         'password': secrets.token_urlsafe(36), 'email': 'admin@worldlabourvalues.invalid',
         'note': 'Email desativado; endereço reservado, não usado para envio ou recuperação.'}
CREDENTIAL.write_text(json.dumps(admin, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
CREDENTIAL.chmod(0o600)
os.chown(CREDENTIAL, 1003, 1001)
bootstrap = ROOT / 'secrets' / 'bootstrap.json'
bootstrap.write_text(json.dumps({'admin': admin, 'db_password': db_password}), encoding='utf-8')
bootstrap.chmod(0o600)
print(json.dumps({'runtime': str(ROOT), 'credential_file': str(CREDENTIAL), 'secrets_printed': False}))
