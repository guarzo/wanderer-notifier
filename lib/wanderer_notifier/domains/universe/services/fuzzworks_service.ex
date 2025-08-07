defmodule WandererNotifier.Domains.Universe.Services.FuzzworksService do
  @moduledoc """
  Service for downloading and processing EVE Online static data from Fuzzworks.

  Fuzzworks provides CSV exports of the EVE Online static data export (SDE)
  which we can use to get item names and ship types without hitting ESI.
  """

  require Logger
  alias WandererNotifier.Infrastructure.Http
  alias WandererNotifier.Shared.Utils.ErrorHandler

  @fuzzworks_base_url "https://www.fuzzwork.co.uk/dump/latest"
  @required_files ["invTypes.csv", "invGroups.csv"]
  @download_timeout 60_000

  @doc """
  Downloads the required CSV files from Fuzzworks.

  Returns the file paths where the CSV files were saved.
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
  """
  @spec get_csv_file_info() :: map()
  def get_csv_file_info do
    file_paths = get_csv_file_paths()

    %{
      types_file: get_file_info(file_paths.types_path),
      groups_file: get_file_info(file_paths.groups_path),
      all_present: csv_files_exist?()
    }
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
        Logger.info("Downloading #{length(missing_files)} CSV files from Fuzzworks")
        download_missing_files(missing_files, data_dir)
    end
  end

  defp ensure_data_directory(data_dir) do
    unless File.exists?(data_dir) do
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
        Logger.info("Successfully downloaded all CSV files")
        {:ok, get_csv_file_paths()}

      {:error, _} = error ->
        Logger.error("Failed to download some CSV files")
        error
    end
  end

  defp download_single_file(file_name, data_dir) do
    url = "#{@fuzzworks_base_url}/#{file_name}.bz2"
    output_path = Path.join(data_dir, file_name)

    Logger.info("Downloading #{file_name} from Fuzzworks")

    with {:ok, compressed_data} <- fetch_compressed_file(url),
         {:ok, decompressed_data} <- decompress_bz2(compressed_data),
         :ok <- File.write(output_path, decompressed_data) do
      Logger.info("Successfully downloaded and saved #{file_name}")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to download #{file_name}: #{inspect(reason)}")
        error
    end
  end

  defp fetch_compressed_file(url) do
    case Http.fuzzworks_get(url, [], timeout: @download_timeout) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decompress_bz2(compressed_data) do
    case System.find_executable("bzip2") do
      nil ->
        {:error, "bzip2 command not found - please install bzip2"}

      _path ->
        decompress_with_bzip2(compressed_data)
    end
  end

  defp decompress_with_bzip2(compressed_data) do
    temp_file = create_temp_file(compressed_data, ".bz2")

    try do
      case System.cmd("bzip2", ["-dc", temp_file], stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {error, _} -> {:error, "bzip2 decompression failed: #{error}"}
      end
    after
      File.rm(temp_file)
    end
  end

  defp create_temp_file(data, extension) do
    uuid = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    temp_path = Path.join(System.tmp_dir!(), "wanderer_notifier_#{uuid}#{extension}")

    File.write!(temp_path, data)
    temp_path
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
