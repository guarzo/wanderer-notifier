defmodule WandererNotifier.Notifiers.Discord.FeatureFlags do
  @moduledoc """
  Feature flags for Discord notification functionality.
  """

  alias WandererNotifier.Config.Config

  @doc """
  Checks if interactive components are enabled.
  """
  def components_enabled? do
    Config.get_feature_flag(:discord_components, false)
  end

  @doc """
  Checks if rich embeds are enabled.
  """
  def rich_embeds_enabled? do
    Config.get_feature_flag(:discord_rich_embeds, true)
  end

  @doc """
  Checks if file attachments are enabled.
  """
  def file_attachments_enabled? do
    Config.get_feature_flag(:discord_file_attachments, true)
  end

  @doc """
  Checks if message components are enabled.
  """
  def message_components_enabled? do
    Config.get_feature_flag(:discord_message_components, true)
  end

  @doc """
  Checks if thread creation is enabled.
  """
  def thread_creation_enabled? do
    Config.get_feature_flag(:discord_thread_creation, false)
  end

  @doc """
  Checks if reactions are enabled.
  """
  def reactions_enabled? do
    Config.get_feature_flag(:discord_reactions, true)
  end

  @doc """
  Checks if message editing is enabled.
  """
  def message_editing_enabled? do
    Config.get_feature_flag(:discord_message_editing, true)
  end

  @doc """
  Checks if message deletion is enabled.
  """
  def message_deletion_enabled? do
    Config.get_feature_flag(:discord_message_deletion, true)
  end
end
