# Killmail Module Refactoring Implementation Plan

## Phase 1: Create New Structure and Module Framework (1-2 days)

1. **Create KillmailData Structure**

   ```elixir
   # lib/wanderer_notifier/killmail_processing/killmail_data.ex
   defmodule WandererNotifier.KillmailProcessing.KillmailData do
     @moduledoc """
     Defines the in-memory structure for killmail data during processing.
     This is used throughout the pipeline before persistence decisions are made.
     """

     @type t :: %__MODULE__{
       killmail_id: integer(),
       zkb_data: map(),
       esi_data: map(),
       solar_system_id: integer() | nil,
       solar_system_name: String.t() | nil,
       kill_time: DateTime.t() | nil,
       victim: map() | nil,
       attackers: list() | nil,
       persisted: boolean(),
       metadata: map()
     }

     defstruct [
       :killmail_id,
       :zkb_data,
       :esi_data,
       :solar_system_id,
       :solar_system_name,
       :kill_time,
       :victim,
       :attackers,
       persisted: false,
       metadata: %{}
     ]

     def from_zkb_and_esi(zkb_data, esi_data) do
       kill_id = Map.get(zkb_data, "killmail_id") || Map.get(zkb_data, :killmail_id)

       %__MODULE__{
         killmail_id: kill_id,
         zkb_data: zkb_data,
         esi_data: esi_data,
         solar_system_id: extract_system_id(esi_data),
         solar_system_name: Map.get(esi_data, "solar_system_name"),
         kill_time: extract_kill_time(esi_data),
         victim: Map.get(esi_data, "victim"),
         attackers: Map.get(esi_data, "attackers")
       }
     end

     def from_resource(resource) do
       %__MODULE__{
         killmail_id: resource.killmail_id,
         solar_system_id: resource.solar_system_id,
         solar_system_name: resource.solar_system_name,
         kill_time: resource.kill_time,
         victim: resource.full_victim_data,
         attackers: resource.full_attacker_data,
         persisted: true
       }
     end

     # Helper functions to extract data
     defp extract_system_id(esi_data) do
       system_id = Map.get(esi_data, "solar_system_id")

       cond do
         is_integer(system_id) -> system_id
         is_binary(system_id) ->
           case Integer.parse(system_id) do
             {id, _} -> id
             :error -> nil
           end
         true -> nil
       end
     end

     defp extract_kill_time(esi_data) do
       kill_time = Map.get(esi_data, "killmail_time")

       cond do
         is_struct(kill_time, DateTime) -> kill_time
         is_binary(kill_time) ->
           case DateTime.from_iso8601(kill_time) do
             {:ok, datetime, _} -> datetime
             _ -> DateTime.utc_now()
           end
         true -> DateTime.utc_now()
       end
     end
   end
   ```

2. **Create Extractor Module**

   ```elixir
   # lib/wanderer_notifier/killmail_processing/extractor.ex
   defmodule WandererNotifier.KillmailProcessing.Extractor do
     @moduledoc """
     Functions for extracting data from killmail structures.
     Works with KillmailData, database resources, and raw API data.
     """

     alias WandererNotifier.KillmailProcessing.KillmailData
     alias WandererNotifier.Resources.Killmail, as: KillmailResource

     @type killmail_source :: KillmailData.t() | KillmailResource.t() | map()

     @spec get_system_id(killmail_source()) :: integer() | nil
     def get_system_id(%KillmailData{solar_system_id: id}) when not is_nil(id), do: id
     def get_system_id(%KillmailResource{solar_system_id: id}) when not is_nil(id), do: id
     def get_system_id(%{esi_data: %{"solar_system_id" => id}}) when not is_nil(id), do: id
     def get_system_id(%{solar_system_id: id}) when not is_nil(id), do: id
     def get_system_id(_), do: nil

     @spec get_system_name(killmail_source()) :: String.t() | nil
     def get_system_name(%KillmailData{solar_system_name: name}) when is_binary(name), do: name
     def get_system_name(%KillmailResource{solar_system_name: name}) when is_binary(name), do: name
     def get_system_name(%{esi_data: %{"solar_system_name" => name}}) when is_binary(name), do: name
     def get_system_name(%{solar_system_name: name}) when is_binary(name), do: name
     def get_system_name(_), do: nil

     @spec get_victim(killmail_source()) :: map()
     def get_victim(%KillmailData{victim: victim}) when is_map(victim), do: victim
     def get_victim(%KillmailResource{full_victim_data: victim}) when is_map(victim), do: victim
     def get_victim(%{esi_data: %{"victim" => victim}}) when is_map(victim), do: victim
     def get_victim(%{victim: victim}) when is_map(victim), do: victim
     def get_victim(_), do: %{}

     @spec get_attackers(killmail_source()) :: [map()]
     def get_attackers(%KillmailData{attackers: attackers}) when is_list(attackers), do: attackers
     def get_attackers(%KillmailResource{full_attacker_data: attackers}) when is_list(attackers), do: attackers
     def get_attackers(%{esi_data: %{"attackers" => attackers}}) when is_list(attackers), do: attackers
     def get_attackers(%{attackers: attackers}) when is_list(attackers), do: attackers
     def get_attackers(_), do: []

     @spec debug_data(killmail_source()) :: map()
     def debug_data(killmail) do
       %{
         struct_type: if(is_struct(killmail), do: killmail.__struct__, else: :not_struct),
         killmail_id: get_killmail_id(killmail),
         has_victim_data: not Enum.empty?(get_victim(killmail)),
         has_attacker_data: not Enum.empty?(get_attackers(killmail)),
         system_id: get_system_id(killmail),
         system_name: get_system_name(killmail),
         attacker_count: length(get_attackers(killmail))
       }
     end

     defp get_killmail_id(%KillmailData{killmail_id: id}), do: id
     defp get_killmail_id(%KillmailResource{killmail_id: id}), do: id
     defp get_killmail_id(%{killmail_id: id}) when not is_nil(id), do: id
     defp get_killmail_id(%{"killmail_id" => id}) when not is_nil(id), do: id
     defp get_killmail_id(_), do: nil
   end

   ```

3. **Create KillmailQueries Module**

   ```elixir
   # lib/wanderer_notifier/killmail_processing/killmail_queries.ex
   defmodule WandererNotifier.KillmailProcessing.KillmailQueries do
     @moduledoc """
     Database query functions for killmails.
     Provides a clean interface for retrieving killmails from the database.
     """

     require Ash.Query

     alias WandererNotifier.Resources.Api
     alias WandererNotifier.Resources.Killmail, as: KillmailResource
     alias WandererNotifier.Resources.KillmailCharacterInvolvement

     @doc """
     Checks if a killmail exists in the database by its ID.
     """
     @spec exists?(integer()) :: boolean()
     def exists?(killmail_id) do
       case Api.read(
              KillmailResource
              |> Ash.Query.filter(killmail_id == ^killmail_id)
              |> Ash.Query.select([:id])
              |> Ash.Query.limit(1)
            ) do
         {:ok, [_record]} -> true
         _ -> false
       end
     end

     @doc """
     Gets a killmail by its ID.
     """
     @spec get(integer()) :: {:ok, KillmailResource.t()} | {:error, :not_found}
     def get(killmail_id) do
       case Api.read(
              KillmailResource
              |> Ash.Query.filter(killmail_id == ^killmail_id)
              |> Ash.Query.limit(1)
            ) do
         {:ok, [killmail]} -> {:ok, killmail}
         _ -> {:error, :not_found}
       end
     end

     @doc """
     Gets all character involvements for a killmail.
     """
     @spec get_involvements(integer()) :: {:ok, [KillmailCharacterInvolvement.t()]} | {:error, :not_found}
     def get_involvements(killmail_id) do
       case exists?(killmail_id) do
         true ->
           Api.read(
             KillmailCharacterInvolvement
             |> Ash.Query.filter(killmail.killmail_id == ^killmail_id)
           )

         false ->
           {:error, :not_found}
       end
     end

     @doc """
     Finds all killmails involving a character within a date range.
     """
     @spec find_by_character(integer(), DateTime.t(), DateTime.t(), keyword()) ::
           {:ok, [KillmailResource.t()]} | {:error, any()}
     def find_by_character(character_id, start_date, end_date, opts \\ []) do
       role = Keyword.get(opts, :role)
       limit = Keyword.get(opts, :limit, 100)
       sort_dir = Keyword.get(opts, :sort, :desc)

       query =
         KillmailCharacterInvolvement
         |> Ash.Query.filter(character_id == ^character_id)
         |> then(fn q ->
           if role, do: Ash.Query.filter(q, character_role == ^role), else: q
         end)
         |> Ash.Query.load(:killmail)
         |> Ash.Query.filter(killmail.kill_time >= ^start_date)
         |> Ash.Query.filter(killmail.kill_time <= ^end_date)
         |> Ash.Query.sort({:expr, [:killmail, :kill_time]}, sort_dir)
         |> Ash.Query.limit(limit)

       case Api.read(query) do
         {:ok, involvements} ->
           killmails = Enum.map(involvements, & &1.killmail)
           {:ok, killmails}

         error ->
           error
       end
     end
   end
   ```

4. **Create Validator Module**

   ```elixir
   # lib/wanderer_notifier/killmail_processing/validator.ex
   defmodule WandererNotifier.KillmailProcessing.Validator do
     @moduledoc """
     Validation functions for killmail data.
     """

     alias WandererNotifier.KillmailProcessing.Extractor

     @doc """
     Validates that a killmail has complete data for processing.
     """
     @spec validate_complete_data(Extractor.killmail_source()) :: :ok | {:error, String.t()}
     def validate_complete_data(killmail) do
       debug_data = Extractor.debug_data(killmail)

       field_checks = [
         {:killmail_id, debug_data.killmail_id, "Killmail ID missing"},
         {:system_id, debug_data.system_id, "Solar system ID missing"},
         {:system_name, debug_data.system_name, "Solar system name missing"},
         {:victim, debug_data.has_victim_data, "Victim data missing"}
       ]

       # Find first failure
       case Enum.find(field_checks, fn {_, value, _} -> is_nil(value) || value == false end) do
         nil -> :ok
         {_, _, reason} -> {:error, reason}
       end
     end
   end
   ```

## Phase 2: Update the Root Killmail Module (1 day)

1. **Update the Root Killmail Module with Delegations**

   ```elixir
   # lib/wanderer_notifier/killmail.ex
   defmodule WandererNotifier.Killmail do
     @moduledoc """
     Utility functions for working with killmail data from various sources.

     NOTE: This module provides backward compatibility with existing code.
     New code should use the specialized modules in the KillmailProcessing namespace.

     @deprecated Use WandererNotifier.KillmailProcessing modules instead.
     """

     alias WandererNotifier.KillmailProcessing.Extractor
     alias WandererNotifier.KillmailProcessing.KillmailQueries
     alias WandererNotifier.KillmailProcessing.Validator

     # Delegate database access functions to KillmailQueries
     defdelegate exists?(killmail_id), to: KillmailQueries
     defdelegate get(killmail_id), to: KillmailQueries
     defdelegate get_involvements(killmail_id), to: KillmailQueries
     defdelegate find_by_character(character_id, start_date, end_date, opts \\ []), to: KillmailQueries

     # Keep the get/3 function for backward compatibility
     def get(killmail, field, default \\ nil) do
       field_atom = if is_binary(field), do: String.to_atom(field), else: field
       field_str = if is_atom(field), do: Atom.to_string(field), else: field

       cond do
         # Check for struct with atom key
         is_struct(killmail) && Map.has_key?(killmail, field_atom) ->
           Map.get(killmail, field_atom)

         # Check map with atom key
         is_map(killmail) && Map.has_key?(killmail, field_atom) ->
           Map.get(killmail, field_atom)

         # Check map with string key
         is_map(killmail) && Map.has_key?(killmail, field_str) ->
           Map.get(killmail, field_str)

         true ->
           default
       end
     end

     # Delegate common extraction functions to Extractor
     defdelegate get_system_id(killmail), to: Extractor
     defdelegate get_victim(killmail), to: Extractor
     defdelegate get_attackers(killmail), to: Extractor
     defdelegate debug_data(killmail), to: Extractor

     # Delegate validation to Validator
     defdelegate validate_complete_data(killmail), to: Validator

     # Keep any specialized functions that don't fit in the new modules,
     # but make sure they use the Extractor internally
     def find_field(killmail, field, character_id, role) do
       case role do
         :victim ->
           victim = Extractor.get_victim(killmail)

           if to_string(Map.get(victim, "character_id", "")) == to_string(character_id) do
             Map.get(victim, field)
           else
             nil
           end

         :attacker ->
           attackers = Extractor.get_attackers(killmail)

           attacker =
             Enum.find(attackers, fn a ->
               to_string(Map.get(a, "character_id", "")) == to_string(character_id)
             end)

           if attacker, do: Map.get(attacker, field), else: nil

         _ ->
           nil
       end
     end
   end
   ```

## Phase 3: Update Pipeline and Enrichment (1-2 days)

1. **Update pipeline.ex**

   - Update imports to use the new modules
   - Update code to work with KillmailData

   Key changes:

   ```elixir
   alias WandererNotifier.KillmailProcessing.{Context, Extractor, KillmailData, Metrics}

   # In create_normalized_killmail
   {:ok, KillmailData.from_zkb_and_esi(zkb_data, esi_data)}

   # In log_validation_failure
   debug_data = Extractor.debug_data(killmail)

   # In other places where Killmail.get_kill_id was used
   defp get_kill_id(data), do: Extractor.get_killmail_id(data)
   ```

2. **Update enrichment.ex**
   - Update to use KillmailData and Extractor

## Phase 4: Testing and Documentation (1-2 days)

1. **Add Unit Tests**

   ```elixir
   # test/killmail_processing/extractor_test.exs
   defmodule WandererNotifier.KillmailProcessing.ExtractorTest do
     use ExUnit.Case

     alias WandererNotifier.KillmailProcessing.{Extractor, KillmailData}

     test "extracts system_id from KillmailData" do
       killmail = %KillmailData{solar_system_id: 12345}
       assert Extractor.get_system_id(killmail) == 12345
     end

     # More tests...
   end
   ```

2. **Add Documentation**
   - Update all @moduledoc sections with clear explanations
   - Add examples to function documentation
   - Create a central document explaining the killmail processing flow

## Phase 5: Gradual Transition (Ongoing)

1. **Update Caller Code**

   - Gradually update code that uses the old Killmail module
   - Prefer direct imports of the specialized modules

2. **Monitoring**
   - Track usage of deprecated functions
   - Add telemetry to check for performance improvements

## Timeline

- **Phase 1**: 1-2 days - Create basic structure and functionality
- **Phase 2**: 1 day - Update root module for backward compatibility
- **Phase 3**: 1-2 days - Update pipeline and enrichment code
- **Phase 4**: 1-2 days - Add tests and documentation
- **Phase 5**: Ongoing - Gradually transition code to new structure

Total estimated time: 4-7 days of focused work
