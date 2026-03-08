defmodule WandererNotifier.Map.MapRegistryBehaviour do
  @moduledoc """
  Behaviour for the MapRegistry, enabling Mox-based testing.

  Declares the subset of MapRegistry functions used by the killmail pipeline
  and other callers that resolve the registry via Dependencies.map_registry/0.
  """

  @callback mode() :: :api | :env_var
  @callback tracking_index_counts() :: {non_neg_integer(), non_neg_integer()}
  @callback maps_tracking_system(String.t() | integer()) :: [term()]
  @callback maps_tracking_character(String.t() | integer()) :: [term()]
  @callback all_maps() :: [term()]
end
