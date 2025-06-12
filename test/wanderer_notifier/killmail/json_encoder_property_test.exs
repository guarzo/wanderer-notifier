defmodule WandererNotifier.Killmail.JsonEncoderPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias WandererNotifier.Killmail.Killmail

  describe "JSON encoding/decoding round-trip properties" do
    property "any valid killmail can be encoded and decoded back" do
      check all killmail <- killmail_generator() do
        # Encode to JSON
        {:ok, json} = Jason.encode(killmail)

        # Decode back
        {:ok, decoded_map} = Jason.decode(json)

        # Create a new killmail from the decoded map
        decoded_killmail = Killmail.from_map(decoded_map)

        # Basic structure should be preserved
        # Note: from_map always converts killmail_id to string
        assert decoded_killmail.killmail_id == decoded_map["killmail_id"]
        assert decoded_killmail.zkb == killmail.zkb

        # If esi_data was present, it should be preserved
        if killmail.esi_data do
          assert decoded_killmail.esi_data == killmail.esi_data
        end
      end
    end

    property "encoded JSON contains all non-nil fields" do
      check all killmail <- killmail_generator() do
        {:ok, json} = Jason.encode(killmail)
        {:ok, decoded} = Jason.decode(json)

        # Check that all non-nil fields from the struct are in the JSON
        killmail
        |> Map.from_struct()
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Enum.each(fn {key, _value} ->
          assert Map.has_key?(decoded, Atom.to_string(key))
        end)
      end
    end

    property "nil values are handled properly in JSON" do
      check all killmail <- killmail_with_nils_generator() do
        {:ok, json} = Jason.encode(killmail)
        {:ok, decoded} = Jason.decode(json)

        # The encoder processes nil fields differently:
        # - Simple nil fields are removed
        # - But zkb, esi_data, and attackers are processed by Map.update which can add them back
        killmail
        |> Map.from_struct()
        |> Enum.filter(fn {_k, v} -> is_nil(v) end)
        |> Enum.each(fn {key, _value} ->
          key_str = Atom.to_string(key)
          if key_str in ["zkb", "esi_data", "attackers"] do
            # These fields might exist but be nil due to Map.update behavior
            if Map.has_key?(decoded, key_str) do
              assert decoded[key_str] == nil
            end
          else
            # Other nil fields should be excluded
            refute Map.has_key?(decoded, key_str)
          end
        end)
      end
    end
  end

  describe "nested structure encoding properties" do
    property "zkb data is properly encoded" do
      check all zkb_data <- zkb_generator() do
        killmail = %Killmail{
          killmail_id: "123456",
          zkb: zkb_data
        }

        {:ok, json} = Jason.encode(killmail)
        {:ok, decoded} = Jason.decode(json)

        assert decoded["zkb"] == zkb_data
      end
    end

    property "victim data in esi_data is preserved" do
      check all victim <- victim_generator() do
        esi_data = %{"victim" => victim, "solar_system_id" => 30_000_142}
        killmail = %Killmail{
          killmail_id: "123456",
          zkb: %{},
          esi_data: esi_data
        }

        {:ok, json} = Jason.encode(killmail)
        {:ok, decoded} = Jason.decode(json)

        assert decoded["esi_data"]["victim"] == victim
      end
    end

    property "attackers list is properly encoded" do
      check all attackers <- list_of(attacker_generator(), min_length: 0, max_length: 10) do
        esi_data = %{"attackers" => attackers, "solar_system_id" => 30_000_142}
        killmail = %Killmail{
          killmail_id: "123456",
          zkb: %{},
          esi_data: esi_data,
          attackers: attackers
        }

        {:ok, json} = Jason.encode(killmail)
        {:ok, decoded} = Jason.decode(json)

        assert decoded["attackers"] == attackers
        assert decoded["esi_data"]["attackers"] == attackers
      end
    end
  end

  describe "type conversion properties" do
    property "killmail_id can be string or integer" do
      check all id <- one_of([positive_integer(), string(:alphanumeric, min_length: 1)]) do
        killmail = %Killmail{
          killmail_id: id,
          zkb: %{}
        }

        {:ok, json} = Jason.encode(killmail)
        {:ok, decoded} = Jason.decode(json)

        # JSON preserves the type - numbers stay as numbers, strings as strings
        assert decoded["killmail_id"] == id
      end
    end

    property "numeric values are preserved" do
      check all value <- float(min: 0.0, max: 1_000_000_000.0),
                system_id <- positive_integer() do
        killmail = %Killmail{
          killmail_id: "123456",
          zkb: %{"totalValue" => value},
          value: value,
          system_id: system_id
        }

        {:ok, json} = Jason.encode(killmail)
        {:ok, decoded} = Jason.decode(json)

        assert decoded["value"] == value
        assert decoded["system_id"] == system_id
        assert decoded["zkb"]["totalValue"] == value
      end
    end
  end

  describe "edge cases and invariants" do
    property "empty structures are handled correctly" do
      check all killmail <- one_of([
                  constant(%Killmail{killmail_id: "1", zkb: %{}}),
                  constant(%Killmail{killmail_id: "2", zkb: %{}, esi_data: %{}}),
                  constant(%Killmail{killmail_id: "3", zkb: %{}, attackers: []})
                ]) do
        {:ok, json} = Jason.encode(killmail)
        {:ok, decoded} = Jason.decode(json)

        assert decoded["killmail_id"] == killmail.killmail_id
        assert decoded["zkb"] == %{}
      end
    end

    property "deeply nested structures are preserved" do
      check all depth <- integer(1..5) do
        # Create a nested structure
        nested = create_nested_map(depth)
        killmail = %Killmail{
          killmail_id: "nested",
          zkb: nested
        }

        {:ok, json} = Jason.encode(killmail)
        {:ok, decoded} = Jason.decode(json)

        assert decoded["zkb"] == nested
      end
    end
  end

  # Generators

  defp killmail_generator do
    gen all core_fields <- core_killmail_fields_generator(),
            victim_fields <- victim_fields_generator(),
            system_fields <- system_fields_generator(),
            optional_fields <- optional_fields_generator() do
      struct(Killmail, Map.merge(core_fields, Map.merge(victim_fields, Map.merge(system_fields, optional_fields))))
    end
  end

  defp core_killmail_fields_generator do
    gen all killmail_id <- one_of([positive_integer(), string(:alphanumeric, min_length: 1)]),
            zkb <- zkb_generator(),
            esi_data <- one_of([nil, esi_data_generator()]) do
      %{killmail_id: killmail_id, zkb: zkb, esi_data: esi_data}
    end
  end

  defp victim_fields_generator do
    gen all victim_name <- one_of([nil, string(:alphanumeric)]),
            victim_corporation <- one_of([nil, string(:alphanumeric)]),
            victim_corp_ticker <- one_of([nil, string(:alphanumeric, min_length: 1, max_length: 5)]),
            victim_alliance <- one_of([nil, string(:alphanumeric)]) do
      %{
        victim_name: victim_name,
        victim_corporation: victim_corporation,
        victim_corp_ticker: victim_corp_ticker,
        victim_alliance: victim_alliance
      }
    end
  end

  defp system_fields_generator do
    gen all ship_name <- one_of([nil, string(:alphanumeric)]),
            system_name <- one_of([nil, string(:alphanumeric)]),
            system_id <- one_of([nil, positive_integer()]) do
      %{ship_name: ship_name, system_name: system_name, system_id: system_id}
    end
  end

  defp optional_fields_generator do
    gen all attackers <- one_of([nil, list_of(attacker_generator(), max_length: 5)]),
            value <- one_of([nil, float(min: 0.0, max: 1_000_000_000.0)]) do
      %{attackers: attackers, value: value}
    end
  end

  defp killmail_with_nils_generator do
    gen all killmail_id <- string(:alphanumeric, min_length: 1),
            zkb <- zkb_generator() do
      %Killmail{
        killmail_id: killmail_id,
        zkb: zkb,
        esi_data: nil,
        victim_name: nil,
        victim_corporation: nil,
        victim_corp_ticker: nil,
        victim_alliance: nil,
        ship_name: nil,
        system_name: nil,
        system_id: nil,
        attackers: nil,
        value: nil
      }
    end
  end

  defp zkb_generator do
    map_of(
      string(:alphanumeric, min_length: 1),
      one_of([string(:alphanumeric), positive_integer(), float(), boolean()]),
      min_length: 0,
      max_length: 10
    )
  end

  defp esi_data_generator do
    gen all victim <- one_of([nil, victim_generator()]),
            attackers <- list_of(attacker_generator(), max_length: 5),
            solar_system_id <- positive_integer(),
            killmail_time <- string(:alphanumeric) do
      %{
        "victim" => victim,
        "attackers" => attackers,
        "solar_system_id" => solar_system_id,
        "killmail_time" => killmail_time
      }
    end
  end

  defp victim_generator do
    gen all character_id <- one_of([nil, positive_integer()]),
            corporation_id <- positive_integer(),
            alliance_id <- one_of([nil, positive_integer()]),
            ship_type_id <- positive_integer() do
      %{
        "character_id" => character_id,
        "corporation_id" => corporation_id,
        "alliance_id" => alliance_id,
        "ship_type_id" => ship_type_id
      }
    end
  end

  defp attacker_generator do
    gen all character_id <- one_of([nil, positive_integer()]),
            corporation_id <- positive_integer(),
            alliance_id <- one_of([nil, positive_integer()]),
            ship_type_id <- positive_integer(),
            weapon_type_id <- positive_integer(),
            damage_done <- positive_integer() do
      %{
        "character_id" => character_id,
        "corporation_id" => corporation_id,
        "alliance_id" => alliance_id,
        "ship_type_id" => ship_type_id,
        "weapon_type_id" => weapon_type_id,
        "damage_done" => damage_done
      }
    end
  end

  defp create_nested_map(0), do: %{"value" => "leaf"}
  defp create_nested_map(depth) do
    %{
      "level" => depth,
      "nested" => create_nested_map(depth - 1),
      "data" => "level_#{depth}"
    }
  end
end
