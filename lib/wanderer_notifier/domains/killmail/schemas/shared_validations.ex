defmodule WandererNotifier.Domains.Killmail.Schemas.SharedValidations do
  @moduledoc """
  Shared validation functions for killmail schemas to eliminate code duplication.

  This module contains common validation logic used by both Attacker and Victim schemas.
  """

  import Ecto.Changeset

  @doc """
  Validates character name consistency between ID and name fields.
  Includes character name length validation (1-37 characters).
  """
  def validate_character_name_consistency(changeset, id_field, name_field) do
    changeset
    |> validate_id_name_consistency(id_field, name_field, "Character")
    |> validate_name_length(name_field, 37)
  end

  @doc """
  Validates corporation name consistency between ID and name fields.
  Includes corporation name length validation (1-100 characters).
  """
  def validate_corporation_name_consistency(changeset, id_field, name_field) do
    changeset
    |> validate_id_name_consistency(id_field, name_field, "Corporation")
    |> validate_name_length(name_field, 100)
  end

  @doc """
  Normalizes WebSocket field data by ensuring consistent field types and formats.
  Accepts a changeset and list of field mappings.
  """
  def normalize_websocket_fields(changeset, fields) do
    Enum.reduce(fields, changeset, fn {field, type}, acc ->
      normalize_field(acc, field, type)
    end)
  end

  @doc """
  Normalizes common WebSocket character/corporation/alliance fields.
  Returns normalized map data ready for changeset creation.
  """
  def normalize_websocket_character_data(ws_data, additional_fields \\ []) do
    # Common character/corporation/alliance fields
    base_fields = [
      {"character_id", :character_id},
      {"character_name", :character_name},
      {"corporation_id", :corporation_id},
      {"corporation_name", :corporation_name},
      {"alliance_id", :alliance_id},
      {"alliance_name", :alliance_name},
      {"ship_type_id", :ship_type_id},
      {"ship_name", :ship_name}
    ]

    # Normalize base fields - convert string keys to atoms
    normalized =
      base_fields
      |> Enum.reduce(%{}, fn {string_key, atom_key}, acc ->
        if value = ws_data[string_key] do
          Map.put(acc, atom_key, value)
        else
          acc
        end
      end)

    # Add additional schema-specific fields
    additional_fields
    |> Enum.reduce(normalized, fn field, acc ->
      string_field = to_string(field)
      atom_field = String.to_atom(string_field)

      if value = ws_data[string_field] do
        Map.put(acc, atom_field, value)
      else
        acc
      end
    end)
  end

  # Private helper functions

  defp validate_id_name_consistency(changeset, id_field, name_field, entity_type) do
    entity_id = get_field(changeset, id_field)
    entity_name = get_field(changeset, name_field)

    case {entity_id, entity_name} do
      {nil, nil} ->
        changeset

      {id, nil} when not is_nil(id) ->
        add_error(
          changeset,
          name_field,
          "#{entity_type} name required when #{entity_type |> String.downcase()} ID is present"
        )

      {nil, name} when not is_nil(name) ->
        add_error(
          changeset,
          id_field,
          "#{entity_type} ID required when #{entity_type |> String.downcase()} name is present"
        )

      {id, name} when not is_nil(id) and not is_nil(name) ->
        changeset

      _ ->
        changeset
    end
  end

  defp validate_name_length(changeset, name_field, max_length) do
    case get_field(changeset, name_field) do
      name when is_binary(name) ->
        if String.length(name) > 0 and String.length(name) <= max_length do
          changeset
        else
          add_error(
            changeset,
            name_field,
            "#{field_name(name_field)} must be 1-#{max_length} characters"
          )
        end

      _ ->
        changeset
    end
  end

  defp field_name(field) do
    field
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp normalize_field(changeset, field, :integer) do
    case get_field(changeset, field) do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {int_value, ""} -> put_change(changeset, field, int_value)
          _ -> changeset
        end

      _ ->
        changeset
    end
  end

  defp normalize_field(changeset, field, :string) do
    case get_field(changeset, field) do
      value when is_integer(value) ->
        put_change(changeset, field, to_string(value))

      _ ->
        changeset
    end
  end

  defp normalize_field(changeset, _field, _type), do: changeset
end
