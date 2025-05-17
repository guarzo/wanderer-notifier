defmodule WandererNotifier.Killmail.JsonEncoders do
  @moduledoc """
  Defines JSON encoding protocols for structs used in the application.
  """

  # Configure Jason.Encoder for the Killmail struct
  defimpl Jason.Encoder, for: WandererNotifier.Killmail.Killmail do
    def encode(struct, opts) do
      struct
      |> to_encodable_map()
      |> Jason.Encode.map(opts)
    end

    # Convert struct to a clean map for encoding
    defp to_encodable_map(struct) do
      struct
      |> Map.from_struct()
      |> remove_nil_values()
      |> process_zkb_data()
      |> process_esi_data()
      |> process_attackers()
    end

    # Remove nil values from map
    defp remove_nil_values(map) do
      map
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{})
    end

    # Process ZKB data field
    defp process_zkb_data(map) do
      Map.update(map, :zkb, nil, fn
        list when is_list(list) -> Map.new(list)
        other -> other
      end)
    end

    # Process ESI data field
    defp process_esi_data(map) do
      Map.update(map, :esi_data, nil, fn
        list when is_list(list) -> convert_keyword_list_map(list)
        other -> other
      end)
    end

    # Process attackers list
    defp process_attackers(map) do
      Map.update(map, :attackers, nil, fn
        list when is_list(list) ->
          Enum.map(list, fn
            attacker when is_list(attacker) -> Map.new(attacker)
            other -> other
          end)

        other ->
          other
      end)
    end

    # Convert nested keyword lists to maps
    defp convert_keyword_list_map(list) when is_list(list) do
      Enum.reduce(list, %{}, fn {key, value}, acc ->
        Map.put(acc, key, convert_value(value))
      end)
    end

    defp convert_value(list) when is_list(list) do
      Map.new(list)
    end

    defp convert_value(other), do: other
  end
end
