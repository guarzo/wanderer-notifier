defmodule WandererNotifier.Notifiers.FormatterTest do
  use ExUnit.Case

  alias WandererNotifier.Notifiers.Formatter

  describe "character data extraction" do
    test "extracts character_id from standard API format" do
      character_data = %{
        "character" => %{
          "name" => "Janissik",
          "alliance_id" => nil,
          "alliance_ticker" => nil,
          "corporation_id" => 98_551_135,
          "corporation_ticker" => "FLYSF",
          "eve_id" => "404850015"
        },
        "tracked" => true
      }

      assert Formatter.extract_character_id(character_data) == "404850015"
    end

    test "extracts character_id from notification format" do
      character_data = %{
        "character_id" => "404850015",
        "character_name" => "Janissik",
        "corporation_name" => "FLYSF",
        "corporation_id" => 98_551_135
      }

      assert Formatter.extract_character_id(character_data) == "404850015"
    end

    test "extracts character_name from standard API format" do
      character_data = %{
        "character" => %{
          "name" => "Janissik",
          "alliance_id" => nil,
          "alliance_ticker" => nil,
          "corporation_id" => 98_551_135,
          "corporation_ticker" => "FLYSF",
          "eve_id" => "404850015"
        },
        "tracked" => true
      }

      assert Formatter.extract_character_name(character_data) == "Janissik"
    end

    test "extracts character_name from notification format" do
      character_data = %{
        "character_id" => "404850015",
        "character_name" => "Janissik",
        "corporation_name" => "FLYSF",
        "corporation_id" => 98_551_135
      }

      assert Formatter.extract_character_name(character_data) == "Janissik"
    end

    test "extracts corporation_id from standard API format" do
      character_data = %{
        "character" => %{
          "name" => "Janissik",
          "alliance_id" => nil,
          "alliance_ticker" => nil,
          "corporation_id" => 98_551_135,
          "corporation_ticker" => "FLYSF",
          "eve_id" => "404850015"
        },
        "tracked" => true
      }

      assert Formatter.extract_corporation_id(character_data) == 98_551_135
    end

    test "extracts corporation_id from notification format" do
      character_data = %{
        "character_id" => "404850015",
        "character_name" => "Janissik",
        "corporation_name" => "FLYSF",
        "corporation_id" => 98_551_135
      }

      assert Formatter.extract_corporation_id(character_data) == 98_551_135
    end

    test "extracts corporation_name from standard API format" do
      character_data = %{
        "character" => %{
          "name" => "Janissik",
          "alliance_id" => nil,
          "alliance_ticker" => nil,
          "corporation_id" => 98_551_135,
          "corporation_ticker" => "FLYSF",
          "eve_id" => "404850015"
        },
        "tracked" => true
      }

      assert Formatter.extract_corporation_name(character_data) == "FLYSF"
    end

    test "extracts corporation_name from notification format" do
      character_data = %{
        "character_id" => "404850015",
        "character_name" => "Janissik",
        "corporation_name" => "FLYSF",
        "corporation_id" => 98_551_135
      }

      assert Formatter.extract_corporation_name(character_data) == "FLYSF"
    end

    test "handles missing values with defaults" do
      character_data = %{"character" => %{}}

      assert Formatter.extract_character_name(character_data) == "Unknown Character"
      assert Formatter.extract_corporation_name(character_data) == "Unknown Corporation"
      assert Formatter.extract_character_id(character_data) == nil
      assert Formatter.extract_corporation_id(character_data) == nil
    end
  end

  describe "statics formatting" do
    test "formats static list with destination information" do
      statics = [
        %{
          "name" => "E545",
          "destination" => %{
            "id" => "ns",
            "name" => "Null-sec",
            "short_name" => "N"
          }
        },
        %{
          "name" => "N062",
          "destination" => %{
            "id" => "c5",
            "name" => "Class 5",
            "short_name" => "C5"
          }
        }
      ]

      # Test through a private function wrapper
      formatted = apply_private(Formatter, :format_statics_list, [statics])
      assert formatted == "E545 (N), N062 (C5)"
    end

    test "handles simple string statics" do
      statics = ["E545", "N062"]

      # Test through a private function wrapper
      formatted = apply_private(Formatter, :format_statics_list, [statics])
      assert formatted == "E545, N062"
    end

    test "handles already formatted string" do
      statics = "E545, N062"

      # Test through a private function wrapper
      formatted = apply_private(Formatter, :format_statics_list, [statics])
      assert formatted == "E545, N062"
    end
  end

  # Helper to test private functions
  defp apply_private(module, function, args) do
    apply(module, function, args)
  end
end
