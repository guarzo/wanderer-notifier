defmodule ChainKills.ESI.Service do
  @moduledoc """
  High-level ESI service for ChainKills.
  """
  require Logger
  alias ChainKills.ESI.Client

  def get_esi_kill_mail(kill_id, killmail_hash, _opts \\ []) do
    Client.get_killmail(kill_id, killmail_hash)
  end

  def get_character_info(eve_id, _opts \\ []) do
    Client.get_character_info(eve_id)
  end

  def get_corporation_info(eve_id, _opts \\ []) do
    Client.get_corporation_info(eve_id)
  end

  def get_alliance_info(eve_id, _opts \\ []) do
    Client.get_alliance_info(eve_id)
  end
end
