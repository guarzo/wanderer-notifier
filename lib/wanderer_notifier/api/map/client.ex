defmodule WandererNotifier.Api.Map.Client do
  @moduledoc """
  Client for interacting with the Map API

  This module is a compatibility layer that delegates to the primary
  WandererNotifier.Map.Client implementation.

  @deprecated Use WandererNotifier.Map.Client directly
  """

  require Logger

  @doc """
  Updates tracked characters
  """
  def update_tracked_characters do
    characters = WandererNotifier.Character.get_all_characters()
    # Call to the underlying implementation
    WandererNotifier.Map.Client.update_tracked_characters(characters)
  end

  @doc """
  Updates tracked characters with provided character list
  """
  def update_tracked_characters(characters) do
    # Call to the underlying implementation
    WandererNotifier.Map.Client.update_tracked_characters(characters)
  end
end
