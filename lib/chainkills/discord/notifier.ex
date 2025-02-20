defmodule ChainKills.Discord.Notifier do
  @moduledoc """
  Sends notifications to Discord as channel messages using a bot token.
  Supports both plain text messages and rich embed messages.
  """
  import Bitwise
  require Logger

  @base_url "https://discord.com/api/channels"

  defp channel_id do
    Application.get_env(:chainkills, :discord_channel_id)
  end

  defp bot_token do
    Application.get_env(:chainkills, :discord_bot_token)
  end

  defp build_url() do
    id = channel_id()
    if id in [nil, ""] do
      raise "Discord channel ID not configured. Set :discord_channel_id in config."
    end
    "#{@base_url}/#{id}/messages"
  end

  defp headers() do
    token = bot_token()
    if token in [nil, ""] do
      raise "Discord bot token not configured. Set :discord_bot_token in config."
    end
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bot #{token}"}
    ]
  end

  @doc """
  Sends a plain text message to Discord.
  """
  def send_message(message) when is_binary(message) do
    payload = %{
      "content" => message,
      "embeds" => []
    }
    send_payload(payload)
  end

  @doc """
  Sends a basic embed message to Discord.
  """
  def send_embed(title, description, url \\ nil, color \\ 0x00FF00) do
    embed = %{
      "title" => title,
      "description" => description,
      "color" => color,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    embed = if url, do: Map.put(embed, "url", url), else: embed
    payload = %{"embeds" => [embed]}
    send_payload(payload)
  end

  @doc """
  Sends a richer embed message for an enriched killmail.
  Expects the enriched killmail to have string keys.
  """
  def send_enriched_kill_embed(enriched_kill, kill_id) do
    normalized = normalize_keys(enriched_kill)
    kill_url = "https://zkillboard.com/kill/#{kill_id}/"
    system_name = Map.get(normalized, "system_name", "Unknown System")
    title = "Ship destroyed in #{system_name}"
    description = build_description(normalized)
    total_value = Map.get(normalized, "total_value", 0.0)
    formatted_value = format_isk_value(total_value)

    # Build a possible thumbnail from the victim’s ship
    victim = Map.get(normalized, "victim", %{})
    victim_ship_type = Map.get(victim, "ship_type_id")

    thumbnail_url =
      if victim_ship_type do
        "https://image.eveonline.com/Render/#{victim_ship_type}_128.png"
      end

    # Author icon from top attacker’s corp if possible
    attackers = Map.get(normalized, "attackers", [])
    top_attacker =
      case attackers do
        [] -> %{}
        _ -> Enum.max_by(attackers, fn a -> Map.get(a, "damage_done", 0) end)
      end

    corp_id = Map.get(top_attacker, "corporation_id")
    author_icon_url =
      if corp_id do
        "https://image.eveonline.com/Corporation/#{corp_id}_64.png"
      end

    embed =
      %{
        "title" => title,
        "url" => kill_url,
        "description" => description,
        "color" => 0x00FF00,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "footer" => %{"text" => "Value: #{formatted_value}"}
      }
      |> maybe_put("thumbnail", if(thumbnail_url, do: %{"url" => thumbnail_url}))
      |> put_author("Kill", kill_url, author_icon_url)

    payload = %{"embeds" => [embed]}
    send_payload(payload)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp put_author(embed, author_name, url, nil) do
    Map.put(embed, "author", %{"name" => author_name, "url" => url})
  end

  defp put_author(embed, author_name, url, author_icon_url) do
    Map.put(embed, "author", %{"name" => author_name, "url" => url, "icon_url" => author_icon_url})
  end

  # Recursively normalize keys
  defp normalize_keys(value) when is_map(value) do
    for {k, v} <- value, into: %{} do
      key = if is_atom(k), do: Atom.to_string(k), else: k
      {key, normalize_keys(v)}
    end
  end

  defp normalize_keys(value) when is_list(value),
    do: Enum.map(value, &normalize_keys/1)

  defp normalize_keys(value),
    do: value

  defp build_description(normalized) do
    victim = Map.get(normalized, "victim", %{})
    attackers = Map.get(normalized, "attackers", [])

    final_attacker = get_final_attacker(attackers)
    top_attacker = get_top_attacker(attackers)

    victim_data = extract_entity(victim, "Character")
    final_data = extract_entity(final_attacker, "Character")

    base_desc =
      "**[#{victim_data.name}](#{victim_data.zkill_url})(#{victim_data.group})** " <>
      "lost their **#{victim_data.ship}** to **[#{final_data.name}](#{final_data.zkill_url})(#{final_data.group})** " <>
      "flying in a **#{final_data.ship}**"

    cond do
      length(attackers) > 1 ->
        top_data = extract_entity(top_attacker, "Character")
        base_desc <>
          ", Top Damage by **[#{top_data.name}](#{top_data.zkill_url})(#{top_data.group})** " <>
          "flying a **#{top_data.ship}**."

      length(attackers) == 1 ->
        base_desc <> " (solo)."

      true ->
        base_desc <> "."
    end
  end

  defp get_final_attacker(attackers) when is_list(attackers) do
    Enum.find(attackers, fn a -> Map.get(a, "final_blow", false) end) ||
      if attackers != [], do: Enum.max_by(attackers, &(&1["damage_done"] || 0)), else: %{}
  end

  defp get_top_attacker(attackers) when is_list(attackers) do
    if attackers == [] do
      %{}
    else
      Enum.max_by(attackers, fn a -> Map.get(a, "damage_done", 0) end)
    end
  end

  defp extract_entity(entity, default_prefix) when is_map(entity) do
    character_id = Map.get(entity, "character_id") || "Unknown"
    name = Map.get(entity, "character_name") || "#{default_prefix} #{character_id}"
    zkill_url = "https://zkillboard.com/character/#{character_id}/"
    corp_id = Map.get(entity, "corporation_id") || "Unknown"
    group = Map.get(entity, "group_name") || "Corp #{corp_id}"
    ship = Map.get(entity, "ship_name") || "Ship #{Map.get(entity, "ship_type_id", "Unknown")}"

    %{
      id: character_id,
      name: name,
      zkill_url: zkill_url,
      group: group,
      ship: ship
    }
  end

  defp send_payload(payload) do
    url = build_url()
    json_payload = Jason.encode!(payload)

    case HTTPoison.post(url, json_payload, headers()) do
      {:ok, %HTTPoison.Response{status_code: code}} when code in 200..299 ->
        :ok
      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("Discord API request failed (status #{code}): #{body}")
        {:error, body}
      {:error, err} ->
        Logger.error("Discord API request error: #{inspect(err)}")
        {:error, err}
    end
  end

  def parse_hex_color("#" <> hex_str) when byte_size(hex_str) == 6 do
    with {r, ""} <- Integer.parse(String.slice(hex_str, 0, 2), 16),
         {g, ""} <- Integer.parse(String.slice(hex_str, 2, 2), 16),
         {b, ""} <- Integer.parse(String.slice(hex_str, 4, 2), 16)
    do
      (r <<< 16) + (g <<< 8) + b
    else
      _ -> 0xFFFFFF
    end
  end

  def parse_hex_color(_), do: 0xFFFFFF

  @doc """
  Formats an ISK value (float) into short string (e.g., "123.4m ISK").
  """
  def format_isk_value(amount) when is_number(amount) do
    cond do
      amount < 1_000_000 ->
        "<1 M ISK"
      amount < 1_000_000_000 ->
        millions = amount / 1_000_000
        :io_lib.format("~.2fm ISK", [millions]) |> List.to_string()
      amount < 1_000_000_000_000 ->
        billions = amount / 1_000_000_000
        :io_lib.format("~.2fb ISK", [billions]) |> List.to_string()
      true ->
        trillions = amount / 1_000_000_000_000
        :io_lib.format("~.2ft ISK", [trillions]) |> List.to_string()
    end
  end
  def format_isk_value(_), do: "N/A"

  @doc """
  Closes the notifier (if any cleanup is needed).
  """
  def close do
    :ok
  end
end
