defmodule WandererNotifier.Notifiers.Discord.Constants do
  @moduledoc """
  Constants for Discord API integration.
  Centralizes API versions, endpoints, and other constants.
  """

  # Current Discord API version
  @api_version "v10"

  # Base URL for Discord API
  @base_api_url "https://discord.com/api/#{@api_version}"

  # Endpoint paths
  @channels_path "/channels"
  @messages_path "/messages"

  # Rate limit constants
  @rate_limit_retry_after 5000
  @max_retry_attempts 3

  # Component types
  @button_component 2
  @select_menu_component 3
  @text_input_component 4

  # Button styles
  @button_style_primary 1
  @button_style_secondary 2
  @button_style_success 3
  @button_style_danger 4
  @button_style_link 5

  # Public exports
  def api_version, do: @api_version
  def base_url, do: @base_api_url
  def channels_url, do: "#{@base_api_url}#{@channels_path}"
  def messages_url(channel_id), do: "#{channels_url()}/#{channel_id}#{@messages_path}"
  def rate_limit_retry_after, do: @rate_limit_retry_after
  def max_retry_attempts, do: @max_retry_attempts

  # Component type helpers
  def component_type(:button), do: @button_component
  def component_type(:select_menu), do: @select_menu_component
  def component_type(:text_input), do: @text_input_component

  # Button style helpers
  def button_style(:primary), do: @button_style_primary
  def button_style(:secondary), do: @button_style_secondary
  def button_style(:success), do: @button_style_success
  def button_style(:danger), do: @button_style_danger
  def button_style(:link), do: @button_style_link
end
