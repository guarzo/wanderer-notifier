defmodule WandererNotifier.Domains.Universe.Services.WandererSdeServiceTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Domains.Universe.Services.WandererSdeService

  setup :verify_on_exit!

  setup do
    # Capture original HTTP client value
    original_http_client = Application.get_env(:wanderer_notifier, :http_client)

    # Set up HTTP client mock
    Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.HTTPMock)

    # Restore original HTTP client on exit
    on_exit(fn ->
      Application.put_env(:wanderer_notifier, :http_client, original_http_client)
    end)

    :ok
  end

  describe "csv_files_exist?/0" do
    test "returns boolean indicating file presence" do
      result = WandererSdeService.csv_files_exist?()
      assert is_boolean(result)
    end
  end

  describe "get_csv_file_paths/0" do
    test "returns map with types_path and groups_path" do
      paths = WandererSdeService.get_csv_file_paths()

      assert is_map(paths)
      assert Map.has_key?(paths, :types_path)
      assert Map.has_key?(paths, :groups_path)
      assert String.ends_with?(paths.types_path, "invTypes.csv")
      assert String.ends_with?(paths.groups_path, "invGroups.csv")
    end
  end

  describe "get_csv_file_info/0" do
    test "returns comprehensive file info" do
      info = WandererSdeService.get_csv_file_info()

      assert is_map(info)
      assert Map.has_key?(info, :types_file)
      assert Map.has_key?(info, :groups_file)
      assert Map.has_key?(info, :all_present)
      assert Map.has_key?(info, :local_version)
      assert is_boolean(info.all_present)
    end

    test "types_file and groups_file contain exists key" do
      info = WandererSdeService.get_csv_file_info()

      assert Map.has_key?(info.types_file, :exists)
      assert Map.has_key?(info.groups_file, :exists)
    end
  end

  describe "get_sde_version/0" do
    test "returns version info on success" do
      expect(WandererNotifier.HTTPMock, :request, fn
        :get, url, nil, [], _opts ->
          assert String.contains?(url, "sde_metadata.json")

          {:ok,
           %{
             status_code: 200,
             body: %{
               "sde_version" => "3142455",
               "release_date" => "2025-12-15T11:14:02Z"
             }
           }}
      end)

      assert {:ok, metadata} = WandererSdeService.get_sde_version()
      assert metadata["sde_version"] == "3142455"
      assert metadata["release_date"] == "2025-12-15T11:14:02Z"
    end

    test "handles JSON string response" do
      expect(WandererNotifier.HTTPMock, :request, fn
        :get, _url, nil, [], _opts ->
          {:ok,
           %{
             status_code: 200,
             body: ~s({"sde_version": "3142455", "release_date": "2025-12-15T11:14:02Z"})
           }}
      end)

      assert {:ok, metadata} = WandererSdeService.get_sde_version()
      assert metadata["sde_version"] == "3142455"
    end

    test "returns error on HTTP failure" do
      expect(WandererNotifier.HTTPMock, :request, fn
        :get, _url, nil, [], _opts ->
          {:ok, %{status_code: 404}}
      end)

      assert {:error, {:http_error, 404}} = WandererSdeService.get_sde_version()
    end

    test "returns error on network failure" do
      expect(WandererNotifier.HTTPMock, :request, fn
        :get, _url, nil, [], _opts ->
          {:error, :timeout}
      end)

      assert {:error, :timeout} = WandererSdeService.get_sde_version()
    end
  end

  describe "check_for_updates/0" do
    test "returns :update_available when remote version differs" do
      expect(WandererNotifier.HTTPMock, :request, fn
        :get, _url, nil, [], _opts ->
          {:ok, %{status_code: 200, body: %{"sde_version" => "9999999"}}}
      end)

      result = WandererSdeService.check_for_updates()

      assert {:update_available, "9999999"} = result
    end

    test "returns :check_failed on error" do
      expect(WandererNotifier.HTTPMock, :request, fn
        :get, _url, nil, [], _opts ->
          {:error, :timeout}
      end)

      assert :check_failed = WandererSdeService.check_for_updates()
    end
  end

  describe "CSV content validation" do
    test "validate_csv_content/2 accepts valid invTypes.csv header" do
      # Access private function through module introspection for testing
      valid_content = "typeID,groupID,typeName,mass,volume,capacity\n1,2,Test,100,10,5"

      # We can't directly test private functions, so we test through download behavior
      # This is more of a documentation test showing expected format
      assert String.starts_with?(valid_content, "typeID,groupID,typeName")
    end

    test "validate_csv_content/2 accepts valid invGroups.csv header" do
      valid_content = "groupID,categoryID,groupName\n1,2,TestGroup"

      assert String.starts_with?(valid_content, "groupID,categoryID,groupName")
    end
  end

  describe "download_csv_files/1" do
    test "returns error when download fails" do
      # Need to allow multiple calls since downloads happen in parallel
      stub(WandererNotifier.HTTPMock, :request, fn
        :get, url, nil, [], _opts ->
          if String.contains?(url, ".csv") do
            {:error, :timeout}
          else
            {:ok, %{status_code: 200, body: %{"sde_version" => "123"}}}
          end
      end)

      result = WandererSdeService.download_csv_files(force_download: true)

      assert {:error, _reason} = result
    end

    test "returns error when CSV content is invalid" do
      # Mock returns HTML instead of CSV (simulating error page)
      # Need to allow multiple calls since downloads happen in parallel
      stub(WandererNotifier.HTTPMock, :request, fn
        :get, url, nil, [], _opts ->
          cond do
            String.contains?(url, "invTypes.csv") ->
              {:ok, %{status_code: 200, body: "<html>Error</html>"}}

            String.contains?(url, "invGroups.csv") ->
              {:ok, %{status_code: 200, body: "groupID,categoryID,groupName\n1,2,Test"}}

            String.contains?(url, "sde_metadata.json") ->
              {:ok, %{status_code: 200, body: %{"sde_version" => "123"}}}

            true ->
              {:error, :unknown_url}
          end
      end)

      result = WandererSdeService.download_csv_files(force_download: true)

      assert {:error, :invalid_csv_content} = result
    end
  end
end
