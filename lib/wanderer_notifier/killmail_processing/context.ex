defmodule WandererNotifier.KillmailProcessing.Context do
  @moduledoc """
  @deprecated Please use WandererNotifier.Killmail.Core.Context instead

  This module is deprecated and will be removed in a future release.
  All functionality has been moved to WandererNotifier.Killmail.Core.Context.

  This is a compatibility layer that transparently forwards all struct and function
  calls to the new module to ease migration.
  """

  # Get the struct keys from the Context module
  @fields Map.keys(%WandererNotifier.Killmail.Core.Context{})
          |> Enum.filter(fn k -> k != :__struct__ end)

  defstruct @fields

  # Delegate all type specs to the new module
  @type t :: WandererNotifier.Killmail.Core.Context.t()

  alias WandererNotifier.Killmail.Core.Context

  # Public API

  @doc """
  Creates a new Context struct for realtime processing.
  @deprecated Use WandererNotifier.Killmail.Core.Context.new_realtime/3 instead
  """
  defdelegate new_realtime(character_id, character_name, source), to: Context

  @doc """
  Creates a new Context struct for realtime processing with metadata.
  @deprecated Use WandererNotifier.Killmail.Core.Context.new_realtime/4 instead
  """
  defdelegate new_realtime(character_id, character_name, source, metadata), to: Context

  @doc """
  Creates a new Context struct for batch processing.
  @deprecated Use WandererNotifier.Killmail.Core.Context.new_batch/3 instead
  """
  defdelegate new_batch(batch_id, batch_name, source), to: Context

  @doc """
  Creates a new Context struct for batch processing with metadata.
  @deprecated Use WandererNotifier.Killmail.Core.Context.new_batch/4 instead
  """
  defdelegate new_batch(batch_id, batch_name, source, metadata), to: Context

  @doc """
  Sets a metadata field in the context.
  @deprecated Use WandererNotifier.Killmail.Core.Context.set_metadata/3 instead
  """
  defdelegate set_metadata(context, key, value), to: Context

  @doc """
  Gets a metadata field from the context.
  @deprecated Use WandererNotifier.Killmail.Core.Context.get_metadata/3 instead
  """
  defdelegate get_metadata(context, key, default \\ nil), to: Context

  @doc """
  Updates the metadata field in the context.
  @deprecated Use WandererNotifier.Killmail.Core.Context.update_metadata/2 instead
  """
  defdelegate update_metadata(context, metadata_map), to: Context

  @doc """
  Returns true if the context represents a batch processing job.
  @deprecated Use WandererNotifier.Killmail.Core.Context.is_batch?/1 instead
  """
  defdelegate is_batch?(context), to: Context

  @doc """
  Returns true if the context represents a realtime processing job.
  @deprecated Use WandererNotifier.Killmail.Core.Context.is_realtime?/1 instead
  """
  defdelegate is_realtime?(context), to: Context
end
