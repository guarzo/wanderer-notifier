defmodule WandererNotifier.Domains.Universe.Services.WandererSdeService do
  @moduledoc """
  Service for downloading and managing EVE Online static data from Wanderer SDE.

  Replaces FuzzworksService with direct access to uncompressed CSV files
  from the wanderer-assets GitHub repository. No bzip2 decompression required.

  ## Data Source

  Files are downloaded from:
  `https://raw.githubusercontent.com/wanderer-industries/wanderer-assets/main/sde-files`

  ## Available Files

  - `invTypes.csv` - Item type definitions (typeID, groupID, typeName, mass, volume, capacity)
  - `invGroups.csv` - Item group classifications (groupID, categoryID, groupName)
  - `sde_metadata.json` - Version and generation metadata

  ## Usage

      # Download CSV files
      {:ok, paths} = WandererSdeService.download_csv_files()

      # Check if files exist locally
      WandererSdeService.csv_files_exist?()

      # Get file paths
      %{types_path: path1, groups_path: path2} = WandererSdeService.get_csv_file_paths()

      # Get SDE version info
      {:ok, %{"sde_version" => version}} = WandererSdeService.get_sde_version()
  """

  require Logger
  alias WandererNotifier.Infrastructure.Http
  alias WandererNotifier.Shared.Utils.ErrorHandler

  @sde_base_url "https://raw.githubusercontent.com/wanderer-industries/wanderer-assets/main/sde-files"
  @metadata_url "#{@sde_base_url}/sde_metadata.json"
  @required_files ["invTypes.csv", "invGroups.csv"]
  @download_timeout 60_000

  @doc """
  Downloads the required CSV files from Wanderer SDE.

  Unlike FuzzworksService, files are downloaded directly without decompression.

  ## Options

  - `:force_download` - If true, re-downloads all files even if they exist (default: false)

  ## Returns

  - `{:ok, %{types_path: path, groups_path: path}}` on success
  - `{:error, reason}` on failure
  """
  @spec download_csv_files(keyword()) :: {:ok, map()} | {:error, term()}
  def download_csv_files(opts \\ []) do
    force_download = Keyword.get(opts, :force_download, false)
    data_dir = get_data_directory()

    ErrorHandler.safe_execute(
      fn -> do_download_csv_files(data_dir, force_download) end,
      context: %{data_dir: data_dir, force_download: force_download}
    )
  end

  @doc """
  Checks if all required CSV files exist locally.

  ## Returns

  - `true` if all files exist
  - `false` if any file is missing
  """
  @spec csv_files_exist?() :: boolean()
  def csv_files_exist? do
    data_dir = get_data_directory()

    @required_files
    |> Enum.all?(fn file_name ->
      data_dir
      |> Path.join(file_name)
      |> File.exists?()
    end)
  end

  @doc """
  Gets the paths to the local CSV files.

  ## Returns

  Map with `:types_path` and `:groups_path` keys.
  """
  @spec get_csv_file_paths() :: map()
  def get_csv_file_paths do
    data_dir = get_data_directory()

    %{
      types_path: Path.join(data_dir, "invTypes.csv"),
      groups_path: Path.join(data_dir, "invGroups.csv")
    }
  end

  @doc """
  Gets information about the current CSV files.

  ## Returns

  Map containing file information and whether all files are present.
  """
  @spec get_csv_file_info() :: map()
  def get_csv_file_info do
    file_paths = get_csv_file_paths()

    %{
      types_file: get_file_info(file_paths.types_path),
      groups_file: get_file_info(file_paths.groups_path),
      all_present: csv_files_exist?(),
      local_version: get_local_version()
    }
  end

  @doc """
  Fetches the current SDE version from the remote metadata file.

  ## Returns

  - `{:ok, metadata_map}` with version info on success
  - `{:error, reason}` on failure

  ## Example

      {:ok, %{"sde_version" => "3142455", "release_date" => "2025-12-15T11:14:02Z"}}
  """
  @spec get_sde_version() :: {:ok, map()} | {:error, term()}
  def get_sde_version do
    case Http.wanderer_sde_get(@metadata_url, [], decode_json: true) do
      {:ok, %{status_code: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status_code: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end

      {:ok, %{status_code: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if an update is available by comparing local and remote versions.

  ## Returns

  - `{:update_available, remote_version}` if a newer version exists
  - `:up_to_date` if local version matches remote
  - `:check_failed` if unable to determine
  """
  @spec check_for_updates() :: {:update_available, String.t()} | :up_to_date | :check_failed
  def check_for_updates do
    case get_sde_version() do
      {:ok, %{"sde_version" => remote_version}} ->
        current_version = get_local_version()

        if remote_version != current_version do
          Logger.info("New SDE version available: #{remote_version} (current: #{current_version})")
          {:update_available, remote_version}
        else
          :up_to_date
        end

      {:error, _} ->
        :check_failed
    end
  end

  # Private functions

  defp do_download_csv_files(data_dir, force_download) do
    ensure_data_directory(data_dir)

    files_to_download =
      if force_download do
        cleanup_existing_files(data_dir)
        @required_files
      else
        get_missing_files(data_dir)
      end

    case files_to_download do
      [] ->
        Logger.info("All CSV files already exist")
        {:ok, get_csv_file_paths()}

      missing_files ->
        Logger.info("Downloading #{length(missing_files)} CSV files from Wanderer SDE")
        download_missing_files(missing_files, data_dir)
    end
  end

  defp ensure_data_directory(data_dir) do
    if !File.exists?(data_dir) do
      File.mkdir_p!(data_dir)
      Logger.debug("Created data directory: #{data_dir}")
    end
  end

  defp cleanup_existing_files(data_dir) do
    @required_files
    |> Enum.each(fn file ->
      file_path = Path.join(data_dir, file)

      if File.exists?(file_path) do
        File.rm!(file_path)
        Logger.debug("Removed existing file: #{file}")
      end
    end)

    # Also remove local version file
    version_path = Path.join(data_dir, "sde_version.txt")

    if File.exists?(version_path) do
      File.rm!(version_path)
    end
  end

  defp get_missing_files(data_dir) do
    @required_files
    |> Enum.reject(fn file_name ->
      data_dir
      |> Path.join(file_name)
      |> File.exists?()
    end)
  end

  defp download_missing_files(file_names, data_dir) do
    results =
      file_names
      |> Enum.map(fn file_name ->
        Task.async(fn -> download_single_file(file_name, data_dir) end)
      end)
      |> Task.await_many(@download_timeout)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        # All files downloaded successfully, save version info
        save_version_info(data_dir)
        Logger.info("Successfully downloaded all CSV files from Wanderer SDE")
        {:ok, get_csv_file_paths()}

      {:error, _} = error ->
        Logger.error("Failed to download some CSV files from Wanderer SDE")
        error
    end
  end

  defp download_single_file(file_name, data_dir) do
    url = "#{@sde_base_url}/#{file_name}"
    output_path = Path.join(data_dir, file_name)

    Logger.info("Downloading #{file_name} from Wanderer SDE")

    case fetch_file(url) do
      {:ok, data} ->
        case File.write(output_path, data) do
          :ok ->
            Logger.info("Successfully downloaded and saved #{file_name}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to write #{file_name}: #{inspect(reason)}")
            {:error, {:file_write_error, reason}}
        end

      {:error, reason} = error ->
        Logger.error("Failed to download #{file_name}: #{inspect(reason)}")
        error
    end
  end

  defp fetch_file(url) do
    case Http.wanderer_sde_get(url, [], timeout: @download_timeout) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp save_version_info(data_dir) do
    case get_sde_version() do
      {:ok, %{"sde_version" => version}} ->
        version_path = Path.join(data_dir, "sde_version.txt")
        File.write(version_path, version)
        Logger.debug("Saved SDE version: #{version}")

      {:error, _} ->
        Logger.warning("Could not fetch SDE version info")
    end
  end

  defp get_local_version do
    version_path = Path.join(get_data_directory(), "sde_version.txt")

    case File.read(version_path) do
      {:ok, version} -> String.trim(version)
      {:error, _} -> nil
    end
  end

  defp get_data_directory do
    Path.join([Application.app_dir(:wanderer_notifier), "priv", "data"])
  end

  defp get_file_info(file_path) do
    if File.exists?(file_path) do
      stat = File.stat!(file_path)

      %{
        exists: true,
        size: stat.size,
        modified: stat.mtime
      }
    else
      %{exists: false}
    end
  end
end
