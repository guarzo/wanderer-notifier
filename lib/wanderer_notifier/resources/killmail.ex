defmodule WandererNotifier.Resources.Killmail do
  @moduledoc """
  Ash resource representing a killmail record.
  Stores killmail data related to tracked characters.
  """
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [
      AshPostgres.Resource
    ]

  # Predefine atoms to ensure they exist at compile time
  @character_roles [:attacker, :victim]

  postgres do
    table("killmails")
    repo(WandererNotifier.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:killmail_id, :integer, allow_nil?: false)
    attribute(:kill_time, :utc_datetime_usec)
    attribute(:solar_system_id, :integer)
    attribute(:solar_system_name, :string)
    attribute(:region_id, :integer)
    attribute(:region_name, :string)
    attribute(:total_value, :decimal)

    # Character was victim or attacker
    attribute(:character_role, :atom, constraints: [one_of: @character_roles])

    # Character details duplicated for query efficiency
    attribute(:related_character_id, :integer, allow_nil?: false)
    attribute(:related_character_name, :string)

    # Ship information
    attribute(:ship_type_id, :integer)
    attribute(:ship_type_name, :string)

    # JSON fields for additional data
    attribute(:zkb_data, :map)
    attribute(:victim_data, :map)
    attribute(:attacker_data, :map)

    # Metadata
    attribute(:processed_at, :utc_datetime_usec, default: &DateTime.utc_now/0)

    timestamps()
  end

  identities do
  end

  relationships do
    belongs_to(:character, WandererNotifier.Resources.TrackedCharacter,
      source_attribute: :related_character_id,
      destination_attribute: :character_id,
      define_attribute?: false
    )
  end

  aggregates do
  end

  calculations do
    calculate(
      :formatted_value,
      :string,
      expr(
        if is_nil(total_value) do
          "0 ISK"
        else
          cond do
            total_value < 1000 -> "<1k ISK"
            total_value < 1_000_000 -> concat(cast(trunc(total_value / 1000), :string), "k ISK")
            true -> concat(cast(trunc(total_value / 1_000_000), :string), "M ISK")
          end
        end
      )
    )
  end

  actions do
    defaults([:read, :update, :destroy])

    create :create do
      primary?(true)

      accept([
        :killmail_id,
        :kill_time,
        :solar_system_id,
        :solar_system_name,
        :region_id,
        :region_name,
        :total_value,
        :character_role,
        :related_character_id,
        :related_character_name,
        :ship_type_id,
        :ship_type_name,
        :zkb_data,
        :victim_data,
        :attacker_data
      ])

      argument(:killmail_id, :integer, allow_nil?: false)

      argument(:character_role, :atom,
        allow_nil?: false,
        constraints: [one_of: @character_roles]
      )

      argument(:related_character_id, :integer, allow_nil?: false)

      change(
        before_action(fn changeset ->
          Ash.Changeset.change_attribute(changeset, :processed_at, DateTime.utc_now())
        end)
      )
    end

    read :get_by_killmail_id do
      argument(:killmail_id, :integer, allow_nil?: false)
      filter(expr(killmail_id == ^arg(:killmail_id)))
    end

    read :list_for_character do
      argument(:character_id, :integer, allow_nil?: false)
      argument(:from_date, :utc_datetime_usec, allow_nil?: false)
      argument(:to_date, :utc_datetime_usec, allow_nil?: false)
      argument(:limit, :integer, default: 10)

      filter(
        expr(
          related_character_id == ^arg(:character_id) and
            kill_time >= ^arg(:from_date) and
            kill_time <= ^arg(:to_date)
        )
      )

      prepare(fn query, _context ->
        query
        |> Ash.Query.sort(kill_time: :desc)
        |> Ash.Query.limit(arg(:limit))
      end)
    end
  end

  code_interface do
    define_for(WandererNotifier.Resources.Api)
    define(:get_by_killmail_id, args: [:killmail_id])
    define(:list_for_character, args: [:character_id, :from_date, :to_date, :limit])
    define(:create, args: [:attributes])
  end

  # Custom queries for the code interface
  defmodule Queries do
    @moduledoc false
    import Ash.Query

    def get_by_killmail_id(query, killmail_id) do
      filter(query, killmail_id == ^killmail_id)
    end

    def list_for_character(query, character_id, from_date, to_date, limit) do
      query
      |> filter(related_character_id == ^character_id)
      |> filter(kill_time >= ^from_date)
      |> filter(kill_time <= ^to_date)
      |> sort(kill_time: :desc)
      |> limit(limit)
    end
  end
end
