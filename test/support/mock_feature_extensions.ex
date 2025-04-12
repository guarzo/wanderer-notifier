defmodule WandererNotifier.MockFeatureExtensions do
  @moduledoc """
  Extensions to add required behavior functions to MockFeatures that aren't directly
  defined in the test_helper.exs file but are needed by various tests.
  """

  # Add the MockFeatures extensions
  def add_expectations do
    # Set up feature status mapping
    Mox.stub(WandererNotifier.Config.MockFeatures, :get_feature_status, fn ->
      %{
        activity_charts: true,
        kill_charts: true,
        map_charts: true,
        character_notifications_enabled: true,
        system_notifications_enabled: true,
        character_tracking_enabled: true,
        system_tracking_enabled: true,
        tracked_systems_notifications_enabled: true,
        tracked_characters_notifications_enabled: true,
        kill_notifications_enabled: true,
        notifications_enabled: true
      }
    end)

    # Enable all features by default for tests
    Mox.stub(WandererNotifier.Config.MockFeatures, :notifications_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.Config.MockFeatures, :kill_notifications_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.Config.MockFeatures, :system_notifications_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.Config.MockFeatures, :character_notifications_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.Config.MockFeatures, :tracked_systems_notifications_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.Config.MockFeatures, :tracked_characters_notifications_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.Config.MockFeatures, :system_tracking_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.Config.MockFeatures, :character_tracking_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.Config.MockFeatures, :kill_charts_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.Config.MockFeatures, :activity_charts_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.Config.MockFeatures, :map_charts_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.Config.MockFeatures, :status_messages_disabled?, fn -> false end)
    Mox.stub(WandererNotifier.Config.MockFeatures, :cache_enabled?, fn -> true end)

    # Define get_feature to return map when :features key is given
    Mox.stub(WandererNotifier.Config.MockFeatures, :get_feature, fn
      :status_messages_disabled, _default -> false
      key, default -> default
    end)

    # Define get_env to return map when :features key is given
    Mox.stub(WandererNotifier.Config.MockFeatures, :get_env, fn
      :features, _default -> %{
        status_messages_disabled: false,
        notifications_enabled: true,
        system_notifications_enabled: true,
        character_notifications_enabled: true,
        kill_notifications_enabled: true
      }
      _key, default -> default
    end)
  end
end
