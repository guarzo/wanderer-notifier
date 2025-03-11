defmodule WandererNotifier.Killmail do
  @moduledoc """
  Represents an enriched killmail with both zKill and ESI data.
  """
  @enforce_keys [:killmail_id, :zkb]
  defstruct [:killmail_id, :zkb, :esi_data]

  @type t :: %__MODULE__{
          killmail_id: any(),
          zkb: map(),
          esi_data: map() | nil
        }
end 