defmodule WandererNotifier.Domains.Notifications.Formatters.Base do
  @moduledoc """
  Base notification formatter providing common formatting utilities.

  This module extracts common formatting patterns from killmail, character, and system formatters,
  providing a unified interface for notification creation and formatting.

  ## Features
  - Standard notification structure building
  - URL and link generation utilities
  - Field creation helpers
  - Color and icon management
  - Value formatting (ISK, numbers, etc.)
  - Error handling patterns

  ## Usage
  ```elixir
  use WandererNotifier.Domains.Notifications.Formatters.Base

  # Create notification
  notification = build_notification(%{
    type: :custom_notification,
    title: "Custom Title",
    description: "Description",
    color: :info,
    fields: [
      build_field("Name", "Value", true)
    ]
  })
  ```
  """

  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Shared.Utils.TimeUtils

  # Color constants
  @colors %{
    default: 0x3498DB,
    info: 0x3498DB,
    success: 0x5CB85C,
    warning: 0xE28A0D,
    error: 0xD9534F,
    wormhole: 0x428BCA,
    highsec: 0x5CB85C,
    lowsec: 0xE28A0D,
    nullsec: 0xD9534F,
    kill: 0xD9534F
  }

  # Icon constants
  @icons %{
    wormhole: "https://images.evetech.net/types/45041/icon",
    highsec: "https://images.evetech.net/types/3802/icon",
    lowsec: "https://images.evetech.net/types/3796/icon",
    nullsec: "https://images.evetech.net/types/3799/icon",
    default: "https://images.evetech.net/types/3802/icon"
  }

  @doc """
  Builds a standard notification structure.

  ## Parameters
  - `attrs` - Map containing notification attributes

  ## Required Attributes
  - `:type` - Notification type (atom)
  - `:title` - Notification title (string)
  - `:description` - Notification description (string)

  ## Optional Attributes
  - `:color` - Color (atom, hex string, or integer)
  - `:fields` - List of field maps
  - `:thumbnail` - Thumbnail map with `:url`
  - `:author` - Author map with `:name` and `:icon_url`
  - `:footer` - Footer map with `:text`
  - `:timestamp` - ISO timestamp string
  - `:url` - URL for the notification title
  - `:image` - Image map with `:url`

  ## Examples
  ```elixir
  build_notification(%{
    type: :system_notification,
    title: "New System Tracked",
    description: "System has been added",
    color: :info,
    fields: [build_field("System", "Jita", true)]
  })
  ```
  """
  def build_notification(attrs) do
    %{
      type: Map.fetch!(attrs, :type),
      title: Map.fetch!(attrs, :title),
      description: Map.fetch!(attrs, :description),
      color: resolve_color(Map.get(attrs, :color, :default)),
      timestamp: Map.get(attrs, :timestamp, TimeUtils.log_timestamp()),
      fields: Map.get(attrs, :fields, []),
      thumbnail: Map.get(attrs, :thumbnail),
      author: Map.get(attrs, :author),
      footer: Map.get(attrs, :footer),
      url: Map.get(attrs, :url),
      image: Map.get(attrs, :image)
    }
    |> remove_nil_values()
  end

  @doc """
  Builds a notification field.

  ## Parameters
  - `name` - Field name (string)
  - `value` - Field value (any, will be converted to string)
  - `inline` - Whether field should be inline (boolean, default: false)

  ## Examples
  ```elixir
  build_field("Character", "John Doe", true)
  build_field("System", "Jita")
  ```
  """
  def build_field(name, value, inline \\ false) do
    %{
      name: safe_to_string(name),
      value: safe_to_string(value),
      inline: inline
    }
  end

  @doc """
  Builds multiple fields from a list of tuples.

  ## Parameters
  - `field_data` - List of `{name, value}` or `{name, value, inline}` tuples

  ## Examples
  ```elixir
  build_fields([
    {"Character", "John Doe", true},
    {"Corporation", "Test Corp", true},
    {"Description", "Long description"}
  ])
  ```
  """
  def build_fields(field_data) when is_list(field_data) do
    Enum.map(field_data, fn
      {name, value} -> build_field(name, value)
      {name, value, inline} -> build_field(name, value, inline)
    end)
  end

  @doc """
  Builds a thumbnail map for notifications.

  ## Parameters
  - `url` - Thumbnail URL (string or nil)

  ## Examples
  ```elixir
  build_thumbnail("https://images.evetech.net/characters/123/portrait")
  build_thumbnail(nil)  # Returns nil
  ```
  """
  def build_thumbnail(nil), do: nil
  def build_thumbnail(url) when is_binary(url), do: %{url: url}

  @doc """
  Builds an author map for notifications.

  ## Parameters
  - `name` - Author name (string)
  - `icon_url` - Author icon URL (string or nil)

  ## Examples
  ```elixir
  build_author("John Doe", "https://images.evetech.net/characters/123/portrait")
  build_author("System Alert", nil)
  ```
  """
  def build_author(name, icon_url \\ nil) do
    %{name: safe_to_string(name), icon_url: icon_url}
    |> remove_nil_values()
  end

  @doc """
  Builds a footer map for notifications.

  ## Parameters
  - `text` - Footer text (string)

  ## Examples
  ```elixir
  build_footer("Value: 100M ISK")
  ```
  """
  def build_footer(text) do
    %{text: safe_to_string(text)}
  end

  @doc """
  Generates EVE character portrait URL.

  ## Parameters
  - `character_id` - Character ID (integer)
  - `size` - Image size (32, 64, 128, 256, 512, default: 64)

  ## Examples
  ```elixir
  character_portrait_url(123456789)
  character_portrait_url(123456789, 128)
  ```
  """
  def character_portrait_url(character_id, size \\ 64) when is_integer(character_id) do
    "https://images.evetech.net/characters/#{character_id}/portrait?size=#{size}"
  end

  @doc """
  Generates EVE corporation logo URL.

  ## Parameters
  - `corporation_id` - Corporation ID (integer)
  - `size` - Image size (32, 64, 128, 256, default: 64)
  """
  def corporation_logo_url(corporation_id, size \\ 64) when is_integer(corporation_id) do
    "https://images.evetech.net/corporations/#{corporation_id}/logo?size=#{size}"
  end

  @doc """
  Generates EVE alliance logo URL.

  ## Parameters
  - `alliance_id` - Alliance ID (integer)
  - `size` - Image size (32, 64, 128, 256, default: 64)
  """
  def alliance_logo_url(alliance_id, size \\ 64) when is_integer(alliance_id) do
    "https://images.evetech.net/alliances/#{alliance_id}/logo?size=#{size}"
  end

  @doc """
  Generates EVE ship/type render URL.

  ## Parameters
  - `type_id` - Type ID (integer)
  - `size` - Image size (32, 64, 128, 256, 512, default: 64)
  """
  def type_render_url(type_id, size \\ 64) when is_integer(type_id) do
    "https://images.evetech.net/types/#{type_id}/render?size=#{size}"
  end

  @doc """
  Generates EVE type icon URL.

  ## Parameters
  - `type_id` - Type ID (integer)
  - `size` - Image size (32, 64, default: 64)
  """
  def type_icon_url(type_id, size \\ 64) when is_integer(type_id) do
    "https://images.evetech.net/types/#{type_id}/icon?size=#{size}"
  end

  @doc """
  Generates zKillboard character URL.

  ## Parameters
  - `character_id` - Character ID (integer)
  """
  def zkillboard_character_url(character_id) when is_integer(character_id) do
    "https://zkillboard.com/character/#{character_id}/"
  end

  @doc """
  Generates zKillboard corporation URL.

  ## Parameters
  - `corporation_id` - Corporation ID (integer)
  """
  def zkillboard_corporation_url(corporation_id) when is_integer(corporation_id) do
    "https://zkillboard.com/corporation/#{corporation_id}/"
  end

  @doc """
  Generates zKillboard alliance URL.

  ## Parameters
  - `alliance_id` - Alliance ID (integer)
  """
  def zkillboard_alliance_url(alliance_id) when is_integer(alliance_id) do
    "https://zkillboard.com/alliance/#{alliance_id}/"
  end

  @doc """
  Generates zKillboard system URL.

  ## Parameters
  - `system_id` - System ID (integer)
  """
  def zkillboard_system_url(system_id) when is_integer(system_id) do
    "https://zkillboard.com/system/#{system_id}/"
  end

  @doc """
  Generates zKillboard killmail URL.

  ## Parameters
  - `killmail_id` - Killmail ID (integer)
  """
  def zkillboard_killmail_url(killmail_id) when is_integer(killmail_id) do
    "https://zkillboard.com/kill/#{killmail_id}/"
  end

  @doc """
  Generates Dotlan region URL.

  ## Parameters
  - `region_name` - Region name (string)
  """
  def dotlan_region_url(region_name) when is_binary(region_name) do
    region_url_name = String.replace(region_name, " ", "_")
    "https://evemaps.dotlan.net/map/#{region_url_name}"
  end

  @doc """
  Creates a markdown link.

  ## Parameters
  - `text` - Link text (string)
  - `url` - Link URL (string)

  ## Examples
  ```elixir
  create_link("John Doe", "https://zkillboard.com/character/123/")
  # Returns: "[John Doe](https://zkillboard.com/character/123/)"
  ```
  """
  def create_link(text, url) when is_binary(text) and is_binary(url) do
    "[#{text}](#{url})"
  end

  @doc """
  Creates a character link with zKillboard URL.

  ## Parameters
  - `character_name` - Character name (string)
  - `character_id` - Character ID (integer or nil)

  ## Examples
  ```elixir
  create_character_link("John Doe", 123456789)
  create_character_link("John Doe", nil)  # Returns: "John Doe"
  ```
  """
  def create_character_link(character_name, character_id) when is_integer(character_id) do
    create_link(character_name, zkillboard_character_url(character_id))
  end

  def create_character_link(character_name, _character_id) do
    safe_to_string(character_name)
  end

  @doc """
  Creates a corporation link with zKillboard URL.

  ## Parameters
  - `corporation_name` - Corporation name (string)
  - `corporation_id` - Corporation ID (integer or nil)
  """
  def create_corporation_link(corporation_name, corporation_id) when is_integer(corporation_id) do
    create_link(corporation_name, zkillboard_corporation_url(corporation_id))
  end

  def create_corporation_link(corporation_name, _corporation_id) do
    safe_to_string(corporation_name)
  end

  @doc """
  Creates an alliance link with zKillboard URL.

  ## Parameters
  - `alliance_name` - Alliance name (string)
  - `alliance_id` - Alliance ID (integer or nil)
  """
  def create_alliance_link(alliance_name, alliance_id) when is_integer(alliance_id) do
    create_link(alliance_name, zkillboard_alliance_url(alliance_id))
  end

  def create_alliance_link(alliance_name, _alliance_id) do
    safe_to_string(alliance_name)
  end

  @doc """
  Creates a system link with zKillboard URL.

  ## Parameters
  - `system_name` - System name (string)
  - `system_id` - System ID (integer or nil)
  """
  def create_system_link(system_name, system_id) when is_integer(system_id) do
    create_link(system_name, zkillboard_system_url(system_id))
  end

  def create_system_link(system_name, _system_id) do
    safe_to_string(system_name)
  end

  @doc """
  Formats ISK values with appropriate suffixes (K, M, B).

  ## Parameters
  - `value` - ISK value (number)

  ## Examples
  ```elixir
  format_isk_value(1500)          # "1.5K"
  format_isk_value(2500000)       # "2.5M"
  format_isk_value(1200000000)    # "1.2B"
  ```
  """
  def format_isk_value(value) when is_number(value) and value >= 1_000_000_000 do
    "#{Float.round(value / 1_000_000_000, 2)}B"
  end

  def format_isk_value(value) when is_number(value) and value >= 1_000_000 do
    "#{Float.round(value / 1_000_000, 2)}M"
  end

  def format_isk_value(value) when is_number(value) and value >= 1_000 do
    "#{Float.round(value / 1_000, 2)}K"
  end

  def format_isk_value(value) when is_number(value) do
    "#{round(value)}"
  end

  def format_isk_value(_value), do: "0"

  @doc """
  Determines color based on system security status.

  ## Parameters
  - `security_status` - Security status (float or string)

  ## Examples
  ```elixir
  determine_security_color(0.8)     # :highsec color
  determine_security_color(0.3)     # :lowsec color
  determine_security_color(0.0)     # :nullsec color
  determine_security_color(-1.0)    # :wormhole color
  ```
  """
  def determine_security_color(security_status) when is_float(security_status) do
    cond do
      security_status >= 0.5 -> :highsec
      security_status > 0.0 -> :lowsec
      security_status == 0.0 -> :nullsec
      security_status < 0.0 -> :wormhole
      true -> :default
    end
  end

  def determine_security_color("Highsec"), do: :highsec
  def determine_security_color("Lowsec"), do: :lowsec
  def determine_security_color("Nullsec"), do: :nullsec
  def determine_security_color("W-Space"), do: :wormhole
  def determine_security_color(_), do: :default

  @doc """
  Gets system icon based on security type.

  ## Parameters
  - `security_type` - Security type (atom or string)

  ## Examples
  ```elixir
  get_system_icon(:highsec)
  get_system_icon("Wormhole")
  ```
  """
  def get_system_icon(security_type) when is_atom(security_type) do
    Map.get(@icons, security_type, @icons.default)
  end

  def get_system_icon(security_type) when is_binary(security_type) do
    type_atom =
      case String.downcase(security_type) do
        "highsec" -> :highsec
        "lowsec" -> :lowsec
        "nullsec" -> :nullsec
        "w-space" -> :wormhole
        "wormhole" -> :wormhole
        _ -> :default
      end

    get_system_icon(type_atom)
  end

  def get_system_icon(_), do: @icons.default

  @doc """
  Safely converts any value to a string, handling nil values.

  ## Parameters
  - `value` - Value to convert (any)

  ## Examples
  ```elixir
  safe_to_string(nil)       # ""
  safe_to_string("test")    # "test"
  safe_to_string(123)       # "123"
  safe_to_string([1,2,3])   # "[1, 2, 3]"
  ```
  """
  def safe_to_string(nil), do: ""
  def safe_to_string(value) when is_binary(value), do: value
  def safe_to_string(value), do: inspect(value, limit: 100, printable_limit: 100)

  @doc """
  Resolves color atoms/strings to integer values.

  ## Parameters
  - `color` - Color (atom, string, or integer)

  ## Examples
  ```elixir
  resolve_color(:info)      # 0x3498DB
  resolve_color("error")    # 0xD9534F
  resolve_color(0xFF0000)   # 0xFF0000
  resolve_color("#FF0000")  # 0xFF0000
  ```
  """
  def resolve_color(color) when is_atom(color) do
    Map.get(@colors, color, @colors.default)
  end

  def resolve_color(color) when is_binary(color) do
    case color do
      "#" <> hex ->
        case Integer.parse(hex, 16) do
          {color_int, _} -> color_int
          :error -> @colors.default
        end

      color_name ->
        color_atom = String.to_existing_atom(color_name)
        Map.get(@colors, color_atom, @colors.default)
    end
  rescue
    ArgumentError -> @colors.default
  end

  def resolve_color(color) when is_integer(color), do: color
  def resolve_color(_), do: @colors.default

  @doc """
  Wraps formatter functions with error handling.

  ## Parameters
  - `module` - Module name for logging (atom)
  - `operation` - Operation description (string)
  - `data` - Data being processed (any)
  - `fun` - Function to execute

  ## Examples
  ```elixir
  with_error_handling(__MODULE__, "format character", character, fn ->
    # formatting logic here
  end)
  ```
  """
  def with_error_handling(module, operation, data, fun) when is_function(fun, 0) do
    fun.()
  rescue
    exception ->
      AppLogger.processor_error(
        "Error in #{module} during #{operation}",
        error: Exception.message(exception),
        data: inspect(data, limit: 500, printable_limit: 500),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__) |> String.slice(0, 1000)
      )

      reraise exception, __STACKTRACE__
  end

  # Private helper functions

  defp remove_nil_values(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end
end
