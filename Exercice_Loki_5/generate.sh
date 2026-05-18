#!/bin/bash
cd ~/tp-observabilite/Exercice_Loki_5
while true; do
  STATUS=$(shuf -n1 -e 200 200 200 404 500 503)
  LEVEL=$([ "$STATUS" = "200" ] && echo "info" || echo "error")
  METHOD=$(shuf -n1 -e GET POST PUT)
  ENDPOINT=$(shuf -n1 -e /api/users /api/orders /api/products)
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"timestamp":"%s","level":"%s","msg":"HTTP/1.1 %s %s","status":%s,"service":"api"}\n' \
    "$TS" "$LEVEL" "$METHOD" "$ENDPOINT" "$STATUS" >> logs/apps/access.log
  sleep 1
done
