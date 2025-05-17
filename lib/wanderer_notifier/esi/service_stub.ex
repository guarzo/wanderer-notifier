defmodule WandererNotifier.ESI.ServiceStub do
  @moduledoc """
  Stub implementation of the ESI Service to avoid compilation warnings.
  This module is only used at compile time and is replaced by mocks during tests.
  """

  @doc """
  Gets killmail data by ID and hash.
  """
  def get_killmail(_killmail_id, _hash), do: {:error, :not_implemented}

  @doc """
  Gets character information.
  """
  def get_character_info(_id, _opts \\ []), do: {:error, :not_implemented}

  @doc """
  Gets corporation information.
  """
  def get_corporation_info(_id, _opts \\ []), do: {:error, :not_implemented}

  @doc """
  Gets alliance information.
  """
  def get_alliance_info(_id, _opts \\ []), do: {:error, :not_implemented}

  @doc """
  Gets system information.
  """
  def get_system(_id, _opts \\ []), do: {:error, :not_implemented}

  @doc """
  Gets type information.
  """
  def get_type_info(_id, _opts \\ []), do: {:error, :not_implemented}

  @doc """
  Gets system kills.
  """
  def get_system_kills(_system_id, _limit, _opts \\ []), do: {:error, :not_implemented}
end
