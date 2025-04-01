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

  @impl true
  def get_single_killmail(_kill_id), do: {:ok, %{}}

  @impl true
  def get_recent_kills(_limit \\ 10), do: {:ok, []}

  @impl true
  def get_system_kills(_system_id, _limit \\ 5), do: {:ok, []}

  @impl true
  def get_character_kills(_character_id, _limit \\ 25, _page \\ 1), do: {:ok, []}
end
