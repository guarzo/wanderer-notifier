defmodule WandererNotifier.Map.SSESupervisor do
  @moduledoc """
  Supervisor for SSE client processes.

  This supervisor manages the lifecycle of SSE clients for different maps,
  providing fault tolerance and restart capabilities.
  """

  use Supervisor
  require Logger

  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Map.{Initializer, MapConfig, SSEClient}

  defp map_registry do
    Application.get_env(
      :wanderer_notifier,
      :map_registry_module,
      WandererNotifier.Map.MapRegistry
    )
  end

  @doc """
  Starts the SSE supervisor.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(_opts) do
    children = []

    # Start with empty children, we'll dynamically add SSE clients
    # when the application starts or when SSE is enabled
    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Starts an SSE client for a specific map.

  ## Parameters
  - `:map_slug` - The map slug for identification and SSE endpoint
  - `:api_token` - Authentication token
  - `:events` - Optional list of events to subscribe to
  """
  @spec start_sse_client(keyword()) :: Supervisor.on_start_child()
  def start_sse_client(opts) do
    map_slug = Keyword.fetch!(opts, :map_slug)

    child_spec = %{
      id: {:sse_client, map_slug},
      start: {SSEClient, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }

    case Supervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("SSE client started", map_slug: map_slug)
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.info("SSE client already running", map_slug: map_slug)
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start SSE client",
          map_slug: map_slug,
          error: inspect(reason)
        )

        error
    end
  end

  @doc """
  Stops an SSE client for a specific map.
  """
  @spec stop_sse_client(String.t()) :: :ok | {:error, term()}
  def stop_sse_client(map_slug) do
    child_id = {:sse_client, map_slug}

    case Supervisor.terminate_child(__MODULE__, child_id) do
      :ok ->
        case Supervisor.delete_child(__MODULE__, child_id) do
          :ok ->
            Logger.info("SSE client stopped", map_slug: map_slug)
            :ok

          {:error, reason} = error ->
            Logger.error("Failed to delete SSE client",
              map_slug: map_slug,
              error: inspect(reason)
            )

            error
        end

      {:error, :not_found} ->
        Logger.info("SSE client not found", map_slug: map_slug)
        :ok
    end
  end

  @doc """
  Restarts an SSE client for a specific map.
  """
  @spec restart_sse_client(String.t()) :: :ok | {:error, term()}
  def restart_sse_client(map_slug) do
    child_id = {:sse_client, map_slug}

    case Supervisor.restart_child(__MODULE__, child_id) do
      {:ok, _pid} ->
        Logger.info("SSE client restarted", map_slug: map_slug)
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to restart SSE client",
          map_slug: map_slug,
          error: inspect(reason)
        )

        error
    end
  end

  @doc """
  Gets the status of all running SSE clients.
  """
  @spec get_client_status() :: [map()]
  def get_client_status() do
    Supervisor.which_children(__MODULE__)
    |> Enum.map(fn {child_id, pid, _type, _modules} ->
      case child_id do
        {:sse_client, map_slug} when is_pid(pid) ->
          status = SSEClient.get_status(map_slug)
          %{map_slug: map_slug, pid: pid, status: status}

        _ ->
          %{child_id: child_id, pid: pid, status: :unknown}
      end
    end)
  end

  @doc """
  Initializes SSE clients based on application configuration.

  In multi-map mode (API), initializes data and starts SSE clients for all
  maps from the map_registry(). In legacy mode, falls back to single-map behavior.

  This function is called during application startup.
  """
  @spec initialize_sse_clients() :: :ok
  def initialize_sse_clients() do
    case map_registry().mode() do
      :api -> initialize_multi_map()
      :legacy -> initialize_legacy()
    end
  end

  @doc """
  Handles dynamic map additions/removals from MapRegistry PubSub.
  """
  @spec handle_maps_updated(map()) :: :ok
  def handle_maps_updated(%{added: added, removed: removed}) do
    # Stop removed maps
    Enum.each(removed, fn slug ->
      Logger.info("Stopping SSE client for removed map", map_slug: slug)
      stop_sse_client(slug)
    end)

    # Start added maps (with initialization)
    Enum.each(added, &start_added_map/1)

    :ok
  end

  defp start_added_map(slug) do
    case map_registry().get_map(slug) do
      {:ok, map_config} ->
        handle_map_start_result(slug, initialize_and_start_for_map(map_config))

      {:error, _} ->
        Logger.warning("Map config not found for added slug", map_slug: slug)
    end
  end

  defp handle_map_start_result(slug, {:ok, _pid}) do
    Logger.info("SSE client started for new map", map_slug: slug)
  end

  defp handle_map_start_result(slug, {:error, reason}) do
    Logger.error("Failed to initialize and start SSE client for new map",
      map_slug: slug,
      reason: inspect(reason)
    )
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Multi-Map Initialization
  # ──────────────────────────────────────────────────────────────────────────────

  defp initialize_multi_map do
    maps = map_registry().all_maps()
    Logger.info("Initializing #{length(maps)} maps from registry", category: :startup)

    successful_maps = run_parallel_init(maps)

    # Signal PipelineWorker
    signal_pipeline_worker()

    # Start SSE clients only for successfully initialized maps
    start_sse_clients_staggered(successful_maps)
  end

  defp run_parallel_init(maps) do
    # Initialize data for all maps (parallelized with concurrency limit)
    # Zip results with original maps to preserve map context on exit
    results =
      maps
      |> Task.async_stream(
        fn map -> {map, initialize_map_data_safely(map)} end,
        max_concurrency: 10,
        timeout: 60_000
      )
      |> Enum.zip(maps)

    {succeeded, failed} = partition_init_results(results)

    log_initialization_failures(failed)

    successful_maps = Enum.map(succeeded, fn {{:ok, {map, _}}, _} -> map end)

    if failed != [] do
      Logger.warning(
        "#{length(failed)}/#{length(maps)} maps failed initialization, " <>
          "starting SSE for #{length(successful_maps)} maps",
        category: :startup
      )
    end

    successful_maps
  end

  defp partition_init_results(results) do
    {succeeded, failed_raw} =
      Enum.split_with(results, fn
        {{:ok, {_map, {:ok, _}}}, _original_map} -> true
        _ -> false
      end)

    failed_items =
      Enum.map(failed_raw, fn
        {{:ok, {map, {:error, reason}}}, _} -> {map, reason}
        {{:exit, reason}, original_map} -> {original_map, {:exit, reason}}
        {_, original_map} -> {original_map, :unknown}
      end)

    {succeeded, failed_items}
  end

  defp log_initialization_failures(failed) do
    Enum.each(failed, fn
      {%MapConfig{} = mc, reason} ->
        Logger.warning("Map initialization failed",
          map_slug: mc.slug,
          map_name: mc.name,
          reason: inspect(reason)
        )

      {nil, reason} ->
        Logger.warning("Map initialization failed (unknown map)",
          reason: inspect(reason)
        )
    end)
  end

  defp initialize_and_start_for_map(map_config) do
    case initialize_map_data_safely(map_config) do
      {:ok, _} ->
        start_sse_client_for_map(map_config)

      {:error, reason} ->
        Logger.warning("Map data initialization failed, skipping SSE client start",
          map_slug: map_config.slug,
          reason: inspect(reason)
        )

        {:error, {:init_failed, reason}}
    end
  end

  defp start_sse_clients_staggered(maps) do
    results =
      maps
      |> Task.async_stream(&start_sse_client_for_map/1,
        max_concurrency: 5,
        timeout: 30_000
      )
      |> Enum.to_list()

    {succeeded, failed} =
      Enum.split_with(results, fn
        {:ok, {:ok, _pid}} -> true
        _ -> false
      end)

    succeeded_count = length(succeeded)
    failed_count = length(failed)

    if failed_count > 0 do
      Enum.each(failed, fn
        {:ok, {:error, reason}} ->
          Logger.warning("SSE client startup failed", reason: inspect(reason))

        {:exit, reason} ->
          Logger.warning("SSE client startup task exited", reason: inspect(reason))

        _ ->
          :ok
      end)

      Logger.warning(
        "SSE client startup: #{succeeded_count} succeeded, #{failed_count} failed out of #{length(maps)}",
        category: :startup
      )
    else
      Logger.info("Started #{succeeded_count} SSE clients", category: :startup)
    end
  end

  defp start_sse_client_for_map(%MapConfig{} = map_config) do
    opts = [
      map_slug: map_config.slug,
      api_token: map_config.api_token || Config.map_api_key()
    ]

    case start_sse_client(opts) do
      {:ok, pid} ->
        Logger.info("SSE client started", map_slug: map_config.slug)
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start SSE client",
          map_slug: map_config.slug,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @spec initialize_map_data_safely(MapConfig.t()) :: {:ok, :initialized} | {:error, term()}
  defp initialize_map_data_safely(%MapConfig{} = map_config) do
    Initializer.initialize_map_data_for(map_config)
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Legacy Single-Map Initialization
  # ──────────────────────────────────────────────────────────────────────────────

  defp initialize_legacy do
    case initialize_legacy_map_data() do
      :ok ->
        Logger.info("Map data initialized successfully")
        start_legacy_sse()

      :error ->
        Logger.error("Map data initialization failed - SSE will not start",
          reason: "Cannot start SSE without initial data to prevent notification spam"
        )

        :ok
    end
  end

  defp initialize_legacy_map_data do
    Initializer.initialize_map_data()
    :ok
  rescue
    error ->
      Logger.error("Exception during map data initialization",
        error: Exception.message(error)
      )

      :error
  end

  defp start_legacy_sse do
    signal_pipeline_worker()

    case get_legacy_map_configuration() do
      {:ok, config} ->
        opts = [map_slug: config.map_slug, api_token: config.api_token]

        case start_sse_client(opts) do
          {:ok, _pid} ->
            Logger.info("SSE client initialized", map_slug: config.map_slug)
            :ok

          {:error, reason} ->
            Logger.error("Failed to start SSE client", error: inspect(reason))
            :ok
        end

      {:error, reason} ->
        Logger.error("Failed to get map configuration: #{inspect(reason)}")
        :ok
    end
  end

  defp get_legacy_map_configuration do
    map_url = Config.map_url()
    map_name = Config.map_name()
    api_token = Config.map_api_key()
    map_slug = extract_map_slug(map_url, map_name)

    {:ok, %{map_slug: map_slug, api_token: api_token}}
  rescue
    e -> {:error, {:config_error, Exception.message(e)}}
  end

  defp extract_map_slug(map_url, map_name) do
    case URI.parse(map_url) do
      %URI{query: query} when is_binary(query) ->
        query
        |> URI.decode_query()
        |> Map.get("name", map_name)

      _ ->
        map_name
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Shared Helpers
  # ──────────────────────────────────────────────────────────────────────────────

  defp signal_pipeline_worker do
    case Process.whereis(WandererNotifier.Domains.Killmail.PipelineWorker) do
      nil ->
        Logger.warning("PipelineWorker not found - cannot signal map initialization complete")

      pid ->
        Logger.info("Signaling PipelineWorker that map initialization is complete")
        send(pid, :map_initialization_complete)
    end
  end
end
