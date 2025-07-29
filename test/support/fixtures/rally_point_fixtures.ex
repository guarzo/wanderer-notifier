defmodule WandererNotifier.RallyPointFixtures do
  @moduledoc """
  Test fixtures for rally point events and notifications.
  """

  def rally_point_added_payload do
    %{
      "rally_point_id" => "550e8400-e29b-41d4-a716-446655440000",
      "solar_system_id" => 30_000_142,
      "system_id" => "660e8400-e29b-41d4-a716-446655440000",
      "character_id" => "770e8400-e29b-41d4-a716-446655440000",
      "character_name" => "Test Pilot",
      "character_eve_id" => 95_123_456,
      "system_name" => "Jita",
      "message" => "Form up for fleet ops!",
      "created_at" => "2024-01-01T12:00:00Z"
    }
  end

  def rally_point_added_payload_minimal do
    %{
      "rally_point_id" => "550e8400-e29b-41d4-a716-446655440000",
      "solar_system_id" => 30_000_142,
      "system_id" => "660e8400-e29b-41d4-a716-446655440000",
      "character_id" => "770e8400-e29b-41d4-a716-446655440000",
      "character_name" => "Test Pilot",
      "character_eve_id" => 95_123_456,
      "system_name" => "Jita",
      "message" => nil,
      "created_at" => "2024-01-01T12:00:00Z"
    }
  end

  def rally_point_event(payload \\ nil) do
    %{
      "id" => "01H5X8G5VQFQK1234567890ABC",
      "type" => "rally_point_added",
      "map_id" => "880e8400-e29b-41d4-a716-446655440000",
      "timestamp" => "2024-01-01T12:00:00.000Z",
      "payload" => payload || rally_point_added_payload()
    }
  end

  def rally_point_data(overrides \\ %{}) do
    defaults = %{
      id: "550e8400-e29b-41d4-a716-446655440000",
      system_id: 30_000_142,
      system_name: "Jita",
      character_name: "Test Pilot",
      character_eve_id: 95_123_456,
      message: "Form up for fleet ops!",
      created_at: "2024-01-01T12:00:00Z"
    }

    Map.merge(defaults, overrides)
  end

  def expected_notification_format do
    %{
      type: :rally_point,
      title: "Rally Point Created",
      description: "Test Pilot has created a rally point in **Jita**",
      color: 0x00FF00,
      fields: [
        %{
          name: "System",
          value: "Jita",
          inline: true
        },
        %{
          name: "Created By",
          value: "Test Pilot",
          inline: true
        },
        %{
          name: "Message",
          value: "Form up for fleet ops!",
          inline: false
        }
      ],
      footer: %{
        text: "Rally Point Notification",
        icon_url: nil
      }
    }
  end

  def expected_notification_format_no_message do
    %{
      type: :rally_point,
      title: "Rally Point Created",
      description: "Test Pilot has created a rally point in **Jita**",
      color: 0x00FF00,
      fields: [
        %{
          name: "System",
          value: "Jita",
          inline: true
        },
        %{
          name: "Created By",
          value: "Test Pilot",
          inline: true
        },
        %{
          name: "Message",
          value: "No message provided",
          inline: false
        }
      ],
      footer: %{
        text: "Rally Point Notification",
        icon_url: nil
      }
    }
  end
end
