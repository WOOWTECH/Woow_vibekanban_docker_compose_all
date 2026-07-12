#!/usr/bin/env bash
# P3: 依正確順序啟動 stack。
# podman-compose 1.0.6 的 depends_on healthcheck 條件不可靠,必須手動排序:
#   db → remote-server(跑 migration + 建 electric_sync role)→ electric + relay。
# 順序錯 = electric 連不上 electric_sync role 直接炸。
set -euo pipefail
source "$(dirname "$0")/deploy.env"
cd "$STACK_DIR"

compose() { podman-compose -f docker-compose.yml "$@"; }

wait_healthy() {
  local name="$1" tries="${2:-60}"
  echo -n "等待 $name healthy "
  for i in $(seq 1 "$tries"); do
    st=$(podman inspect --format '{{.State.Health.Status}}' "$name" 2>/dev/null || echo "n/a")
    [ "$st" = "healthy" ] && { echo " OK"; return 0; }
    echo -n "."; sleep 3
  done
  echo " TIMEOUT (status=$st)"; return 1
}

PROJ=$(basename "$STACK_DIR")

echo "1) postgres"
compose up -d remote-db
wait_healthy "${PROJ}_remote-db_1" 40

echo "2) remote-server(migration + electric_sync)"
compose up -d remote-server
wait_healthy "${PROJ}_remote-server_1" 60

echo "3) electric + relay-server"
compose up -d electric relay-server

echo "---- 現況 ----"
compose ps
