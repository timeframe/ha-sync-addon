def present:
  . != null and . != "" and (type != "string" or test("\\S"));

def override($entities; $suffix):
  [$entities[] | select(.entity_id | endswith($suffix))][0].state;

def selected($entities; $suffix; $prefix):
  override($entities; $suffix) as $id |
  if $id | present then
    [$entities[] | select(.entity_id == $id)][0]
  else
    [$entities[] | select(.entity_id | startswith($prefix))][0]
  end;

def numeric:
  tostring | test("^-?[0-9]+(\\.[0-9]+)?$");

.entities as $entities |
selected($entities; "timeframe_media_player_entity_id"; "media_player.") as $player |
selected($entities; "timeframe_weather_entity_id"; "weather.") as $weather |
override($entities; "timeframe_weather_feels_like_entity_id") as $feels_like_id |
[$entities[] | select(.entity_id == $feels_like_id)][0] as $feels_like |
(
  if ($feels_like_id | present) and ($feels_like.state | numeric) then
    $feels_like.state
  else
    $weather.attributes.apparent_temperature
  end
) as $temperature |
{
  status: ([
    $entities[] |
    select(.entity_id | test("^sensor\\.timeframe_(top_left|top_right|weather_status|daily_event)")) |
    select(.state | present) |
    {entity_id, state}
  ] | sort_by(.entity_id)),
  now_playing: (
    if $player == null or $player.state == "paused" or $player.state == "idle" or
        (([$player.attributes.media_artist, $player.attributes.media_title] | any(present)) | not) then
      {}
    else
      {artist: $player.attributes.media_artist, track: $player.attributes.media_title}
    end),
  temperature: (
    if $temperature | numeric then
      {
        value: ($temperature | tonumber | . + 0),
        unit: (if $weather.attributes.temperature_unit == "°C" then "C" else "F" end)
      }
    else
      null
    end)
}
