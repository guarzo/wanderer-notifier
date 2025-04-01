defmodule WandererNotifier.Api.ZKill.ServiceMock do
  @moduledoc """
  Mock implementation of the ZKill service for testing.
  """

  @behaviour WandererNotifier.Api.ZKill.Behaviour

  @impl true
  def get_killmail(_kill_id, _hash) do
    {:ok,
     %{
       "killmail_id" => 12_345,
       "solar_system_id" => 30_000_142,
       "victim" => %{
         "character_id" => 93_265_357,
         "ship_type_id" => 587
       },
       "attackers" => [
         %{
           "character_id" => 93_898_784,
           "ship_type_id" => 11_567
         }
       ]
     }}
  end

  @impl true
  def get_system_kills(_system_id, _limit) do
    {:ok,
     [
       %{
         "killmail_id" => 12_345,
         "zkb" => %{
           "totalValue" => 1_000_000.0,
           "points" => 1,
           "hash" => "abc123"
         }
       }
     ]}
  end
end
