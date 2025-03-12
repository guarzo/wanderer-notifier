defmodule WandererNotifier.ApplicationTest do
  use ExUnit.Case
  import Mox
  import ExUnit.CaptureLog
  alias WandererNotifier.Application, as: WandererApp
  require Logger

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Reset environment variables before each test
    Application.put_env(:wanderer_notifier, :license_key, "test_license_key")
    Application.put_env(:wanderer_notifier, :license_manager_api_url, "https://test.license.manager")
    Application.put_env(:wanderer_notifier, :bot_registration_token, "test_bot_token")

    # Make sure we're using our mocks
    original_license_module = Application.get_env(:wanderer_notifier, :license_module)

    # Override the modules with our mocks
    Application.put_env(:wanderer_notifier, :license_module, WandererNotifier.LicenseMock)

    on_exit(fn ->
      # Restore original modules
      Application.put_env(:wanderer_notifier, :license_module, original_license_module)
    end)

    :ok
  end

  describe "validate_license/0" do
    test "logs success when the license is valid" do
      # Set up expectations
      WandererNotifier.LicenseMock
      |> expect(:validate, fn -> true end)

      log =
        capture_log(fn ->
          WandererApp.validate_license()
        end)

      assert log =~ "License validation successful"
    end

    test "continues with limited functionality when the license is invalid" do
      # Set up expectations
      WandererNotifier.LicenseMock
      |> expect(:validate, fn -> false end)

      log =
        capture_log(fn ->
          WandererApp.validate_license()
        end)

      assert log =~ "Invalid license. The application will continue with limited functionality."
    end
  end
end
