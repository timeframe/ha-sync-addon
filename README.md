# Timeframe HA Sync Addon

A minimal Home Assistant addon that syncs `timeframe_*`, `weather.*`, and `media_player.*` entities to [Timeframe](https://www.timeframe.app).

## Setup

1. In Timeframe, go to your [Profile](https://www.timeframe.app/profile) and copy the **Home Assistant Sync API Key** for your location
2. Install this addon in Home Assistant
3. Configure the addon with your API key
4. Start the addon

## Configuration

| Option | Description | Default |
|--------|-------------|---------|
| `api_key` | API key from your Timeframe profile page | *required* |
| `sync_interval_seconds` | How often to poll HA for changes (seconds) | `1` |

To protect the upstream API, syncs are debounced to at most once per 60 seconds when data changes.

## How it works

The addon polls Home Assistant for all entities matching `timeframe_*`, `weather.*`, or `media_player.*` and sends their current state to the Timeframe cloud API. Only the latest sync data is stored.

### Configuration entities

You can create these optional `sensor` entities in Home Assistant (e.g. via template sensors or helpers) to control which entities Timeframe uses:

| Entity ID | Default behavior | Description |
|-----------|-----------------|-------------|
| `sensor.timeframe_media_player_entity_id` | Uses the first `media_player.*` entity | Set the state to a specific media player entity ID (e.g. `media_player.living_room`) to control which player's now-playing info is shown. |
| `sensor.timeframe_weather_entity_id` | Uses the first `weather.*` entity | Set the state to a specific weather entity ID (e.g. `weather.home`) to control which weather entity provides forecasts. |
| `sensor.timeframe_weather_feels_like_entity_id` | Uses `apparent_temperature` from the weather entity | Set the state to a specific sensor entity ID to override the feels-like temperature display. |

When any of these config sensors exist and their state is a valid entity ID, the referenced entity is automatically included in the sync payload.

## Resource usage

This addon is designed to be extremely lightweight — it's a single shell script using `curl` and `jq` with no runtime dependencies.
