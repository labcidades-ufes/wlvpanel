#!/usr/bin/env python3
"""Backup diário privado, com retenção de sete dias, apenas desta instalação."""
import datetime as dt
import gzip
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile

ROOT = Path('/srv/worldlabourvalues-analytics')
BACKUPS = ROOT / 'backups'
if os.geteuid() != 0 or ROOT.is_symlink() or BACKUPS.is_symlink():
    raise SystemExit('Execute como root em caminhos operacionais reais.')
os.umask(0o077)
now = dt.datetime.now(dt.timezone.utc)
dest = BACKUPS / now.strftime('%Y%m%dT%H%M%SZ')
dest.mkdir(mode=0o700)
command = ['docker', 'exec', 'wlv-analytics-db', 'sh', '-c',
           'export MYSQL_PWD="$(cat /run/secrets/db-password)"; exec mariadb-dump --user=matomo --single-transaction --quick --skip-lock-tables matomo']
with gzip.open(dest / 'matomo.sql.gz', 'wb') as output:
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    while chunk := process.stdout.read(1024 * 1024):
        output.write(chunk)
    error = process.stderr.read()
    if process.wait():
        raise RuntimeError('Falha do dump; backup incompleto preservado para diagnóstico.')
with tarfile.open(dest / 'configuration.tar.gz', 'w:gz') as archive:
    for relative in ['compose.yaml', 'apache.conf', 'php.ini', 'bin', 'secrets', 'html/config']:
        archive.add(ROOT / relative, arcname=relative, recursive=True)
(dest / 'complete.json').write_text(json.dumps({'created_utc': now.isoformat(), 'retention_days': 7, 'database_consistent_snapshot': True}) + '\n')
# Remove somente backups completos, antigos e reconhecidos desta instalação.
for old in BACKUPS.iterdir():
    if old.is_symlink() or not re.fullmatch(r'\d{8}T\d{6}Z', old.name) or not old.is_dir():
        continue
    date = dt.datetime.strptime(old.name, '%Y%m%dT%H%M%SZ').replace(tzinfo=dt.timezone.utc)
    if (now - date).total_seconds() <= 7 * 86400:
        continue
    expected = {'matomo.sql.gz', 'configuration.tar.gz', 'complete.json'}
    contents = list(old.iterdir())
    if {p.name for p in contents} == expected and all(p.is_file() and not p.is_symlink() for p in contents):
        for file in contents:
            file.unlink()
        old.rmdir()
print(json.dumps({'backup': str(dest), 'complete': True, 'retention_days': 7}))
