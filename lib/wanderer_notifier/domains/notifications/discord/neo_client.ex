defmodule WandererNotifier.Domains.Notifications.Notifiers.Discord.NeoClient do
  @moduledoc """
  Nostrum-based Discord client implementation.
  Leverages the Nostrum library for interaction with Discord API and event handling.
  """
  use Nostrum.Consumer

  alias Nostrum.Api.Message
  alias Nostrum.Struct.Embed
  alias WandererNotifier.Domains.Notifications.Discord.ChannelResolver
  require Logger
  alias WandererNotifier.Shared.Utils.TimeUtils
  alias WandererNotifier.Shared.Utils.Retry
  alias WandererNotifier.Domains.Notifications.Discord.ConnectionHealth

  # -- ENVIRONMENT AND CONFIGURATION HELPERS --

  defp env do
    Application.get_env(:wanderer_notifier, :env, :prod)
  end

  @doc """
  Gets the configured Discord channel ID as an integer.
  Returns the normalized channel ID or nil if not set or invalid.
  """
  def channel_id do
    ChannelResolver.get_primary_channel_id()
  end

  # -- MESSAGING API --

  @doc """
  Sends an embed message to Discord using Nostrum.

  ## Parameters
    - embed: A map containing the embed data
    - override_channel_id: Optional channel ID to override the default

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_embed(embed, override_channel_id \\ nil) do
    if env() == :test do
      log_test_embed(embed)
    else
      target_channel = resolve_target_channel(override_channel_id)
      send_embed_to_channel(embed, target_channel)
    end
  end

  # Log test mode embed without sending
  defp log_test_embed(embed) do
    Logger.info("TEST MODE: Would send embed to Discord via Nostrum",
      embed: inspect(embed),
      category: :discord_api
    )

    {:ok, :sent}
  end

  # Resolve the target channel ID
  defp resolve_target_channel(override_channel_id) do
    if is_nil(override_channel_id) do
      channel_id()
    else
      ChannelResolver.resolve_channel(:default, override_channel_id)
    end
  end

  # Send embed to the specified channel
  defp send_embed_to_channel(embed, target_channel) do
    # Validate channel ID
    case target_channel do
      nil ->
        Logger.error("Failed to send embed: nil channel ID",
          embed_type: typeof(embed),
          embed_title:
            if(is_map(embed), do: Map.get(embed, "title", "Unknown title"), else: "Unknown"),
          category: :discord_api
        )

        {:error, :nil_channel_id}

      channel_id when is_integer(channel_id) ->
        send_embed_to_valid_channel(embed, channel_id)
    end
  end

  # Helper function to send embed to a validated channel ID
  defp send_embed_to_valid_channel(embed, channel_id) do
    # Convert to Nostrum.Struct.Embed
    discord_embed = convert_to_nostrum_embed(embed)

    # Check if there's content to send with the embed
    content = extract_content_safely(embed)

    # Use Nostrum.Api.Message.create with embeds (plural) as an array
    try do
      channel_id_int = channel_id

      if is_binary(content) and String.trim(content) != "" do
        send_discord_message(channel_id_int, discord_embed, content)
      else
        send_discord_message(channel_id_int, discord_embed)
      end
    rescue
      e ->
        handle_exception(e, channel_id)
    end
  end

  # Send message to Discord and handle the response
  defp send_discord_message(channel_id_int, discord_embed) do
    send_discord_message_with_retry(channel_id_int, discord_embed, nil)
  end

  # Send message with content to Discord and handle the response
  defp send_discord_message(channel_id_int, discord_embed, content)
       when is_binary(content) and content != "" do
    send_discord_message_with_retry(channel_id_int, discord_embed, content)
  end

  defp send_discord_message_with_retry(channel_id_int, discord_embed, content) do
    rally_id = extract_rally_id(discord_embed)
    has_content = content != nil
    start_time = System.monotonic_time(:millisecond)

    retry_opts = build_retry_options(start_time, rally_id, channel_id_int)

    retry_fn =
      create_retry_function(
        channel_id_int,
        discord_embed,
        content,
        rally_id,
        has_content,
        start_time
      )

    result = Retry.http_retry(retry_fn, retry_opts)
    handle_discord_result(result, start_time, rally_id)
  end

  defp build_retry_options(start_time, rally_id, channel_id_int) do
    [
      max_attempts: 5,
      base_backoff: 2_000,
      max_backoff: 10_000,
      jitter: :full,
      context: "Discord API call",
      # IMPORTANT: Don't retry on timeouts to prevent duplicate messages
      # Only retry on definitive connection failures
      retryable_errors: [:econnrefused, :ehostunreach, :enetunreach, :econnreset],
      # Still retry on rate limits and server errors (except 408 timeout)
      retryable_status_codes: [429, 500, 502, 503, 504],
      on_retry: fn attempt, error, delay ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        log_retry_attempt(attempt, error, delay, elapsed, rally_id, channel_id_int)
      end
    ]
  end

  defp create_retry_function(
         channel_id_int,
         discord_embed,
         content,
         rally_id,
         has_content,
         start_time
       ) do
    fn ->
      log_api_attempt(channel_id_int, has_content, rally_id, 0)
      task = create_discord_api_task(channel_id_int, discord_embed, content, rally_id)
      handle_task_result(task, channel_id_int, start_time, rally_id)
    end
  end

  defp handle_task_result(task, channel_id_int, start_time, rally_id) do
    # Use a shorter initial timeout to detect stuck connections faster
    case Task.yield(task, 10_000) do
      {:ok, result} ->
        handle_task_success(result, channel_id_int, start_time, rally_id)

      nil ->
        handle_task_timeout(task, channel_id_int, start_time, rally_id)
    end
  end

  defp handle_task_success(result, channel_id_int, start_time, rally_id) do
    case result do
      {:ok, _message} = success ->
        success

      {:error, %{status_code: 429} = response} ->
        handle_rate_limit(response, channel_id_int, start_time, rally_id)

      {:error, response} ->
        {:error, response}
    end
  end

  defp handle_task_timeout(task, channel_id_int, start_time, rally_id) do
    # First timeout - log warning
    log_timeout_warning(channel_id_int, start_time, 10_000)

    # Give it another 5 seconds before giving up
    case Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        log_extended_completion(start_time)
        handle_task_success(result, channel_id_int, start_time, rally_id)

      nil ->
        handle_final_timeout(channel_id_int, start_time)
    end
  end

  defp log_timeout_warning(channel_id_int, start_time, timeout_ms) do
    Logger.warning("Discord API call still pending after #{timeout_ms / 1000}s",
      channel_id: channel_id_int,
      nostrum_state: get_nostrum_state(),
      elapsed: System.monotonic_time(:millisecond) - start_time,
      category: :discord_api
    )
  end

  defp log_extended_completion(start_time) do
    Logger.info("Discord API call completed after extended wait",
      elapsed: System.monotonic_time(:millisecond) - start_time,
      category: :discord_api
    )
  end

  defp handle_final_timeout(channel_id_int, start_time) do
    Logger.error("Discord API timeout after 15s total",
      channel_id: channel_id_int,
      nostrum_state: get_nostrum_state(),
      elapsed: System.monotonic_time(:millisecond) - start_time,
      category: :discord_api
    )

    log_system_diagnostics()

    # Record timeout for health monitoring (without killmail_id - that's handled by discord_notifier)
    ConnectionHealth.record_timeout()

    {:error, :timeout}
  end

  defp handle_discord_result({:ok, _response}, start_time, rally_id) do
    # Record success for health monitoring
    ConnectionHealth.record_success()

    handle_success(start_time, rally_id, 0)
    {:ok, :sent}
  end

  defp handle_discord_result({:error, reason}, _start_time, _rally_id) do
    Logger.error("Discord API call failed after all attempts",
      reason: inspect(reason),
      category: :discord_api
    )

    # Record failure for health monitoring (without killmail_id - that's handled by discord_notifier)
    ConnectionHealth.record_failure(reason)

    {:error, reason}
  end

  defp log_retry_attempt(attempt, error, delay, elapsed, rally_id, channel_id) do
    error_msg =
      case error do
        :timeout -> "timed out after 15 seconds"
        %{status_code: 429} -> "rate limited (429)"
        other -> inspect(other)
      end

    Logger.warning(
      "Discord API #{error_msg} on attempt #{attempt + 1} after #{elapsed}ms, retrying in #{delay}ms...",
      rally_id: rally_id,
      channel_id: channel_id,
      category: :discord_api
    )
  end

  defp extract_rally_id(discord_embed) do
    case discord_embed do
      %{description: desc} when is_binary(desc) ->
        if Regex.match?(~r/rally point/i, desc), do: "rally_point", else: nil

      _ ->
        nil
    end
  end

  defp log_api_attempt(channel_id, has_content, rally_id, _attempt) do
    Logger.info("Starting Discord API call",
      channel_id: channel_id,
      has_content: has_content,
      rally_id: rally_id,
      category: :discord_api
    )
  end

  defp create_discord_api_task(channel_id_int, discord_embed, content, rally_id) do
    Task.Supervisor.async_nolink(WandererNotifier.TaskSupervisor, fn ->
      api_start = System.monotonic_time(:millisecond)

      # Log Nostrum connection state
      ws_state = get_nostrum_state()

      Logger.debug("Pre-send state check",
        rally_id: rally_id,
        nostrum_connected: ws_state,
        channel_id: channel_id_int,
        category: :discord_api
      )

      # Log embed size for diagnostics
      embed_size = calculate_embed_size(discord_embed)

      Logger.debug("Embed size",
        rally_id: rally_id,
        embed_size_bytes: embed_size,
        has_content: content != nil,
        content_length: if(content, do: String.length(content), else: 0),
        category: :discord_api
      )

      Logger.debug("Calling Message.create",
        rally_id: rally_id,
        category: :discord_api
      )

      result = call_discord_api(channel_id_int, discord_embed, content)

      Logger.debug(
        "Message.create returned after #{System.monotonic_time(:millisecond) - api_start}ms",
        rally_id: rally_id,
        result_type: elem(result, 0),
        category: :discord_api
      )

      result
    end)
  end

  defp call_discord_api(channel_id_int, discord_embed, content) do
    log_pre_api_state(channel_id_int, content)
    start_time = System.monotonic_time(:millisecond)

    log_api_call_start(channel_id_int)

    result = execute_message_create(channel_id_int, discord_embed, content)
    duration = System.monotonic_time(:millisecond) - start_time

    log_api_call_result(channel_id_int, duration, result)
    finalize_api_result(result, duration)
  end

  defp log_pre_api_state(channel_id_int, content) do
    content_info = format_content_preview(content)
    ratelimiter_state = get_ratelimiter_state()

    Logger.info("[DiagnosticLog] Pre-API call state",
      channel_id: channel_id_int,
      content_preview: content_info,
      ratelimiter: ratelimiter_state,
      category: :discord_api
    )

    log_rate_limit_warning(channel_id_int)
  end

  defp format_content_preview(nil), do: "none"

  defp format_content_preview(content) do
    preview = String.slice(content, 0, 50)
    suffix = if String.length(content) > 50, do: "...", else: ""
    "\"#{preview}#{suffix}\""
  end

  defp log_rate_limit_warning(channel_id_int) do
    rate_limit_info = check_rate_limit_status(channel_id_int)

    if rate_limit_info[:limited] do
      Logger.warning("Rate limit active",
        channel_id: channel_id_int,
        retry_after: rate_limit_info[:retry_after],
        category: :discord_api
      )
    end
  end

  defp log_api_call_start(channel_id_int) do
    Logger.info("[DiagnosticLog] Calling Message.create NOW",
      channel_id: channel_id_int,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      category: :discord_api
    )
  end

  defp execute_message_create(channel_id_int, discord_embed, content) do
    try do
      log_gun_pool_status()

      # Deep diagnostic: check ratelimiter state machine
      rl_state = get_ratelimiter_deep_state()

      Logger.info("[DiagnosticLog] Ratelimiter deep state before Message.create",
        state: rl_state,
        category: :discord_api
      )

      if content do
        Message.create(channel_id_int, content: content, embeds: [discord_embed])
      else
        Message.create(channel_id_int, embeds: [discord_embed])
      end
    rescue
      exception ->
        Logger.error("Exception during Discord API call",
          error: Exception.message(exception),
          stacktrace: __STACKTRACE__,
          category: :discord_api
        )

        {:error, exception}
    end
  end

  defp get_ratelimiter_deep_state do
    try do
      fetch_ratelimiter_state()
    rescue
      e -> %{error: Exception.message(e)}
    catch
      :exit, {:timeout, _} -> %{error: "sys.get_state timeout - ratelimiter blocked"}
      :exit, reason -> %{error: "exit: #{inspect(reason)}"}
    end
  end

  defp fetch_ratelimiter_state do
    case Process.whereis(Nostrum.Api.Ratelimiter) do
      nil -> %{exists: false}
      pid -> extract_ratelimiter_state(pid)
    end
  end

  defp extract_ratelimiter_state(pid) do
    case :sys.get_state(pid, 1000) do
      {state_name, state_data} when is_atom(state_name) ->
        build_ratelimiter_info(state_name, state_data)

      other ->
        %{exists: true, state: inspect(other) |> String.slice(0, 100)}
    end
  end

  defp build_ratelimiter_info(state_name, state_data) do
    %{
      exists: true,
      state_name: state_name,
      connection: get_connection_info(state_data),
      outstanding_count: state_data |> Map.get(:outstanding, %{}) |> map_size(),
      running_count: state_data |> Map.get(:running, %{}) |> map_size(),
      inflight_count: state_data |> Map.get(:inflight, %{}) |> map_size()
    }
  end

  defp get_connection_info(state_data) do
    case Map.get(state_data, :conn) do
      nil -> :no_connection
      conn_pid when is_pid(conn_pid) -> if Process.alive?(conn_pid), do: :alive, else: :dead
      _ -> :unknown
    end
  end

  defp log_api_call_result(channel_id_int, duration, result) do
    Logger.info("[DiagnosticLog] Message.create returned",
      channel_id: channel_id_int,
      duration_ms: duration,
      result_type: elem(result, 0),
      category: :discord_api
    )
  end

  defp finalize_api_result({:ok, _} = success, _duration), do: success

  defp finalize_api_result({:error, reason} = error, duration) do
    Logger.error("Discord API call failed",
      duration_ms: duration,
      reason: inspect(reason),
      category: :discord_api
    )

    error
  end

  defp handle_success(start_time, rally_id, attempt) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if attempt > 0 do
      Logger.info(
        "Discord API call succeeded on attempt #{attempt + 1} after #{elapsed}ms",
        rally_id: rally_id,
        category: :discord_api
      )
    else
      Logger.info("Discord API call succeeded after #{elapsed}ms",
        rally_id: rally_id,
        category: :discord_api
      )
    end

    {:ok, :sent}
  end

  defp handle_rate_limit(response, _channel_id_int, start_time, rally_id) do
    elapsed = System.monotonic_time(:millisecond) - start_time
    retry_after = get_retry_after(Map.get(response, :response))

    Logger.warning("Discord rate limited after #{elapsed}ms",
      rally_id: rally_id,
      retry_after: retry_after,
      category: :discord_api
    )

    {:error, %{status_code: 429, retry_after: retry_after}}
  end

  # Handle exceptions during message sending
  defp handle_exception(e, channel_id) do
    Logger.error("Exception in send_embed_to_channel",
      error: Exception.message(e),
      channel_id: channel_id,
      category: :discord_api
    )

    {:error, {:exception, Exception.message(e)}}
  end

  @doc """
  Sends a message with components to Discord using Nostrum.

  ## Parameters
    - embed: A map containing the embed data
    - components: A list of component rows (buttons, select menus, etc.)
    - override_channel_id: Optional channel ID to override the default

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_message_with_components(embed, components, override_channel_id \\ nil) do
    if env() == :test do
      log_test_message_with_components(embed, components)
    else
      target_channel = resolve_target_channel(override_channel_id)
      send_message_with_components_to_channel(embed, components, target_channel)
    end
  end

  # Log test mode message with components without sending
  defp log_test_message_with_components(embed, components) do
    Logger.info("TEST MODE: Would send message with components via Nostrum",
      embed: inspect(embed),
      components: inspect(components),
      category: :discord_api
    )

    {:ok, :sent}
  end

  # Send message with components to the specified channel
  defp send_message_with_components_to_channel(_embed, _components, nil) do
    Logger.error("Failed to send message with components: nil channel ID", category: :discord_api)
    {:error, :nil_channel_id}
  end

  defp send_message_with_components_to_channel(embed, components, target_channel) do
    # Convert to Nostrum structs
    discord_embed = convert_to_nostrum_embed(embed)
    discord_components = components
    # Log detailed info about what we're sending
    Logger.debug("Sending message with components via Nostrum",
      channel_id: target_channel,
      embed_type: typeof(discord_embed),
      category: :discord_api
    )

    case Message.create(target_channel,
           embeds: [discord_embed],
           components: discord_components
         ) do
      {:ok, _message} ->
        {:ok, :sent}

      {:error, %{status_code: 429, response: response}} ->
        retry_after = get_retry_after(response)

        Logger.error("Discord rate limit hit via Nostrum",
          retry_after: retry_after,
          category: :discord_api
        )

        {:error, %{status_code: 429, retry_after: retry_after}}

      {:error, error} ->
        Logger.error("Failed to send message with components via Nostrum",
          error: inspect(error),
          category: :discord_api
        )

        {:error, error}
    end
  end

  @doc """
  Sends a simple text message to Discord using Nostrum.

  ## Parameters
    - message: The text message to send
    - override_channel_id: Optional channel ID to override the default

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_message(message, override_channel_id \\ nil) do
    if env() == :test do
      log_test_message(message)
    else
      target_channel = resolve_target_channel(override_channel_id)
      send_message_to_channel(message, target_channel)
    end
  end

  # Log test mode message without sending
  defp log_test_message(message) do
    Logger.info("TEST MODE: Would send message via Nostrum",
      message: message,
      category: :discord_api
    )

    {:ok, :sent}
  end

  # Send message to the specified channel
  defp send_message_to_channel(_message, nil) do
    Logger.error("Failed to send message: nil channel ID", category: :discord_api)
    {:error, :nil_channel_id}
  end

  defp send_message_to_channel(message, target_channel) do
    Logger.debug("Sending text message via Nostrum",
      channel_id: target_channel,
      message_length: String.length(message),
      category: :discord_api
    )

    # target_channel is already an integer from resolve_target_channel
    case Message.create(target_channel, content: message) do
      {:ok, _response} ->
        {:ok, :sent}

      {:error, %{status_code: 429, response: response}} ->
        retry_after = get_retry_after(response)

        Logger.error("Discord rate limit hit via Nostrum",
          retry_after: retry_after,
          category: :discord_api
        )

        {:error, %{status_code: 429, retry_after: retry_after}}

      {:error, error} ->
        Logger.error("Failed to send message via Nostrum")
        {:error, error}
    end
  end

  # -- FILE HANDLING --

  @doc """
  Sends a file to Discord with an optional title and description using Nostrum.

  ## Parameters
    - filename: The name of the file to send
    - file_data: The binary content of the file
    - title: The title for the Discord embed (optional)
    - description: The description for the Discord embed (optional)
    - override_channel_id: Optional channel ID to override the default
    - custom_embed: A custom embed to use instead of the default one (optional)

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_file(
        filename,
        file_data,
        title \\ nil,
        description \\ nil,
        override_channel_id \\ nil,
        custom_embed \\ nil
      ) do
    if env() == :test do
      log_test_file(filename, title, description)
    else
      Logger.debug("Sending file to Discord via Nostrum",
        filename: filename,
        category: :discord_api
      )

      target_channel = resolve_target_channel(override_channel_id)
      send_file_to_channel(filename, file_data, title, description, target_channel, custom_embed)
    end
  end

  # Log test mode file without sending
  defp log_test_file(filename, title, description) do
    Logger.info("TEST MODE: Would send file to Discord via Nostrum",
      filename: filename,
      title: title,
      description: description,
      category: :discord_api
    )

    {:ok, :sent}
  end

  # Send file to the specified channel
  defp send_file_to_channel(_filename, _file_data, _title, _description, nil, _custom_embed) do
    Logger.error("Failed to send file: nil channel ID", category: :discord_api)
    {:error, :nil_channel_id}
  end

  defp send_file_to_channel(filename, file_data, title, description, target_channel, custom_embed) do
    # Create the embed (use custom if provided, otherwise create default)
    embed = create_file_embed(filename, title, description, custom_embed)

    Logger.debug("Sending file with embed via Nostrum",
      channel_id: target_channel,
      filename: filename,
      embed: inspect(embed),
      category: :discord_api
    )

    case Message.create(target_channel,
           file: %{name: filename, body: file_data},
           embeds: [embed]
         ) do
      {:ok, _message} ->
        {:ok, :sent}

      {:error, %{status_code: 429, response: response}} ->
        retry_after = get_retry_after(response)

        Logger.error("Discord rate limit hit via Nostrum",
          retry_after: retry_after,
          category: :discord_api
        )

        {:error, %{status_code: 429, retry_after: retry_after}}

      {:error, error} ->
        Logger.error("Failed to send file via Nostrum", category: :discord_api)
        {:error, error}
    end
  end

  # Create embed for file upload
  defp create_file_embed(filename, title, description, custom_embed) do
    if custom_embed do
      embed = convert_to_nostrum_embed(custom_embed)
      %{embed | image: %{url: "attachment://#{filename}"}}
    else
      %Embed{
        title: title,
        description: description,
        timestamp: TimeUtils.now(),
        color: 3_447_003,
        image: %{url: "attachment://#{filename}"}
      }
    end
  end

  # -- EVENT HANDLING --

  @doc """
  Handle interaction events from Discord.
  This allows responding to button clicks, select menu choices, etc.
  """
  @impl true
  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    Logger.debug("Received Discord interaction",
      type: interaction.type,
      guild_id: interaction.guild_id,
      channel_id: interaction.channel_id,
      category: :discord_api
    )

    :noop
  end

  @impl true
  def handle_event(_event) do
    :noop
  end

  # -- HELPERS --

  defp typeof(term) when is_binary(term), do: "string"
  defp typeof(term) when is_boolean(term), do: "boolean"
  defp typeof(term) when is_integer(term), do: "integer"
  defp typeof(term) when is_float(term), do: "float"
  defp typeof(term) when is_map(term), do: "map"
  defp typeof(term) when is_list(term), do: "list"
  defp typeof(term) when is_atom(term), do: "atom"
  defp typeof(term) when is_tuple(term), do: "tuple"
  defp typeof(term) when is_function(term), do: "function"
  defp typeof(term) when is_pid(term), do: "pid"
  defp typeof(term) when is_reference(term), do: "reference"
  defp typeof(term) when is_struct(term), do: "struct:#{term.__struct__}"
  defp typeof(_), do: "unknown"

  @doc """
  Converts any embed format to Nostrum.Struct.Embed.
  """
  def convert_to_nostrum_embed(embed) when is_struct(embed, Embed) do
    # Already a Nostrum embed
    embed
  end

  def convert_to_nostrum_embed(embed) do
    require Logger

    # Convert struct to map if needed
    embed_map =
      if is_struct(embed) do
        Map.from_struct(embed)
      else
        embed
      end

    # Extract fields safely
    fields_raw =
      cond do
        Map.has_key?(embed_map, :fields) -> Map.get(embed_map, :fields)
        Map.has_key?(embed_map, "fields") -> Map.get(embed_map, "fields")
        true -> []
      end

    fields = if is_list(fields_raw), do: fields_raw, else: []

    # Create the Nostrum embed
    discord_embed = %Embed{
      title: get_field_with_fallback(embed_map, :title, "title"),
      description: get_field_with_fallback(embed_map, :description, "description"),
      url: get_field_with_fallback(embed_map, :url, "url"),
      timestamp: get_field_with_fallback(embed_map, :timestamp, "timestamp"),
      color: get_field_with_fallback(embed_map, :color, "color"),
      footer: extract_footer(embed_map),
      image: extract_image(embed_map),
      thumbnail: extract_thumbnail(embed_map),
      author: extract_author(embed_map),
      fields:
        Enum.map(fields, fn field ->
          %Embed.Field{
            name: get_field_with_fallback(field, :name, "name", ""),
            value: get_field_with_fallback(field, :value, "value", ""),
            inline: get_field_with_fallback(field, :inline, "inline", false)
          }
        end)
    }

    discord_embed
  end

  # Extract footer from the embed
  defp extract_footer(embed) do
    footer = get_field_with_fallback(embed, :footer, "footer")

    case footer do
      nil -> nil
      footer_map when is_map(footer_map) -> build_footer(footer_map)
    end
  end

  # Build a footer struct from a map
  defp build_footer(footer_map) do
    %Embed.Footer{
      text: get_field_with_fallback(footer_map, :text, "text", ""),
      icon_url: get_field_with_fallback(footer_map, :icon_url, "icon_url")
    }
  end

  # Extract author from the embed
  defp extract_author(embed) do
    author = get_field_with_fallback(embed, :author, "author")

    case author do
      nil -> nil
      author_map when is_map(author_map) -> build_author(author_map)
    end
  end

  # Build an author struct from a map
  defp build_author(author_map) do
    %Embed.Author{
      name: get_field_with_fallback(author_map, :name, "name", ""),
      url: get_field_with_fallback(author_map, :url, "url"),
      icon_url: get_field_with_fallback(author_map, :icon_url, "icon_url")
    }
  end

  # Extract content safely using pattern matching
  defp extract_content_safely(%{content: content}) when is_binary(content), do: content
  defp extract_content_safely(%{"content" => content}) when is_binary(content), do: content
  defp extract_content_safely(_), do: ""

  # Get a field with fallback from atom or string keys
  defp get_field_with_fallback(map, atom_key, string_key, default \\ nil) do
    value =
      cond do
        Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
        Map.has_key?(map, string_key) -> Map.get(map, string_key)
        true -> default
      end

    value
  end

  # Extract thumbnail from the embed
  defp extract_thumbnail(embed) do
    thumbnail = get_field_with_fallback(embed, :thumbnail, "thumbnail")
    # Try different formats in order of likelihood
    cond do
      valid_thumbnail = extract_thumbnail_from_map(thumbnail) ->
        valid_thumbnail

      valid_url = extract_valid_url(thumbnail) ->
        %Embed.Thumbnail{url: valid_url}

      valid_url = extract_valid_url(Map.get(embed, "thumbnail_url")) ->
        %Embed.Thumbnail{url: valid_url}

      valid_url = extract_valid_url(Map.get(embed, "icon_url")) ->
        %Embed.Thumbnail{url: valid_url}

      true ->
        extract_thumbnail_from_icon_field(embed)
    end
  end

  # Extract thumbnail from a map with url key
  defp extract_thumbnail_from_map(thumbnail) when is_map(thumbnail) do
    cond do
      valid_url = extract_valid_url(Map.get(thumbnail, :url)) ->
        %Embed.Thumbnail{url: valid_url}

      valid_url = extract_valid_url(Map.get(thumbnail, "url")) ->
        %Embed.Thumbnail{url: valid_url}

      true ->
        nil
    end
  end

  defp extract_thumbnail_from_map(_), do: nil

  # Check for icon field and extract thumbnail
  defp extract_thumbnail_from_icon_field(embed) do
    if Map.has_key?(embed, "icon") do
      icon = Map.get(embed, "icon")

      if is_map(icon) && Map.has_key?(icon, "url") do
        %Embed.Thumbnail{url: icon["url"]}
      else
        nil
      end
    else
      nil
    end
  end

  # Validate URL is not empty
  defp extract_valid_url(url) when is_binary(url) do
    trimmed = String.trim(url)
    if trimmed == "", do: nil, else: trimmed
  end

  defp extract_valid_url(_), do: nil

  # Extract image from embed
  defp extract_image(embed) do
    image = get_field_with_fallback(embed, :image, "image")

    case extract_image_from_map(image) do
      {:ok, url} ->
        %Embed.Image{url: url}

      {:error, _} ->
        cond do
          valid_url = extract_valid_url(image) ->
            %Embed.Image{url: valid_url}

          valid_url = extract_valid_url(get_field_with_fallback(embed, :image_url, "image_url")) ->
            %Embed.Image{url: valid_url}

          true ->
            nil
        end
    end
  end

  # Extract image data from a map structure
  defp extract_image_from_map(data) when is_map(data) do
    if Map.has_key?(data, "image") and is_map(data["image"]) and
         Map.has_key?(data["image"], "url") do
      {:ok, data["image"]["url"]}
    else
      {:error, "No image URL found in map"}
    end
  end

  defp extract_image_from_map(_), do: {:error, "Data is not a map"}

  defp get_retry_after(%{headers: headers}) when is_list(headers) do
    # Prefer Discord's X-RateLimit-Reset-After (seconds, can be fractional), fallback to Retry-After
    lower_headers = normalize_headers(headers)

    # Try X-RateLimit-Reset-After first
    case parse_retry_header(lower_headers, "x-ratelimit-reset-after") do
      {:ok, ms} ->
        clamp_ms(ms)

      :error ->
        # Fallback to Retry-After
        case parse_retry_header(lower_headers, "retry-after") do
          {:ok, ms} -> clamp_ms(ms)
          :error -> 5_000
        end
    end
  rescue
    _ -> 5_000
  end

  defp get_retry_after(_) do
    5_000
  end

  defp normalize_headers(headers) do
    Enum.into(headers, %{}, fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
  end

  defp parse_retry_header(headers, header_name) do
    case Map.get(headers, header_name) do
      nil ->
        :error

      v ->
        case Float.parse(v) do
          {sec, _} -> {:ok, trunc(sec * 1000)}
          :error -> :error
        end
    end
  end

  # Clamp retry-after milliseconds to reasonable bounds (0 to 120 seconds)
  defp clamp_ms(ms) when is_integer(ms) do
    ms
    |> max(0)
    |> min(120_000)
  end

  # Helper function to check Nostrum API Ratelimiter state
  defp get_ratelimiter_state do
    try do
      case Process.whereis(Nostrum.Api.Ratelimiter) do
        nil ->
          %{status: :not_started, pid: nil}

        pid when is_pid(pid) ->
          # Get process info for diagnostics
          info = Process.info(pid, [:message_queue_len, :status, :memory])

          %{
            status: :running,
            pid: inspect(pid),
            message_queue_len: info[:message_queue_len],
            process_status: info[:status],
            memory_kb: div(info[:memory] || 0, 1024)
          }
      end
    rescue
      _ -> %{status: :unknown, error: "failed to get state"}
    end
  end

  # Helper function to check Nostrum WebSocket state
  defp get_nostrum_state do
    # Check if Nostrum's websocket connection is established
    # This is a simple check - you might need to enhance based on Nostrum's API
    case Process.whereis(Nostrum.Shard.Supervisor) do
      nil -> :not_started
      pid when is_pid(pid) -> check_nostrum_supervisor_state(pid)
    end
  rescue
    _ -> :unknown
  end

  defp check_nostrum_supervisor_state(pid) do
    if Process.alive?(pid) do
      # Check if we have any active shards
      case Supervisor.which_children(pid) do
        [] -> :no_shards
        children -> check_shard_connections(children)
      end
    else
      :supervisor_dead
    end
  end

  defp check_shard_connections(children) do
    # Check if any shard is connected
    connected =
      Enum.any?(children, fn {_, pid, _, _} ->
        is_pid(pid) && Process.alive?(pid)
      end)

    if connected, do: :connected, else: :disconnected
  end

  # Calculate the approximate size of an embed in bytes
  defp calculate_embed_size(embed) do
    # Convert embed to JSON and calculate byte size
    case Jason.encode(embed) do
      {:ok, json} -> byte_size(json)
      {:error, _} -> 0
    end
  rescue
    _ -> 0
  end

  # Check rate limit status (placeholder - enhance with actual Nostrum rate limit tracking)
  defp check_rate_limit_status(_channel_id) do
    # This is a placeholder. In production, you'd want to track rate limits
    # from previous Discord API responses (X-RateLimit headers)
    # For now, we'll just return not limited
    %{limited: false, retry_after: 0}
  end

  # Log Gun connection pool status for diagnostics
  defp log_gun_pool_status do
    # Only run expensive diagnostics at debug level
    if Logger.compare_levels(Logger.level(), :debug) != :gt do
      # Try to get Gun connection info from Nostrum
      # This is approximate since Nostrum manages Gun internally
      try do
        # Check for Gun processes
        gun_processes =
          Process.list()
          |> Enum.filter(&gun_process?/1)
          |> length()

        Logger.debug("Gun connection pool status",
          gun_processes: gun_processes,
          category: :discord_api
        )
      rescue
        _ -> :ok
      end
    end
  end

  # Checks if a process is a Gun connection process.
  # Delegates to the shared ProcessInspection helper for consistent diagnostics.
  # Returns true only on {:ok, true}, false for {:ok, false} or {:error, _}.
  defp gun_process?(pid) do
    alias WandererNotifier.Infrastructure.ProcessInspection

    case ProcessInspection.detect_gun_process(pid) do
      {:ok, true} -> true
      {:ok, false} -> false
      {:error, _reason} -> false
    end
  end

  # Log system diagnostics when timeout occurs
  defp log_system_diagnostics do
    try do
      # Get process count
      process_count = length(Process.list())

      # Get memory info
      memory_info = :erlang.memory()

      # Get scheduler info
      schedulers_online = :erlang.system_info(:schedulers_online)

      Logger.warning("System diagnostics at timeout",
        process_count: process_count,
        memory_mb: div(memory_info[:total], 1_048_576),
        schedulers_online: schedulers_online,
        category: :discord_api
      )
    rescue
      _ -> :ok
    end
  end
end
