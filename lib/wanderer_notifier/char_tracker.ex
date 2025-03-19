defmodule WandererNotifier.CharTracker do
  @moduledoc """
  Proxy module for WandererNotifier.Api.Map.Characters.
  This module delegates calls to the underlying service implementation.
  """

  @doc """
  Updates the tracked characters list and notifies about new characters.
  Delegates to WandererNotifier.Api.Map.Characters.update_tracked_characters/1.
  """
  def update_tracked_characters(cached_characters \\ nil) do
    WandererNotifier.Api.Map.Characters.update_tracked_characters(cached_characters)
  end

  @doc """
  Checks if the characters endpoint is available by making a test request.
  Delegates to WandererNotifier.Api.Map.Characters.check_characters_endpoint_availability/0.
  """
  def check_characters_endpoint_availability do
    WandererNotifier.Api.Map.Characters.check_characters_endpoint_availability()
  end
end
