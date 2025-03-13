defmodule WandererNotifier.Discord.Notifier do
  @moduledoc """
  Sends notifications to Discord as channel messages using a bot token.
  Supports plain text messages and rich embed messages.
  """
  require Logger
  alias WandererNotifier.Http.Client, as: HttpClient
  alias WandererNotifier.Helpers.CacheHelpers

  # Use a runtime environment check instead of compile-time
  defp env do
    Application.get_env(:wanderer_notifier, :env, :prod)
  end

  @base_url "https://discord.com/api/channels"
  @verbose_logging false  # Set to true to enable verbose logging

  # Define behavior for mocking in tests
  @callback send_message(String.t()) :: :ok | {:error, any()}
  @callback send_embed(String.t(), String.t(), any(), integer()) :: :ok | {:error, any()}

  # Retrieve the channel ID and bot token at runtime.
  defp channel_id do
    Application.get_env(:wanderer_notifier, :discord_channel_id)
  end

  defp bot_token do
    Application.get_env(:wanderer_notifier, :discord_bot_token)
  end

  defp build_url do
    id = channel_id()

    if id in [nil, ""] and env() != :test do
      raise "Discord channel ID not configured. Please set :discord_channel_id in your configuration."
    end

    "#{@base_url}/#{id}/messages"
  end

  defp headers do
    token = bot_token()

    if token in [nil, ""] and env() != :test do
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
    if env() == :test do
      if @verbose_logging, do: Logger.info("DISCORD MOCK: #{message}")
      :ok
    else
      # Track notification errors (ignore if failure)
      try do
        WandererNotifier.Stats.increment(:errors)
      rescue
        _ -> :ok
      end

      payload = %{"content" => message, "embeds" => []}
      send_payload(payload)
    end
  end

  @doc """
  Sends a basic embed message to Discord.
  """
  def send_embed(title, description, url \\ nil, color \\ 0x00FF00) do
    if env() == :test do
      if @verbose_logging, do: Logger.info("DISCORD MOCK EMBED: #{title} - #{description}")
      :ok
    else
      try do
        WandererNotifier.Stats.increment(:errors)
      rescue
        _ -> :ok
      end

      embed = %{"title" => title, "description" => description, "color" => color}
      embed = if url, do: Map.put(embed, "url", url), else: embed
      payload = %{"embeds" => [embed]}
      send_payload(payload)
    end
  end

  @doc """
  Sends a rich embed message for an enriched killmail.
  Expects the enriched killmail (and its nested maps) to have string keys.
  """
  def send_enriched_kill_embed(enriched_kill, kill_id) do
    if env() == :test do
      if @verbose_logging, do: Logger.info("DISCORD TEST KILL EMBED: Kill ID #{kill_id}")
      :ok
    else
      try do
        WandererNotifier.Stats.increment(:kills)
      rescue
        _ -> :ok
      end

      normalized = normalize_keys(enriched_kill)

      system_name =
        case Map.get(normalized, "system_name") do
          nil ->
            solar_system_id = Map.get(normalized, "solar_system_id")
            resolve_system_name(solar_system_id)
          name ->
            name
        end

      kill_url = "https://zkillboard.com/kill/#{kill_id}/"
      title = "Ship destroyed in #{system_name}"
      description = build_description(normalized)
      total_value = get_total_value(normalized)
      formatted_value = format_isk_value(total_value)

      # Check if license is valid
      license_valid = WandererNotifier.License.status().valid

      if license_valid do
        # Send rich embed for valid license
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
        top_attacker = get_top_attacker(attackers)
        corp_id = Map.get(top_attacker, "corporation_id")

        author_icon_url =
          if corp_id, do: "https://image.eveonline.com/Corporation/#{corp_id}_64.png", else: nil

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
      else
        # Send plain text for invalid license
        # Extract basic information for plain text
        victim = Map.get(normalized, "victim", %{})
        victim_data = extract_entity(victim)

        # Create a simple plain text message
        message = "Kill in #{system_name}: #{victim_data.name} lost a #{victim_data.ship} (#{formatted_value}) - #{kill_url}"
        send_message(message)
      end
    end
  end

  @doc """
  Sends a notification for a new tracked character.
  Expects a map with keys: "character_id", "character_name", "corporation_id", "corporation_name".
  If names are missing, ESI lookups are performed.
  """
  def send_new_tracked_character_notification(character) when is_map(character) do
    if env() == :test do
      character_id = Map.get(character, "character_id") || Map.get(character, "eve_id")
      if @verbose_logging, do: Logger.info("DISCORD TEST CHARACTER NOTIFICATION: Character ID #{character_id}")
      :ok
    else
      try do
        WandererNotifier.Stats.increment(:characters)
      rescue
        _ -> :ok
      end

      character_id = Map.get(character, "character_id") || Map.get(character, "eve_id")
      portrait_url = "https://image.eveonline.com/characters/#{character_id}/portrait"

      name =
        Map.get(character, "character_name") ||
          case WandererNotifier.ESI.Service.get_character_info(character_id) do
            {:ok, %{"name" => n}} -> n
            _ -> "Character #{character_id}"
          end

      corp_id = Map.get(character, "corporation_id") || Map.get(character, "corp_id")

      corp =
        Map.get(character, "corporation_name") ||
          case WandererNotifier.ESI.Service.get_corporation_info(corp_id) do
            {:ok, %{"name" => n}} -> n
            _ -> "Corp #{corp_id}"
          end

      # Check if license is valid
      license_valid = WandererNotifier.License.status().valid

      if license_valid do
        # Send rich embed for valid license
        title = "New Tracked Character"

        description =
          "New tracked character **#{name}** (Corp: #{corp}) has been retrieved from the API."

        url = "https://zkillboard.com/character/#{character_id}/"
        color = 0x00FF00

        embed =
          %{
            "title" => title,
            "url" => url,
            "description" => description,
            "color" => color,
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
          |> maybe_put("thumbnail", %{"url" => portrait_url})

        payload = %{"embeds" => [embed]}
        send_payload(payload)
      else
        # Send plain text for invalid license
        message = "New tracked character: #{name} (Corp: #{corp}) - https://zkillboard.com/character/#{character_id}/"
        send_message(message)
      end
    end
  end

  @doc """
  Sends a notification for a new system found.
  Expects a map with keys: "system_id" and optionally "system_name".
  If "system_name" is missing, falls back to a lookup.
  """
  def send_new_system_notification(system) when is_map(system) do
    if env() == :test do
      system_id = Map.get(system, "system_id") || Map.get(system, :system_id)
      if @verbose_logging, do: Logger.info("DISCORD TEST SYSTEM NOTIFICATION: System ID #{system_id}")
      :ok
    else
      try do
        WandererNotifier.Stats.increment(:systems)
      rescue
        _ -> :ok
      end

      system_id =
        Map.get(system, "system_id") ||
          Map.get(system, :system_id)

      system_name =
        Map.get(system, "system_name") ||
          Map.get(system, :alias) ||
          "Solar System #{system_id}"

      # Check if license is valid
      license_valid = WandererNotifier.License.status().valid

      if license_valid do
        # Send rich embed for valid license
        title = "New System Tracked"
        description = "New system **#{system_name}** has been added to tracking."
        url = "https://zkillboard.com/system/#{system_id}/"
        color = 0x00FF00

        embed = %{
          "title" => title,
          "url" => url,
          "description" => description,
          "color" => color,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        payload = %{"embeds" => [embed]}
        send_payload(payload)
      else
        # Send plain text for invalid license
        message = "New system tracked: #{system_name} - https://zkillboard.com/system/#{system_id}/"
        send_message(message)
      end
    end
  end

  defp send_payload(payload) do
    url = build_url()
    json_payload = Jason.encode!(payload)

    Logger.info("Sending Discord notification to URL: #{url}")
    Logger.debug("Discord notification payload: #{inspect(payload, pretty: true)}")
    Logger.debug("Discord notification headers: #{inspect(headers(), pretty: true)}")

    case HttpClient.request("POST", url, headers(), json_payload) do
      {:ok, %HTTPoison.Response{status_code: status}} when status in 200..299 ->
        Logger.info("Discord message sent successfully with status code: #{status}")
        :ok

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.error("Discord API request failed with status #{status}")
        Logger.error("Discord API error response: #{inspect(body)}")
        {:error, body}

      {:error, err} ->
        Logger.error("Discord API request error: #{inspect(err)}")
        {:error, err}
    end
  end

  # Conditionally add a field.
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Adds the author block.
  defp put_author(embed, author_name, url, nil) do
    Map.put(embed, "author", %{"name" => author_name, "url" => url})
  end

  defp put_author(embed, author_name, url, author_icon_url) do
    Map.put(embed, "author", %{"name" => author_name, "url" => url, "icon_url" => author_icon_url})
  end

  # Recursively normalize keys in a map to strings.
  defp normalize_keys(%WandererNotifier.Killmail{} = killmail) do
    # Convert the Killmail struct to a map and then normalize it
    killmail_map = %{
      "killmail_id" => killmail.killmail_id,
      "zkb" => normalize_keys(killmail.zkb),
      "esi_data" => normalize_keys(killmail.esi_data)
    }

    # Merge ESI data into the top level for easier access
    Map.merge(killmail_map, normalize_keys(killmail.esi_data || %{}))
  end

  defp normalize_keys(value) when is_map(value) do
    for {k, v} <- value, into: %{} do
      key = if is_atom(k), do: Atom.to_string(k), else: k
      {key, normalize_keys(v)}
    end
  end

  defp normalize_keys(value) when is_list(value), do: Enum.map(value, &normalize_keys/1)
  defp normalize_keys(value), do: value

  defp build_description(normalized) do
    victim = Map.get(normalized, "victim", %{})
    attackers = Map.get(normalized, "attackers", [])

    final_attacker = get_final_attacker(attackers)
    top_attacker = get_top_attacker(attackers)

    victim_data = extract_entity(victim)
    final_data = extract_entity(final_attacker)

    base_desc =
      "**[#{victim_data.name}](#{victim_data.zkill_url}) (#{victim_data.corp})** lost their **#{victim_data.ship}** " <>
      "to **[#{final_data.name}](#{final_data.zkill_url}) (#{final_data.corp})** flying a **#{final_data.ship}**"

    if length(attackers) > 1 and top_attacker != %{} do
      top_data = extract_entity(top_attacker)

      base_desc <>
        ", Top Damage was done by **[#{top_data.name}](#{top_data.zkill_url}) (#{top_data.corp})** " <>
        "flying a **#{top_data.ship}**."
    else
      base_desc <> " solo."
    end
  end

  defp get_final_attacker(attackers) when is_list(attackers) do
    valid =
      attackers
      |> Enum.filter(fn a -> Map.has_key?(a, "character_id") end)

    Enum.find(valid, fn a -> Map.get(a, "final_blow", false) end) ||
      if valid != [], do: Enum.max_by(valid, fn a -> Map.get(a, "damage_done", 0) end), else: %{}
  end

  defp get_top_attacker(attackers) when is_list(attackers) do
    valid =
      attackers
      |> Enum.filter(fn a -> Map.has_key?(a, "character_id") end)

    if valid != [] do
      Enum.max_by(valid, fn a -> Map.get(a, "damage_done", 0) end)
    else
      %{}
    end
  end

  defp extract_entity(entity) when is_map(entity) do
    character_id = Map.get(entity, "character_id")

    name =
      case Map.get(entity, "character_name") do
        nil ->
          if is_valid_id?(character_id) do
            case WandererNotifier.ESI.Service.get_character_info(character_id) do
              {:ok, %{"name" => character_name}} -> character_name
              _ -> "Character #{character_id}"
            end
          else
            "Unknown Character"
          end

        name ->
          name
      end

    corporation_id = Map.get(entity, "corporation_id")

    corp =
      case Map.get(entity, "corporation_name") do
        nil ->
          if is_valid_id?(corporation_id) do
            case WandererNotifier.ESI.Service.get_corporation_info(corporation_id) do
              {:ok, %{"name" => corp_name}} -> corp_name
              _ -> "Corp #{corporation_id}"
            end
          else
            "Unknown Corporation"
          end

        corp_name ->
          corp_name
      end

    ship_type_id = Map.get(entity, "ship_type_id")

    ship =
      case Map.get(entity, "ship_name") do
        nil ->
          if is_valid_id?(ship_type_id) do
            case WandererNotifier.ESI.Service.get_ship_type_name(ship_type_id) do
              {:ok, %{"name" => ship_name}} -> ship_name
              _ -> "Ship #{ship_type_id}"
            end
          else
            "Unknown Ship"
          end

        ship_name ->
          ship_name
      end

    zkill_url =
      Map.get(entity, "zkill_url") ||
        if is_valid_id?(character_id) do
          "https://zkillboard.com/character/#{character_id}/"
        else
          nil
        end

    %{id: character_id || "unknown", name: name, corp: corp, ship: ship, zkill_url: zkill_url}
  end

  # Helper function to check if an ID is valid for API calls
  defp is_valid_id?(nil), do: false
  defp is_valid_id?("Unknown"), do: false
  defp is_valid_id?("unknown"), do: false
  defp is_valid_id?(id) when is_binary(id) do
    case Integer.parse(id) do
      {num, ""} when num > 0 -> true
      _ -> false
    end
  end
  defp is_valid_id?(id) when is_integer(id) and id > 0, do: true
  defp is_valid_id?(_), do: false

  defp resolve_system_name(nil), do: "Unknown System"

  defp resolve_system_name(solar_system_id) do
    if not is_valid_id?(solar_system_id) do
      "Unknown System"
    else
      tracked = get_tracked_systems()

      case Enum.find(tracked, fn sys ->
             to_string(Map.get(sys, "system_id") || Map.get(sys, :system_id)) ==
               to_string(solar_system_id)
           end) do
        nil ->
          case WandererNotifier.ESI.Service.get_solar_system_name(solar_system_id) do
            {:ok, %{"name" => name}} -> name
            _ -> "Solar System #{solar_system_id}"
          end

        system ->
          Map.get(system, "system_name") || Map.get(system, :alias) ||
            "Solar System #{solar_system_id}"
      end
    end
  end

  defp get_tracked_systems do
    CacheHelpers.get_tracked_systems()
  end

  defp get_total_value(normalized) do
    case Map.get(normalized, "total_value") do
      nil ->
        get_in(normalized, ["zkb", "totalValue"]) || 0.0
      value ->
        value
    end
  end

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
