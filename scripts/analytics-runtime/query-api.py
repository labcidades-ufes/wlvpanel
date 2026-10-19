#!/usr/bin/env python3
"""Consulta administrativa local. Não grava nem imprime tokens de autenticação."""
import json
import os
import re
import subprocess
import sys

if os.geteuid() != 0:
    raise SystemExit('Execute com sudo; o acesso ao Docker é administrativo.')
parameters = json.loads(sys.argv[1])
if not isinstance(parameters, dict) or 'method' not in parameters:
    raise SystemExit('Informe um objeto JSON com method e os parâmetros da API Matomo.')
if not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*\.get[A-Za-z0-9]+', parameters['method']) or 'token' in parameters['method'].lower() or 'token_auth' in parameters:
    raise SystemExit('Este helper aceita somente métodos de consulta sem tokens.')
result = subprocess.run(['docker', 'exec', '--user', 'www-data', '-i', 'wlv-analytics-app', 'php', '/opt/wlv-analytics/local-api.php'],
                        input=json.dumps(parameters).encode(), check=True, capture_output=True)
sys.stdout.buffer.write(result.stdout)
