defmodule ChainKills.Discord.Notifier do
  @moduledoc """
  Sends notifications to Discord as channel messages using a bot token.
  Supports both plain text messages and rich embed messages.
  """
  import Bitwise
  require Logger

  @base_url "https://discord.com/api/channels"

  # Retrieve the channel ID and bot token at runtime.
  defp channel_id do
    Application.get_env(:chainkills, :discord_channel_id)
  end

  defp bot_token do
    Application.get_env(:chainkills, :discord_bot_token)
  end

  defp build_url() do
    id = channel_id()
    if id in [nil, ""] do
      raise "Discord channel ID not configured. Please set :discord_channel_id in your configuration."
    end
    "#{@base_url}/#{id}/messages"
  end

  defp headers() do
    token = bot_token()
    if token in [nil, ""] do
      raise "Discord bot token not configured. Please set :discord_bot_token in your configuration."
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
  Sends a rich embed message for an enriched killmail.
  Expects the enriched killmail (and its nested maps) to have string keys.
  """
  def send_enriched_kill_embed(enriched_kill, kill_id) do
    normalized = normalize_keys(enriched_kill)
    kill_url = "https://zkillboard.com/kill/#{kill_id}/"
    system_name = Map.get(normalized, "system_name", "Unknown System")
    title = "Ship destroyed in #{system_name}"
    description = build_description(normalized)
    total_value = Map.get(normalized, "total_value", 0.0)
    formatted_value = format_isk_value(total_value)

    # Build thumbnail from victim's ship type.
    victim = Map.get(normalized, "victim", %{})
    victim_ship_type = Map.get(victim, "ship_type_id")
    thumbnail_url =
      if victim_ship_type do
        "https://image.eveonline.com/Render/#{victim_ship_type}_128.png"
      else
        nil
      end

    # Determine author icon from the top attacker's corporation (if available).
    attackers = Map.get(normalized, "attackers", [])
    top_attacker =
      case attackers do
        [] -> %{}
        _ -> Enum.max_by(attackers, fn a -> Map.get(a, "damage_done", 0) end)
      end
    corp_id = Map.get(top_attacker, "corporation_id")
    author_icon_url =
      if corp_id,
        do: "https://image.eveonline.com/Corporation/#{corp_id}_64.png",
        else: nil

    author_text = "Kill"
    color = 0x00FF00

    embed =
      %{
        "title" => title,
        "url" => kill_url,
        "description" => description,
        "color" => color,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "footer" => %{"text" => "Value: #{formatted_value}"}
      }
      |> maybe_put("thumbnail", if(thumbnail_url, do: %{"url" => thumbnail_url}))
      |> put_author(author_text, kill_url, author_icon_url)

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

  # Recursively normalize keys in a map to strings.
  defp normalize_keys(value) when is_map(value) do
    for {k, v} <- value, into: %{} do
      key = if is_atom(k), do: Atom.to_string(k), else: k
      {key, normalize_keys(v)}
    end
  end
  defp normalize_keys(value) when is_list(value), do: Enum.map(value, &normalize_keys/1)
  defp normalize_keys(value), do: value


  # Updated build_description: derive fallback values using IDs if names are missing.
  defp build_description(normalized) do
    victim = Map.get(normalized, "victim", %{})
    attackers = Map.get(normalized, "attackers", [])
    final_attacker =
      Enum.find(attackers, fn a -> Map.get(a, "final_blow", false) end) ||
        (if attackers != [], do: Enum.max_by(attackers, fn a -> Map.get(a, "damage_done", 0) end), else: %{})
    top_attacker =
      if attackers != [] do
        Enum.max_by(attackers, fn a -> Map.get(a, "damage_done", 0) end)
      else
        %{}
      end

    # Derive victim values.
    victim_id = Map.get(victim, "character_id", "Unknown")
    victim_name =
      Map.get(victim, "character_name") ||
        "Character #{victim_id}"
    victim_zkill_url =
      Map.get(victim, "zkill_url") ||
        "https://zkillboard.com/character/#{victim_id}/"
    victim_corp = Map.get(victim, "corporation_id", "Unknown")
    victim_group =
      Map.get(victim, "group_name") ||
        "Corp #{victim_corp}"
    victim_ship =
      Map.get(victim, "ship_name") ||
        "Ship #{Map.get(victim, "ship_type_id", "Unknown")}"

    # Derive final attacker values.
    final_attacker_id = Map.get(final_attacker, "character_id", "Unknown")
    final_attacker_name =
      Map.get(final_attacker, "character_name") ||
        "Character #{final_attacker_id}"
    final_attacker_zkill_url =
      Map.get(final_attacker, "zkill_url") ||
        "https://zkillboard.com/character/#{final_attacker_id}/"
    final_attacker_corp = Map.get(final_attacker, "corporation_id", "Unknown")
    final_attacker_group =
      Map.get(final_attacker, "group_name") ||
        "Corp #{final_attacker_corp}"
    final_attacker_ship =
      Map.get(final_attacker, "ship_name") ||
        "Ship #{Map.get(final_attacker, "ship_type_id", "Unknown")}"

    base_desc =
      "**[#{victim_name}](#{victim_zkill_url})(#{victim_group})** lost their **#{victim_ship}** " <>
      "to **[#{final_attacker_name}](#{final_attacker_zkill_url})(#{final_attacker_group})** flying in a **#{final_attacker_ship}**"

    if length(attackers) > 1 do
      top_attacker_id = Map.get(top_attacker, "character_id", "Unknown")
      top_attacker_name =
        Map.get(top_attacker, "character_name") ||
          "Character #{top_attacker_id}"
      top_attacker_zkill_url =
        Map.get(top_attacker, "zkill_url") ||
          "https://zkillboard.com/character/#{top_attacker_id}/"
      top_attacker_corp = Map.get(top_attacker, "corporation_id", "Unknown")
      top_attacker_group =
        Map.get(top_attacker, "group_name") ||
          "Corp #{top_attacker_corp}"
      top_attacker_ship =
        Map.get(top_attacker, "ship_name") ||
          "Ship #{Map.get(top_attacker, "ship_type_id", "Unknown")}"

      base_desc <>
        ", Top Damage was done by **[#{top_attacker_name}](#{top_attacker_zkill_url})(#{top_attacker_group})** " <>
        "flying in a **#{top_attacker_ship}**."
    else
      base_desc <> " solo."
    end
  end

  defp send_payload(payload) do
    url = build_url()
    json_payload = Jason.encode!(payload)

    case HTTPoison.post(url, json_payload, headers()) do
      {:ok, %HTTPoison.Response{status_code: status}} when status in 200..299 ->
        :ok

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.error("Discord API request failed with status #{status}: #{body}")
        {:error, body}

      {:error, err} ->
        Logger.error("Discord API request error: #{inspect(err)}")
        {:error, err}
    end
  end

  # Parses a color string in "#RRGGBB" form into an integer.
  def parse_hex_color(hex_str) do
    with {r, ""} <- Integer.parse(String.slice(hex_str, 1, 2), 16),
         {g, ""} <- Integer.parse(String.slice(hex_str, 3, 2), 16),
         {b, ""} <- Integer.parse(String.slice(hex_str, 5, 2), 16) do
      (r <<< 16) + (g <<< 8) + b
    else
      _ -> 0xFFFFFF
    end
  end

  # Formats an ISK value into a short string.
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
