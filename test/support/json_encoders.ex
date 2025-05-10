defmodule WandererNotifier.Test.Support.JsonEncoders do
  @moduledoc """
  Defines JSON encoding protocols for structs used in tests.
  """

  # Configure Jason.Encoder for the Killmail struct
  defimpl Jason.Encoder, for: WandererNotifier.Killmail.Killmail do
    def encode(struct, opts) do
      # Convert struct to a map, excluding keys that are nil
      map =
        struct
        |> Map.from_struct()
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Enum.into(%{})

      Jason.Encode.map(map, opts)
    end
  end
end
