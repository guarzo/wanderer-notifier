defmodule WandererNotifier.Infrastructure.Adapters.JaniceClientTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Infrastructure.Adapters.JaniceClient

  describe "enabled?/0" do
    test "returns false when no Janice API token is configured" do
      refute JaniceClient.enabled?()
    end
  end

  describe "format_appraisal_request/1" do
    test "formats items correctly for Janice API" do
      items = [
        %{"type_id" => 12_345, "quantity" => 1},
        %{"type_id" => 67_890, "quantity" => 5}
      ]

      expected = "12_345 1\n67_890 5"
      assert JaniceClient.format_appraisal_request(items) == expected
    end

    test "handles item_type_id key" do
      items = [
        %{"item_type_id" => 12_345, "quantity" => 2}
      ]

      expected = "12_345 2"
      assert JaniceClient.format_appraisal_request(items) == expected
    end

    test "defaults quantity to 1 when missing" do
      items = [
        %{"type_id" => 12_345}
      ]

      expected = "12_345 1"
      assert JaniceClient.format_appraisal_request(items) == expected
    end
  end

  describe "appraise_items/1" do
    test "returns error when not enabled" do
      items = [%{"type_id" => 12_345, "quantity" => 1}]

      assert {:error, :janice_not_configured} = JaniceClient.appraise_items(items)
    end
  end
end
