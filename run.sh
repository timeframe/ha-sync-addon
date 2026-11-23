#!/bin/bash
set -e

API_KEY="$(jq -r '.api_key' /data/options.json)"
SYNC_INTERVAL="$(jq -r '.sync_interval_seconds' /data/options.json)"
BACKGROUND_COOLDOWN=60
DISPLAY_STATE_FILTER="$(dirname "${BASH_SOURCE[0]}")/display_state.jq"
CLOUD_URL="https://www.timeframe.app/api/ha_sync"
HA_TOKEN="${SUPERVISOR_TOKEN}"
HA_API="http://supervisor/core/api"
ADDON_VERSION=$(jq -r '.version' /data/options.json 2>/dev/null || jq -r '.version' /config.json 2>/dev/null || echo "unknown")

if [ -z "$API_KEY" ]; then
  echo "[FATAL] No API key configured. Generate one at https://www.timeframe.app/profile"
  exit 1
fi

echo "[INFO] Timeframe HA Sync starting (poll: ${SYNC_INTERVAL}s, background cooldown: ${BACKGROUND_COOLDOWN}s, display changes: immediate)"

LAST_DISPLAY_HASH=""
LAST_SEND=0
NEXT_RETRY=0
RETRY_DELAY=2

while true; do
  # Fetch all entities from HA
  RESPONSE=$(curl -sf \
    -H "Authorization: Bearer ${HA_TOKEN}" \
    -H "Content-Type: application/json" \
    "${HA_API}/states" 2>&1) || {
    echo "[WARNING] Failed to fetch HA states, retrying in ${SYNC_INTERVAL}s"
    sleep "${SYNC_INTERVAL}"
    continue
  }

  # Filter matching entities and resolve referenced entity IDs from config sensors
  PAYLOAD=$(echo "$RESPONSE" | jq -c --arg v "$ADDON_VERSION" '
    . as $all |
    [$all[] | select(.entity_id | test("^sensor\\.timeframe_(media_player|weather|weather_feels_like)_entity_id$")) | .state | select(. != "" and . != "unknown" and . != "unavailable")] as $refs |
    {version: $v, entities: [$all[] | select(
      (.entity_id | (startswith("timeframe_") or startswith("weather.") or startswith("media_player.") or test("\\btimeframe_")))
      or (.entity_id as $eid | ($refs | any(. == $eid)))
    ) | {entity_id, state, attributes: .attributes, last_changed: .last_changed}]}
  ')

  ENTITY_COUNT=$(echo "$PAYLOAD" | jq '.entities | length')

  if [ "$ENTITY_COUNT" -eq 0 ]; then
    echo "[DEBUG] No matching entities found, skipping sync"
    sleep "${SYNC_INTERVAL}"
    continue
  fi

  if ! DISPLAY_STATE=$(echo "$PAYLOAD" | jq -cS -f "$DISPLAY_STATE_FILTER"); then
    echo "[ERROR] Failed to determine display changes, retrying in ${SYNC_INTERVAL}s"
    sleep "${SYNC_INTERVAL}"
    continue
  fi
  DISPLAY_HASH=$(echo "$DISPLAY_STATE" | md5sum | cut -d' ' -f1)
  NOW=$(date +%s)
  ELAPSED=$(( NOW - LAST_SEND ))

  # Display changes bypass the background cooldown, but not failure backoff.
  if [ "$NOW" -ge "$NEXT_RETRY" ] &&
      { [ "$DISPLAY_HASH" != "$LAST_DISPLAY_HASH" ] || [ "$ELAPSED" -ge "$BACKGROUND_COOLDOWN" ]; }; then
    HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
      -X POST \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      "${CLOUD_URL}") || HTTP_CODE="000"
    NOW=$(date +%s)

    if [ "$HTTP_CODE" = "200" ]; then
      echo "[INFO] Synced ${ENTITY_COUNT} entities to Timeframe"
      LAST_DISPLAY_HASH="$DISPLAY_HASH"
      LAST_SEND="$NOW"
      NEXT_RETRY=0
      RETRY_DELAY=2
    else
      NEXT_RETRY=$(( NOW + RETRY_DELAY ))
      echo "[WARNING] Sync failed (HTTP ${HTTP_CODE}), retrying in ${RETRY_DELAY}s"
      RETRY_DELAY=$(( RETRY_DELAY * 2 ))
      if [ "$RETRY_DELAY" -gt 60 ]; then RETRY_DELAY=60; fi
    fi
  fi

  sleep "${SYNC_INTERVAL}"
done
