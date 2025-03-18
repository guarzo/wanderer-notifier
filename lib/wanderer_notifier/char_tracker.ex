defmodule WandererNotifier.CharTracker do
  @moduledoc """
  Proxy module for WandererNotifier.Services.CharTracker.
  This module delegates calls to the underlying service implementation.
  """

  @doc """
  Updates the tracked characters list and notifies about new characters.
  Delegates to WandererNotifier.Services.CharTracker.update_tracked_characters/1.
  """
  def update_tracked_characters(cached_characters \\ nil) do
    WandererNotifier.Services.CharTracker.update_tracked_characters(cached_characters)
  end

  @doc """
  Checks if the characters endpoint is available by making a test request.
  Delegates to WandererNotifier.Services.CharTracker.check_characters_endpoint_availability/0.
  """
  def check_characters_endpoint_availability do
    WandererNotifier.Services.CharTracker.check_characters_endpoint_availability()
  end
end
