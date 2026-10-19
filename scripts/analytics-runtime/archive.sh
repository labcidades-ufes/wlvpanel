#!/usr/bin/env bash
set -euo pipefail
exec /usr/bin/flock -n /run/lock/wlv-analytics-archive.lock \
  /usr/bin/docker exec --user www-data wlv-analytics-app php console core:archive \
  --url=https://worldlabourvalues.org/estatisticas/ --concurrent-requests-per-website=1
