defmodule WandererNotifier.Map.SSESupervisor do
  @moduledoc """
  Supervisor for SSE client processes.

  This supervisor manages the lifecycle of SSE clients for different maps,
  providing fault tolerance and restart capabilities.
  """

  use Supervisor
  require Logger

  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Map.SSEClient

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
  - `:map_id` - The map UUID for SSE endpoint
  - `:map_slug` - The map slug for identification
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

  This function is called during application startup.
  """
  @spec initialize_sse_clients() :: :ok
  def initialize_sse_clients() do
    # First, initialize map data to populate the cache
    # This MUST complete before starting SSE to avoid notification spam
    case initialize_map_data_safely() do
      :ok ->
        Logger.info("Map data initialized successfully")
        # Only start SSE if we successfully loaded initial data
        start_sse_after_initialization()

      :error ->
        Logger.error("Map data initialization failed - SSE will not start",
          reason: "Cannot start SSE without initial data to prevent notification spam"
        )

        # Don't start SSE if we couldn't load initial data
        :ok
    end
  end

  defp start_sse_after_initialization do
    # Add a small delay to ensure cache writes are complete
    Process.sleep(1000)

    # Signal the WebSocket client that it can start now
    case Process.whereis(WandererNotifier.Domains.Killmail.PipelineWorker) do
      nil ->
        Logger.warning("PipelineWorker not found - cannot signal map initialization complete")

      pid ->
        Logger.info("Signaling PipelineWorker that map initialization is complete")
        send(pid, :map_initialization_complete)
    end

    case get_map_configuration() do
      {:ok, map_config} ->
        Logger.info("Starting SSE client after successful data initialization")
        start_sse_client_from_config(map_config)

      {:error, reason} ->
        Logger.error("Failed to initialize SSE clients",
          error: inspect(reason)
        )

        :ok
    end
  end

  defp initialize_map_data_safely do
    try do
      WandererNotifier.Map.Initializer.initialize_map_data()
      :ok
    rescue
      error ->
        Logger.error("Exception during map data initialization",
          error: Exception.message(error),
          stacktrace: __STACKTRACE__
        )

        :error
    end
  end

  # Private helper functions

  defp get_map_configuration() do
    map_url = Config.get(:map_url)
    map_name = Config.get(:map_name)
    api_token = Config.get(:map_token)

    if map_url && map_name && api_token do
      # Extract map slug from URL or use map_name
      map_slug = extract_map_slug(map_url, map_name)

      {:ok,
       %{
         map_slug: map_slug,
         api_token: api_token
       }}
    else
      {:error, :missing_configuration}
    end
  end

  defp extract_map_slug(map_url, map_name) do
    # Try to extract slug from URL parameters
    case URI.parse(map_url) do
      %URI{query: query} when is_binary(query) ->
        query
        |> URI.decode_query()
        |> Map.get("name", map_name)

      _ ->
        map_name
    end
  end

  defp start_sse_client_from_config(map_config) do
    opts = [
      map_slug: map_config.map_slug,
      api_token: map_config.api_token
      # Don't pass events at all - let it use defaults or none
    ]

    case start_sse_client(opts) do
      {:ok, _pid} ->
        Logger.info("SSE client initialized successfully",
          map_slug: map_config.map_slug
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to start SSE client",
          map_slug: map_config.map_slug,
          error: inspect(reason)
        )

        :ok
    end
  end
end
