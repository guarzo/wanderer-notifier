defmodule WandererNotifier.Processing.Killmail.KillmailProcessor do
  @moduledoc """
  @deprecated Please use WandererNotifier.Killmail.Processing.Processor instead

  This module is deprecated and will be removed in a future release.
  All functionality has been moved to WandererNotifier.Killmail.Processing.Processor.
  """

  alias WandererNotifier.Killmail.Processing.Processor

  @doc """
  Process a killmail through the complete pipeline.
  @deprecated Please use WandererNotifier.Killmail.Processing.Processor.process_killmail/2 instead
  """
  def process_killmail(killmail, context) do
    Processor.process_killmail(killmail, context)
  end

  @doc """
  Configure the KillmailProcessor module during application startup.
  @deprecated Please use WandererNotifier.Killmail.Processing.Processor.configure/0 instead
  """
  def configure do
    Processor.configure()
  end
end
