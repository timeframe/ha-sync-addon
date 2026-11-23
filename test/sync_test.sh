#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -f "$TMP/uploads" "$TMP/output"; rmdir "$TMP"' EXIT

BASE='[
  {"entity_id":"sensor.timeframe_top_left","state":"home,Home","attributes":{}},
  {"entity_id":"sensor.timeframe_top_right","state":"lightbulb,On","attributes":{}},
  {"entity_id":"sensor.timeframe_weather_status","state":"weather-sunny,Clear","attributes":{}},
  {"entity_id":"sensor.timeframe_daily_event_family","state":"calendar,School","attributes":{}},
  {"entity_id":"media_player.living_room","state":"playing","attributes":{"media_artist":"Artist","media_title":"Track","media_position":1}},
  {"entity_id":"media_player.bedroom","state":"playing","attributes":{"media_title":"Other"}},
  {"entity_id":"weather.home","state":"sunny","attributes":{"apparent_temperature":70,"temperature_unit":"°F"}}
]'

fingerprint() {
  jq -cS '{entities: .}' <<< "$1" | jq -cS -f "$ROOT/display_state.jq"
}

assert_same() {
  local before after
  before="$(fingerprint "$1")" || exit 1
  after="$(fingerprint "$2")" || exit 1
  if [ "$before" != "$after" ]; then
    echo "FAIL: $3 should not change the display fingerprint" >&2
    exit 1
  fi
}

assert_changed() {
  local before after
  before="$(fingerprint "$1")" || exit 1
  after="$(fingerprint "$2")" || exit 1
  if [ "$before" = "$after" ]; then
    echo "FAIL: $3 should change the display fingerprint" >&2
    exit 1
  fi
}

run_case() {
  local name="$1" expected="$2" actual
  : > "$TMP/uploads"
  (
    ITERATION=0
    SUPERVISOR_TOKEN=test
    jq() {
      if [ "${3:-}" = "/data/options.json" ]; then
        case "$2" in
          .api_key) echo test ;;
          .sync_interval_seconds) echo 1 ;;
          .version) echo test ;;
          *) return 1 ;;
        esac
      else
        command jq "$@"
      fi
    }
    curl() {
      local arg payload="" posting=false
      while [ "$#" -gt 0 ]; do
        arg="$1"
        shift
        case "$arg" in
          POST) posting=true ;;
          -d) payload="$1"; shift ;;
        esac
      done
      if [ "$posting" = true ]; then
        command jq -c --argjson iteration "$ITERATION" \
          '. + {iteration: $iteration}' <<< "$payload" >> "$TMP/uploads"
        echo "${CODES[$ITERATION]:-200}"
      else
        echo "${STATES[$ITERATION]}"
      fi
    }
    date() { echo "$(( 1000 + TIMES[ITERATION] ))"; }
    sleep() {
      ITERATION=$(( ITERATION + 1 ))
      if [ "$ITERATION" -ge "${#STATES[@]}" ]; then exit 0; fi
    }
    source "$ROOT/run.sh"
  ) > "$TMP/output" 2>&1 || {
    cat "$TMP/output" >&2
    return 1
  }
  actual="$(jq -sr 'map(.iteration | tostring) | join(",")' "$TMP/uploads")"
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $name: expected uploads at [$expected], got [$actual]" >&2
    cat "$TMP/output" >&2
    exit 1
  fi
  echo "PASS: $name"
}

TRACK="$(jq '.[4].attributes.media_title = "Next track"' <<< "$BASE")"
ARTIST="$(jq '.[4].attributes.media_artist = "Next artist"' <<< "$BASE")"
PAUSED="$(jq '.[4].state = "paused"' <<< "$BASE")"
POSITION="$(jq '.[4].attributes.media_position = 2' <<< "$BASE")"
TEMPERATURE="$(jq '.[6].attributes.apparent_temperature = 71' <<< "$BASE")"
UNSELECTED="$(jq '.[5].attributes.media_title = "Another track"' <<< "$BASE")"

assert_same "$BASE" "$POSITION" "playback position"
assert_same "$BASE" "$UNSELECTED" "unselected player"
assert_same "$BASE" "$(jq '.[0].attributes.updated = "now" | .[4].last_changed = "later"' <<< "$BASE")" "metadata"
assert_same "$BASE" "$(jq '.[0:4] |= reverse' <<< "$BASE")" "status ordering"
assert_same "$BASE" "$(jq '.[6].attributes.apparent_temperature = "70.0"' <<< "$BASE")" "equivalent numeric temperature"
assert_changed "$BASE" "$TRACK" "track"
assert_changed "$BASE" "$ARTIST" "artist"
assert_changed "$BASE" "$PAUSED" "pause"
assert_changed "$BASE" "$TEMPERATURE" "temperature"
assert_changed "$BASE" "$(jq 'map(select(.entity_id != "media_player.living_room"))' <<< "$BASE")" "player removal"
assert_changed "$BASE" "$(jq '. + [{entity_id:"sensor.timeframe_media_player_entity_id",state:"media_player.bedroom"}]' <<< "$BASE")" "player selection"
assert_changed "$BASE" "$(jq 'map(select(.entity_id != "sensor.timeframe_top_left"))' <<< "$BASE")" "status removal"
assert_changed "$BASE" "$(jq '.[6].attributes.temperature_unit = "°C"' <<< "$BASE")" "temperature unit"
assert_changed "$BASE" "$(jq '.[6].attributes.apparent_temperature = "unavailable"' <<< "$BASE")" "temperature unavailable"

OVERRIDDEN="$(jq '. + [
  {entity_id:"sensor.timeframe_weather_feels_like_entity_id",state:"sensor.outside"},
  {entity_id:"sensor.outside",state:"65"}
]' <<< "$BASE")"
assert_changed "$BASE" "$OVERRIDDEN" "referenced temperature"
assert_same "$OVERRIDDEN" "$(jq '.[6].attributes.apparent_temperature = 80' <<< "$OVERRIDDEN")" "overridden weather temperature"
assert_changed "$OVERRIDDEN" "$(jq '.[8].state = "66"' <<< "$OVERRIDDEN")" "referenced temperature change"
assert_changed "$BASE" "$(jq '. + [
  {entity_id:"sensor.timeframe_weather_entity_id",state:"weather.other"},
  {entity_id:"weather.other",attributes:{apparent_temperature:60,temperature_unit:"°F"}}
]' <<< "$BASE")" "weather selection"
echo "PASS: display fingerprints"

CODES=()
STATES=("$BASE" "$TRACK" "$ARTIST" "$PAUSED" "$BASE")
TIMES=(0 1 2 3 4)
run_case "music updates bypass cooldown, including resume" "0,1,2,3,4"

for index in 0 1 2 3; do
  CHANGED="$(jq --argjson index "$index" '.[$index].state = "updated"' <<< "$BASE")"
  STATES=("$BASE" "$CHANGED")
  TIMES=(0 1)
  run_case "status/event surface $index bypasses cooldown" "0,1"
done

STATES=("$BASE" "$TEMPERATURE" "$TEMPERATURE")
TIMES=(0 1 2)
run_case "temperature sends immediately, unchanged data does not" "0,1"

STATES=("$BASE" "$POSITION" "$UNSELECTED" "$POSITION")
TIMES=(0 1 59 60)
run_case "background changes wait for cooldown and send latest snapshot" "0,3"
jq -es '.[-1].entities[4].attributes.media_position == 2' "$TMP/uploads" > /dev/null

STATES=("$BASE" "$POSITION" "$BASE")
TIMES=(0 1 60)
run_case "reverted background changes wait for the heartbeat" "0,2"

STATES=("$BASE" "$POSITION" "$(jq '.[4].attributes.media_title = "New"' <<< "$POSITION")")
TIMES=(0 1 2)
run_case "immediate updates include pending background data" "0,2"
jq -es '.[-1].entities[4].attributes.media_position == 2' "$TMP/uploads" > /dev/null

STATES=("$BASE" "$BASE" "$BASE")
TIMES=(0 60 120)
run_case "unchanged snapshots heartbeat every 60 seconds" "0,1,2"

STATES=("$BASE" "$TRACK" "$ARTIST" "$ARTIST" "$ARTIST")
TIMES=(0 1 2 3 4)
CODES=(200 500 200 200 200)
run_case "failed immediate upload backs off and retries latest state" "0,1,3"
jq -es '.[-1].entities[4].attributes.media_artist == "Next artist"' "$TMP/uploads" > /dev/null

STATES=("$BASE" "$BASE" "$BASE" "$BASE" "$BASE" "$BASE" "$BASE" "$BASE" "$BASE" "$BASE" "$BASE")
TIMES=(0 1 2 3 6 14 30 62 121 122 123)
CODES=(429 429 429 429 429 429 429 429 429 200 200)
run_case "retry backoff grows to 60 seconds" "0,2,4,5,6,7,9"
grep -q 'HTTP 429' "$TMP/output"

STATES=("$BASE" "$BASE" "$BASE" "$TRACK" "$TRACK" "$TRACK")
TIMES=(0 2 6 7 8 9)
CODES=(500 500 200 500 200 200)
run_case "successful upload resets failure backoff" "0,1,2,3,5"

echo "All sync tests passed."
