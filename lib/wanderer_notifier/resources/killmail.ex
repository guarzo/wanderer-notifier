defmodule WandererNotifier.Resources.Killmail do
  @moduledoc """
  Ash resource representing a killmail record.
  Primary storage for core killmail data in the normalized model.
  """
  use Ash.Resource,
    domain: WandererNotifier.Resources.Api,
    data_layer: AshPostgres.DataLayer,
    extensions: [
      AshPostgres.Resource
    ]

  postgres do
    table("killmails")
    repo(WandererNotifier.Data.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:killmail_id, :integer, allow_nil?: false)
    attribute(:kill_time, :utc_datetime_usec)

    # Economic data (from zKB)
    attribute(:total_value, :decimal)
    attribute(:points, :integer)
    attribute(:is_npc, :boolean, default: false)
    attribute(:is_solo, :boolean, default: false)

    # System information
    attribute(:solar_system_id, :integer)
    attribute(:solar_system_name, :string)
    attribute(:solar_system_security, :float)
    attribute(:region_id, :integer)
    attribute(:region_name, :string)

    # Victim information
    attribute(:victim_id, :integer)
    attribute(:victim_name, :string)
    attribute(:victim_ship_id, :integer)
    attribute(:victim_ship_name, :string)
    attribute(:victim_corporation_id, :integer)
    attribute(:victim_corporation_name, :string)
    attribute(:victim_alliance_id, :integer)
    attribute(:victim_alliance_name, :string)

    # Basic attacker information
    attribute(:attacker_count, :integer)
    attribute(:final_blow_attacker_id, :integer)
    attribute(:final_blow_attacker_name, :string)
    attribute(:final_blow_ship_id, :integer)
    attribute(:final_blow_ship_name, :string)

    # Raw data preservation
    attribute(:zkb_hash, :string)
    # Keep this for detailed victim information
    attribute(:full_victim_data, :map)
    # Keep this for detailed attacker information
    attribute(:full_attacker_data, :term)

    # Metadata
    attribute(:processed_at, :utc_datetime_usec, default: &DateTime.utc_now/0)
    timestamps()
  end

  identities do
    identity(:unique_killmail, [:killmail_id])
  end

  relationships do
    has_many(:character_involvements, WandererNotifier.Resources.KillmailCharacterInvolvement)
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

      # Accept all attributes for the killmail
      accept([
        :killmail_id,
        :kill_time,
        :total_value,
        :points,
        :is_npc,
        :is_solo,
        :solar_system_id,
        :solar_system_name,
        :solar_system_security,
        :region_id,
        :region_name,
        :victim_id,
        :victim_name,
        :victim_ship_id,
        :victim_ship_name,
        :victim_corporation_id,
        :victim_corporation_name,
        :victim_alliance_id,
        :victim_alliance_name,
        :attacker_count,
        :final_blow_attacker_id,
        :final_blow_attacker_name,
        :final_blow_ship_id,
        :final_blow_ship_name,
        :zkb_hash,
        :full_victim_data,
        :full_attacker_data
      ])

      # Set the processed_at timestamp
      change(fn changeset, _context ->
        now = DateTime.utc_now()

        changeset
        |> Ash.Changeset.change_attribute(:processed_at, now)
        |> Ash.Changeset.force_change_attribute(:inserted_at, now |> DateTime.truncate(:second))
        |> Ash.Changeset.force_change_attribute(:updated_at, now |> DateTime.truncate(:second))
      end)
    end

    read :get_by_killmail_id do
      argument(:killmail_id, :integer, allow_nil?: false)
      filter(expr(killmail_id == ^arg(:killmail_id)))
    end

    read :list_by_date_range do
      argument(:from_date, :utc_datetime_usec, allow_nil?: false)
      argument(:to_date, :utc_datetime_usec, allow_nil?: false)
      argument(:limit, :integer, default: 100)

      filter(
        expr(
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
    define(:get, action: :read)
    define(:get_by_killmail_id, action: :get_by_killmail_id, args: [:killmail_id])
    define(:list_by_date_range, action: :list_by_date_range, args: [:from_date, :to_date, :limit])
    define(:create, action: :create)
    define(:update, action: :update)
    define(:destroy, action: :destroy)
  end

  # Custom queries for the code interface
  defmodule Queries do
    @moduledoc false
    import Ash.Query

    def get_by_killmail_id(query, killmail_id) do
      filter(query, killmail_id == ^killmail_id)
    end

    def list_by_date_range(query, from_date, to_date, limit) do
      query
      |> filter(kill_time >= ^from_date)
      |> filter(kill_time <= ^to_date)
      |> sort(kill_time: :desc)
      |> limit(limit)
    end
  end
end
