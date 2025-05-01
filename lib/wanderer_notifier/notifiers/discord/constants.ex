defmodule WandererNotifier.Notifiers.Discord.Constants do
  @moduledoc """
  Constants used in Discord notifications.
  """

  # Discord color codes
  def colors do
    %{
      default: 0x3498DB,
      success: 0x2ECC71,
      warning: 0xF1C40F,
      error: 0xE74C3C,
      info: 0x3498DB,
      highsec: 0x2ECC71,
      lowsec: 0xF1C40F,
      nullsec: 0xE74C3C,
      wormhole: 0x9B59B6
    }
  end

  # Discord embed limits
  def embed_limits do
    %{
      title: 256,
      description: 4096,
      fields: 25,
      field_name: 256,
      field_value: 1024,
      footer_text: 2048,
      author_name: 256,
      total: 6000
    }
  end

  # Discord message limits
  def message_limits do
    %{
      content: 2000,
      embeds: 10,
      files: 10,
      # 8MB
      file_size: 8_388_608
    }
  end

  # Discord component limits
  def component_limits do
    %{
      action_rows: 5,
      buttons_per_row: 5,
      select_menu_options: 25,
      custom_id: 100
    }
  end

  # Discord rate limits
  def rate_limits do
    %{
      messages_per_second: 5,
      messages_per_minute: 120,
      webhook_per_second: 30
    }
  end
end
