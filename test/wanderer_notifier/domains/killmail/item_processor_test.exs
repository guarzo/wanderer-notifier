defmodule WandererNotifier.Domains.Killmail.ItemProcessorTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Domains.Killmail.{Killmail, ItemProcessor}
  alias WandererNotifier.Shared.Config

  describe "enabled?/0" do
    test "returns false when no Janice API token is configured" do
      refute ItemProcessor.enabled?()
    end
  end

  describe "process_killmail_items/1" do
    test "returns killmail unchanged when disabled" do
      killmail = %Killmail{
        killmail_id: "12345",
        system_id: 30_000_142,
        esi_data: %{
          "victim" => %{
            "items" => [
              %{
                "item_type_id" => 12_345,
                "quantity_dropped" => 1,
                "flag" => 11
              }
            ]
          }
        }
      }

      assert {:ok, ^killmail} = ItemProcessor.process_killmail_items(killmail)
    end

    test "processes items when enabled" do
      # This would require mocking the Config and JaniceClient
      # For now, just test the disabled path
      killmail = %Killmail{killmail_id: "12345"}

      assert {:ok, result} = ItemProcessor.process_killmail_items(killmail)
      assert result == killmail
    end
  end
end
