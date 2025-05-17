defmodule WandererNotifier.Test.DeduplicationBehaviour do
  @moduledoc """
  Test behaviour definition for deduplication services.
  """
  @callback check(:kill, String.t()) :: {:ok, :duplicate | :new} | {:error, term()}
  @callback clear_key(:kill, String.t()) :: {:ok, :cleared} | {:error, term()}
end

defmodule WandererNotifier.Test.ConfigBehaviour do
  @moduledoc """
  Test behaviour definition for configuration services.
  """
  @callback get_notification_setting(:kill, :enabled) :: boolean()
  @callback get_config() :: map()
end

defmodule WandererNotifier.Test.CharacterBehaviour do
  @moduledoc """
  Test behaviour definition for character tracking services.
  """
  @callback is_tracked?(String.t() | integer()) :: boolean()
end

defmodule WandererNotifier.Test.SystemBehaviour do
  @moduledoc """
  Test behaviour definition for system tracking services.
  """
  @callback is_tracked?(String.t() | integer()) :: boolean()
end
