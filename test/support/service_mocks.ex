defmodule WandererNotifier.Api.ESI.ServiceMock do
  @moduledoc """
  Mock implementation of the ESI service for testing.
  """

  @behaviour WandererNotifier.Api.ESI.ServiceBehaviour

  @impl true
  def get_killmail(_kill_id, _hash), do: {:ok, %{}}

  @impl true
  def get_character_info(_character_id), do: {:ok, %{"name" => "Test Character"}}

  @impl true
  def get_corporation_info(_corporation_id), do: {:ok, %{}}

  @impl true
  def get_alliance_info(_alliance_id), do: {:ok, %{}}

  @impl true
  def get_system_info(_system_id), do: {:ok, %{}}

  @impl true
  def get_type_info(_type_id), do: {:ok, %{"name" => "Test Ship"}}

  @impl true
  def get_system(_system_id), do: {:ok, %{}}

  @impl true
  def get_character(_character_id), do: {:ok, %{}}

  @impl true
  def get_type(_type_id), do: {:ok, %{}}

  @impl true
  def get_ship_type_name(_ship_type_id), do: {:ok, %{"name" => "Test Ship"}}

  @impl true
  def get_system_kills(_system_id, _limit), do: {:ok, []}
end

defmodule WandererNotifier.Api.ZKill.ServiceMock do
  @moduledoc """
  Mock implementation of the ZKill service for testing.
  """

  @behaviour WandererNotifier.Api.ZKill.ServiceBehaviour
  @behaviour WandererNotifier.Api.ZKill.Behaviour

  @impl true
  def get_single_killmail(_kill_id), do: {:ok, %{}}

  @impl true
  def get_recent_kills(_limit \\ 10), do: {:ok, []}

  @impl true
  def get_system_kills(_system_id, _limit \\ 5) do
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

  @impl true
  def get_character_kills(_character_id, _limit \\ 25, _page \\ 1), do: {:ok, []}

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
end
