#!/usr/bin/with-contenv bashio
set -e

API_KEY="$(bashio::config 'api_key')"
SYNC_INTERVAL="$(bashio::config 'sync_interval_seconds')"
CLOUD_URL="https://www.timeframe.app/api/ha_sync"
HA_TOKEN="${SUPERVISOR_TOKEN}"
HA_API="http://supervisor/core/api"

if [ -z "$API_KEY" ]; then
  bashio::log.fatal "No API key configured. Generate one at https://www.timeframe.app/profile"
  exit 1
fi

bashio::log.info "Timeframe HA Sync starting (interval: ${SYNC_INTERVAL}s)"

while true; do
  # Fetch all entities from HA, filter to timeframe_*, weather.*, and media_player.*
  RESPONSE=$(curl -sf \
    -H "Authorization: Bearer ${HA_TOKEN}" \
    -H "Content-Type: application/json" \
    "${HA_API}/states" 2>&1) || {
    bashio::log.warning "Failed to fetch HA states, retrying in ${SYNC_INTERVAL}s"
    sleep "${SYNC_INTERVAL}"
    continue
  }

  # Filter entities matching timeframe_*, weather.*, or media_player.* prefixes
  PAYLOAD=$(echo "$RESPONSE" | jq -c '{entities: [.[] | select(.entity_id | (startswith("timeframe_") or startswith("weather.") or startswith("media_player."))) | {entity_id, state, attributes: .attributes, last_changed: .last_changed}]}')

  ENTITY_COUNT=$(echo "$PAYLOAD" | jq '.entities | length')

  if [ "$ENTITY_COUNT" -eq 0 ]; then
    bashio::log.debug "No matching entities found, skipping sync"
    sleep "${SYNC_INTERVAL}"
    continue
  fi

  # Send to Timeframe cloud
  HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "${CLOUD_URL}" 2>&1) || HTTP_CODE="000"

  if [ "$HTTP_CODE" = "200" ]; then
    bashio::log.info "Synced ${ENTITY_COUNT} entities to Timeframe"
  else
    bashio::log.warning "Sync failed (HTTP ${HTTP_CODE}), retrying in ${SYNC_INTERVAL}s"
  fi

  sleep "${SYNC_INTERVAL}"
done
