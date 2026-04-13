defmodule WandererNotifier.Domains.Notifications.Discord.HttpClient do
  @moduledoc """
  Direct Discord REST API client that supports multiple bot tokens.

  Used for multi-map notification sending where each map has its own
  Discord bot token. Bypasses Nostrum's API layer (which only supports
  a single bot token) and makes direct HTTP requests.

  Uses the existing `Infrastructure.Http` module with the `:discord`
  service configuration for timeout and retry settings.
  """

  require Logger

  alias WandererNotifier.Infrastructure.Http

  @discord_api_base "https://discord.com/api/v10"

  @discord_embed_keys MapSet.new(~w(
    title description url color timestamp footer image thumbnail
    author fields name value inline icon_url proxy_icon_url text
    width height proxy_url provider video
  ))

  @discord_embed_key_map Map.new(@discord_embed_keys, fn key -> {key, String.to_atom(key)} end)

  @max_retries 2
  @initial_retry_delay_ms 500

  @type embed :: map()
  @type channel_id :: String.t() | integer()
  @type bot_token :: String.t()
  @type send_result :: {:ok, :sent} | {:error, term()}

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Sends a Discord embed to a channel using a specific bot token.
  """
  @spec send_embed(bot_token(), channel_id(), embed(), keyword()) :: send_result()
  def send_embed(bot_token, channel_id, embed, opts \\ []) do
    send_message_payload(bot_token, channel_id, %{embeds: [normalize_embed(embed)]}, opts)
  end

  @doc """
  Sends a Discord embed with text content (for @mentions) to a channel.
  """
  @spec send_embed_with_content(bot_token(), channel_id(), embed(), String.t(), keyword()) ::
          send_result()
  def send_embed_with_content(bot_token, channel_id, embed, content, opts \\ []) do
    payload = %{
      embeds: [normalize_embed(embed)],
      content: content
    }

    send_message_payload(bot_token, channel_id, payload, opts)
  end

  @doc """
  Sends a plain text message to a channel using a specific bot token.
  """
  @spec send_message(bot_token(), channel_id(), String.t(), keyword()) :: send_result()
  def send_message(bot_token, channel_id, content, opts \\ []) do
    send_message_payload(bot_token, channel_id, %{content: content}, opts)
  end

  # ============================================================================
  # Private Implementation
  # ============================================================================

  defp send_message_payload(bot_token, channel_id, payload, caller_opts) do
    url = "#{@discord_api_base}/channels/#{channel_id}/messages"

    headers = [
      {"Authorization", "Bot #{bot_token}"},
      {"Content-Type", "application/json"}
    ]

    defaults = [service: :discord, rate_limit: [bucket_key: token_bucket_key(bot_token)]]
    opts = Keyword.merge(defaults, caller_opts)

    do_send_with_retry(url, payload, headers, opts, channel_id, _attempt = 0)
  end

  defp do_send_with_retry(url, payload, headers, opts, channel_id, attempt) do
    result = Http.request(:post, url, payload, headers, opts)

    case handle_response(result, channel_id) do
      {:retry, reason} when attempt < @max_retries ->
        delay = retry_delay(attempt)
        log_retry(channel_id, reason, attempt)
        Process.sleep(delay)
        do_send_with_retry(url, payload, headers, opts, channel_id, attempt + 1)

      {:retry, reason} ->
        log_exhausted(channel_id, reason)
        {:error, reason}

      final ->
        final
    end
  end

  defp handle_response({:ok, %{status_code: status}}, _channel_id) when status in 200..299 do
    {:ok, :sent}
  end

  defp handle_response({:ok, %{status_code: 429, body: body}}, channel_id) do
    retry_after = extract_retry_after(body)
    Logger.warning("Discord rate limited", channel_id: channel_id, retry_after: retry_after)
    {:error, {:rate_limited, retry_after}}
  end

  defp handle_response({:ok, %{status_code: status, body: body}}, channel_id) do
    Logger.error("Discord API error", status: status, channel_id: channel_id, body: inspect(body))
    {:error, {:discord_api_error, status}}
  end

  defp handle_response({:error, reason}, _channel_id) do
    {:retry, reason}
  end

  defp log_retry(channel_id, reason, attempt) do
    Logger.warning("Discord transport error, retrying",
      channel_id: channel_id,
      error: inspect(reason),
      attempt: attempt + 1,
      max_retries: @max_retries,
      retry_in_ms: retry_delay(attempt)
    )
  end

  defp log_exhausted(channel_id, reason) do
    Logger.error("Discord request failed after #{@max_retries} retries",
      channel_id: channel_id,
      error: inspect(reason)
    )
  end

  defp retry_delay(attempt) do
    trunc(@initial_retry_delay_ms * :math.pow(2, attempt))
  end

  defp extract_retry_after(%{"retry_after" => seconds}) when is_number(seconds), do: seconds
  defp extract_retry_after(_), do: 5.0

  # Normalize embed to a plain map suitable for the Discord REST API.
  # Handles Nostrum structs, custom structs, and plain maps.
  defp normalize_embed(embed) when is_struct(embed) do
    embed
    |> Map.from_struct()
    |> normalize_embed_map()
  end

  defp normalize_embed(embed) when is_map(embed) do
    normalize_embed_map(embed)
  end

  defp normalize_embed_map(embed) do
    embed
    |> normalize_keys()
    |> Map.drop([:__struct__, :content, :type])
    |> reject_nil_values()
    |> normalize_nested()
  end

  defp normalize_keys(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) ->
        {k, v}

      {k, v} when is_binary(k) ->
        case Map.fetch(@discord_embed_key_map, k) do
          {:ok, atom_key} -> {atom_key, v}
          :error -> {k, v}
        end

      {k, v} ->
        {k, v}
    end)
  end

  defp reject_nil_values(map) do
    Map.reject(map, fn {_k, v} -> is_nil(v) end)
  end

  defp normalize_nested(map) do
    map
    |> maybe_normalize_field(:footer)
    |> maybe_normalize_field(:author)
    |> maybe_normalize_field(:thumbnail)
    |> maybe_normalize_field(:image)
    |> maybe_normalize_fields()
  end

  defp maybe_normalize_field(map, key) do
    case Map.get(map, key) do
      nil ->
        map

      value when is_struct(value) ->
        Map.put(map, key, value |> Map.from_struct() |> reject_nil_values())

      value when is_map(value) ->
        Map.put(map, key, reject_nil_values(value))

      _ ->
        map
    end
  end

  defp maybe_normalize_fields(map) do
    case Map.get(map, :fields) do
      nil ->
        map

      fields when is_list(fields) ->
        normalized =
          Enum.map(fields, fn
            field when is_struct(field) -> field |> Map.from_struct() |> reject_nil_values()
            field when is_map(field) -> reject_nil_values(field)
            other -> other
          end)

        Map.put(map, :fields, normalized)

      _ ->
        map
    end
  end

  # Generate a rate limit bucket key from a bot token.
  # Uses a truncated SHA-256 hash for privacy and consistent keying.
  defp token_bucket_key(bot_token) do
    hash = :crypto.hash(:sha256, bot_token) |> Base.encode16(case: :lower) |> binary_part(0, 12)
    "discord:#{hash}"
  end
end
