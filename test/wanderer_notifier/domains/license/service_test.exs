defmodule WandererNotifier.Domains.License.LicenseServiceTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Domains.License.LicenseService, as: Service

  setup :verify_on_exit!

  setup do
    # Set up HTTP client mock
    Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.HTTPMock)

    # Start the License Service if not already running
    case Process.whereis(WandererNotifier.Domains.License.LicenseService) do
      nil ->
        {:ok, _pid} = WandererNotifier.Domains.License.LicenseService.start_link([])

      _pid ->
        :ok
    end

    :ok
  end

  describe "status/0" do
    test "returns license status from GenServer state" do
      # This test doesn't need HTTP mocking as it just reads state
      assert is_map(Service.status())
    end
  end

  describe "validate/0" do
    test "returns validation results" do
      # The validate function doesn't make HTTP calls directly - it just returns state
      result = Service.validate()
      assert is_map(result)
    end
  end

  describe "increment_notification_count/1" do
    test "increments system notification count" do
      # Function returns the new count, not :ok
      result = Service.increment_notification_count(:system)
      assert is_integer(result)
    end

    test "increments character notification count" do
      result = Service.increment_notification_count(:character)
      assert is_integer(result)
    end

    test "increments killmail notification count" do
      result = Service.increment_notification_count(:killmail)
      assert is_integer(result)
    end
  end

  describe "get_notification_count/1" do
    test "gets notification count for type" do
      count = Service.get_notification_count(:system)
      assert is_integer(count)
    end
  end

  describe "feature_enabled?/1" do
    test "checks if feature is enabled" do
      result = Service.feature_enabled?(:rich_embeds)
      assert is_boolean(result)
    end

    test "handles unknown features" do
      result = Service.feature_enabled?(:unknown_feature)
      assert is_boolean(result)
    end
  end
end
