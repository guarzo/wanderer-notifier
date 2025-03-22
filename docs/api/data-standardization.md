# API Data Standardization

This document outlines the approach to standardizing API data in the WandererNotifier application.

## Overview

The WandererNotifier application interacts with several external APIs, each with its own data formats and structures. To maintain consistency and enable robust data processing, the application uses structured data types to represent API data.

## Design Principles

The standardization approach follows these key principles:

1. **Struct-Based Representation**: Use Elixir structs to represent API data
2. **Validation at Boundaries**: Validate API responses when they enter the system
3. **Consistent Access Patterns**: Provide consistent ways to access data across different APIs
4. **Error Handling**: Standardize error handling with clear return values
5. **Documentation**: Document the structure and usage of each data type

## Structured Data Types

### Character

The `WandererNotifier.Data.Character` struct represents character data from various APIs:

```elixir
defmodule WandererNotifier.Data.Character do
  @moduledoc """
  Represents an EVE Online character with relevant tracking information.
  """

  @type t :: %__MODULE__{
          eve_id: String.t(),
          name: String.t(),
          corporation_id: integer() | nil,
          corporation_ticker: String.t() | nil,
          alliance_id: integer() | nil,
          alliance_ticker: String.t() | nil,
          tracked: boolean()
        }

  defstruct [
    :eve_id,
    :name,
    :corporation_id,
    :corporation_ticker,
    :alliance_id,
    :alliance_ticker,
    tracked: false
  ]

  @doc """
  Creates a new Character struct from API response data.
  """
  def new(character_data) do
    %__MODULE__{
      eve_id: Map.get(character_data, "eve_id"),
      name: Map.get(character_data, "name"),
      corporation_id: Map.get(character_data, "corporation_id"),
      corporation_ticker: Map.get(character_data, "corporation_ticker"),
      alliance_id: Map.get(character_data, "alliance_id"),
      alliance_ticker: Map.get(character_data, "alliance_ticker"),
      tracked: true
    }
  end
end
```

### MapSystem

The `WandererNotifier.Data.MapSystem` struct represents solar system data:

```elixir
defmodule WandererNotifier.Data.MapSystem do
  @moduledoc """
  Represents a solar system with tracking information.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          solar_system_id: integer(),
          name: String.t(),
          original_name: String.t(),
          temporary_name: String.t() | nil,
          class_title: String.t() | nil,
          effect_name: String.t() | nil,
          region_name: String.t() | nil,
          statics: [String.t()] | nil,
          static_details: [map()] | nil,
          system_type: atom()
        }

  defstruct [
    :id,
    :solar_system_id,
    :name,
    :original_name,
    :temporary_name,
    :class_title,
    :effect_name,
    :region_name,
    :statics,
    :static_details,
    system_type: :unknown
  ]

  @doc """
  Creates a new MapSystem struct from API response data.
  """
  def new(system_data) do
    # System type is determined based on ID range and properties
    system_type = determine_system_type(system_data)

    # Original name falls back to name if not provided
    original_name = Map.get(system_data, "original_name", Map.get(system_data, "name"))

    # Only set temporary_name if it's different from original_name
    temporary_name =
      case Map.get(system_data, "temporary_name") do
        ^original_name -> nil
        nil -> nil
        temp_name -> temp_name
      end

    %__MODULE__{
      id: Map.get(system_data, "id"),
      solar_system_id: Map.get(system_data, "solar_system_id"),
      name: Map.get(system_data, "name"),
      original_name: original_name,
      temporary_name: temporary_name,
      class_title: Map.get(system_data, "class_title"),
      effect_name: Map.get(system_data, "effect_name"),
      region_name: Map.get(system_data, "region_name"),
      statics: Map.get(system_data, "statics"),
      system_type: system_type
    }
  end

  @doc """
  Determines if the system is a wormhole based on its properties.
  """
  def wormhole?(%__MODULE__{} = system) do
    system.system_type == :wormhole
  end

  @doc """
  Formats the display name of the system.
  """
  def format_display_name(%__MODULE__{} = system) do
    cond do
      system.temporary_name && system.original_name ->
        "#{system.temporary_name} (#{system.original_name})"

      system.original_name ->
        system.original_name

      true ->
        system.name
    end
  end
end
```

### Killmail

The `WandererNotifier.Data.Killmail` struct represents killmail data:

```elixir
defmodule WandererNotifier.Data.Killmail do
  @moduledoc """
  Represents a killmail from ESI or zKillboard.
  """

  @type t :: %__MODULE__{
          killmail_id: integer(),
          zkb: map() | nil,
          esi_data: map() | nil
        }

  defstruct [
    :killmail_id,
    :zkb,
    :esi_data
  ]

  @doc """
  Creates a new Killmail struct with the given ID and optional zkb and ESI data.
  """
  def new(killmail_id, zkb \\ nil, esi_data \\ nil) do
    %__MODULE__{
      killmail_id: killmail_id,
      zkb: zkb,
      esi_data: esi_data
    }
  end

  @doc """
  Gets the solar system ID from the killmail.
  """
  def solar_system_id(%__MODULE__{} = killmail) do
    cond do
      killmail.esi_data && Map.has_key?(killmail.esi_data, "solar_system_id") ->
        Map.get(killmail.esi_data, "solar_system_id")

      true ->
        nil
    end
  end
end
```

## API Client Implementation

API clients are implemented to use these structured data types:

```elixir
defmodule WandererNotifier.Api.Map.CharactersClient do
  @moduledoc """
  Client for interacting with the Map API characters endpoints.
  """

  alias WandererNotifier.Api.Map.Client
  alias WandererNotifier.Data.Character
  alias WandererNotifier.Cache.Repository, as: Cache

  @cache_ttl_seconds 86400  # 24 hours

  @doc """
  Updates tracked characters from the Map API.
  """
  def update_tracked_characters do
    with {:ok, response} <- Client.get("/api/map/characters"),
         {:ok, characters} <- extract_characters(response) do
      characters =
        characters
        |> Enum.map(&Character.new(Map.get(&1, "character")))
        |> Enum.filter(& &1.tracked)

      # Cache the characters
      Cache.put("map:tracked_characters", characters, ttl: @cache_ttl_seconds)

      {:ok, characters}
    else
      error -> error
    end
  end

  # Extracts character data from the API response
  defp extract_characters(%{"data" => %{"characters" => characters}}) when is_list(characters) do
    {:ok, characters}
  end
  defp extract_characters(_) do
    {:error, :invalid_response}
  end
end
```

## Validation and Error Handling

API responses are validated at the boundary through validation modules:

```elixir
defmodule WandererNotifier.Api.Map.ResponseValidator do
  @moduledoc """
  Validates responses from the Map API.
  """

  @doc """
  Validates a Map API response.
  """
  def validate_response({:ok, %{status: 200, body: body}}) do
    case Jason.decode(body) do
      {:ok, decoded} -> validate_decoded_response(decoded)
      {:error, _} -> {:error, :invalid_json}
    end
  end
  def validate_response({:ok, %{status: status}}) when status in 400..499 do
    {:error, :client_error}
  end
  def validate_response({:ok, %{status: status}}) when status in 500..599 do
    {:error, :server_error}
  end
  def validate_response({:error, reason}) do
    {:error, reason}
  end

  # Validates the structure of the decoded response
  defp validate_decoded_response(%{"success" => true, "data" => data}) when is_map(data) do
    {:ok, data}
  end
  defp validate_decoded_response(%{"success" => false, "error" => error}) do
    {:error, error}
  end
  defp validate_decoded_response(_) do
    {:error, :invalid_structure}
  end
end
```

## URL Building

URLs are built consistently using builder modules:

```elixir
defmodule WandererNotifier.Api.Map.UrlBuilder do
  @moduledoc """
  Builds URLs for the Map API.
  """

  alias WandererNotifier.Core.Config

  @doc """
  Builds a URL for the Map API.
  """
  def build_url(path) do
    Config.map_url_with_name() <> path
  end

  @doc """
  Builds a URL for the Map API with query parameters.
  """
  def build_url(path, params) when is_map(params) do
    query = URI.encode_query(params)
    build_url(path) <> "?" <> query
  end
end
```

## Benefits of Standardization

The standardization approach provides several benefits:

1. **Type Safety**: Using structs with typespecs enables type checking
2. **Documentation**: Struct fields and functions are documented for clarity
3. **Validation**: API responses are validated before processing
4. **Consistency**: Data is accessed in a consistent way across the application
5. **Maintenance**: Changes to API formats can be handled in a single place
6. **Testing**: Mock API responses can be easily created and validated

## Implementation Status

Currently, the following data types have been standardized:

- ✅ Character
- ✅ MapSystem
- ✅ Killmail

The following data types are planned for standardization:

- ❌ Corporation
- ❌ Alliance
- ❌ UniverseType (ships)
- ❌ SolarSystem (from ESI)

## Recommendations

1. Continue standardizing the remaining data types
2. Enhance validation with more detailed error messages
3. Add tests for all data type conversions
4. Document all data structures in a central location
