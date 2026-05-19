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
| `sync_interval_seconds` | How often to sync entities (seconds) | `5` |

## How it works

The addon polls Home Assistant for all entities matching `timeframe_*`, `weather.*`, or `media_player.*` and sends their current state to the Timeframe cloud API. Only the latest sync data is stored.

## Resource usage

This addon is designed to be extremely lightweight — it's a single shell script using `curl` and `jq` with no runtime dependencies.
