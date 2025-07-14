defmodule WandererNotifier.Map.SSESupervisor do
  @moduledoc """
  Supervisor for SSE client processes.

  This supervisor manages the lifecycle of SSE clients for different maps,
  providing fault tolerance and restart capabilities.
  """

  use Supervisor
  require Logger

  alias WandererNotifier.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger
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
        AppLogger.api_info("SSE client started", map_slug: map_slug)
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        AppLogger.api_info("SSE client already running", map_slug: map_slug)
        {:ok, pid}

      {:error, reason} = error ->
        AppLogger.api_error("Failed to start SSE client",
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
            AppLogger.api_info("SSE client stopped", map_slug: map_slug)
            :ok

          {:error, reason} = error ->
            AppLogger.api_error("Failed to delete SSE client",
              map_slug: map_slug,
              error: inspect(reason)
            )

            error
        end

      {:error, :not_found} ->
        AppLogger.api_info("SSE client not found", map_slug: map_slug)
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
        AppLogger.api_info("SSE client restarted", map_slug: map_slug)
        :ok

      {:error, reason} = error ->
        AppLogger.api_error("Failed to restart SSE client",
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
    case initialize_map_data_safely() do
      :ok ->
        AppLogger.api_info("Map data initialized successfully")
        
      :error ->
        AppLogger.api_warn("Map data initialization failed, continuing with SSE")
    end
    
    # Then start SSE clients
    case get_map_configuration() do
      {:ok, map_config} ->
        start_sse_client_from_config(map_config)

      {:error, reason} ->
        AppLogger.api_error("Failed to initialize SSE clients",
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
        AppLogger.api_error("Exception during map data initialization",
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

    # Use a timeout to prevent indefinite blocking during SSE client startup
    # 30 seconds timeout
    timeout = 30_000

    try do
      task = Task.async(fn -> start_sse_client(opts) end)

      case Task.await(task, timeout) do
        {:ok, _pid} ->
          AppLogger.api_info("SSE client initialized successfully",
            map_slug: map_config.map_slug
          )

          :ok

        {:error, reason} ->
          AppLogger.api_error("Failed to start SSE client",
            map_slug: map_config.map_slug,
            error: inspect(reason)
          )

          :ok
      end
    catch
      :exit, {:timeout, _} ->
        AppLogger.api_error("SSE client initialization timed out",
          map_slug: map_config.map_slug,
          timeout: timeout
        )

        :ok
    end
  end
end
