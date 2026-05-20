#!/usr/bin/with-contenv bashio
set -e

API_KEY="$(bashio::config 'api_key')"
SYNC_INTERVAL="$(bashio::config 'sync_interval_seconds')"
DEBOUNCE=60
CLOUD_URL="https://www.timeframe.app/api/ha_sync"
HA_TOKEN="${SUPERVISOR_TOKEN}"
HA_API="http://supervisor/core/api"
ADDON_VERSION=$(jq -r '.version' /data/options.json 2>/dev/null || jq -r '.version' /config.json 2>/dev/null || echo "unknown")

if [ -z "$API_KEY" ]; then
  bashio::log.fatal "No API key configured. Generate one at https://www.timeframe.app/profile"
  exit 1
fi

bashio::log.info "Timeframe HA Sync starting (poll: ${SYNC_INTERVAL}s, debounce: ${DEBOUNCE}s)"

LAST_HASH=""
LAST_SEND=0
DIRTY=false

while true; do
  # Fetch all entities from HA
  RESPONSE=$(curl -sf \
    -H "Authorization: Bearer ${HA_TOKEN}" \
    -H "Content-Type: application/json" \
    "${HA_API}/states" 2>&1) || {
    bashio::log.warning "Failed to fetch HA states, retrying in ${SYNC_INTERVAL}s"
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
    bashio::log.debug "No matching entities found, skipping sync"
    sleep "${SYNC_INTERVAL}"
    continue
  fi

  # Debounce: only send if data changed and cooldown has elapsed
  HASH=$(echo "$PAYLOAD" | md5sum | cut -d' ' -f1)
  NOW=$(date +%s)
  ELAPSED=$(( NOW - LAST_SEND ))

  if [ "$HASH" != "$LAST_HASH" ]; then
    DIRTY=true
  fi

  if [ "$DIRTY" = true ] && [ "$ELAPSED" -ge "$DEBOUNCE" ]; then
    HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" \
      -X POST \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      "${CLOUD_URL}" 2>&1) || HTTP_CODE="000"

    if [ "$HTTP_CODE" = "200" ]; then
      bashio::log.info "Synced ${ENTITY_COUNT} entities to Timeframe"
      LAST_HASH="$HASH"
      LAST_SEND="$NOW"
      DIRTY=false
    else
      bashio::log.warning "Sync failed (HTTP ${HTTP_CODE}), will retry"
    fi
  fi

  sleep "${SYNC_INTERVAL}"
done
