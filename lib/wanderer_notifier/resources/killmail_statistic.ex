defmodule WandererNotifier.Resources.KillmailStatistic do
  @moduledoc """
  Ash resource for aggregated killmail statistics.
  Stores statistics about kills and deaths for tracked characters over different time periods.
  """
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [
      AshPostgres.Resource
    ]

  # Predefine atoms to ensure they exist at compile time
  @period_types [:daily, :weekly, :monthly]

  postgres do
    table("killmail_statistics")
    repo(WandererNotifier.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    # Aggregation period
    attribute(:period_type, :atom, constraints: [one_of: @period_types])
    attribute(:period_start, :date)
    attribute(:period_end, :date)

    # Character information
    attribute(:character_id, :integer, allow_nil?: false)
    attribute(:character_name, :string)

    # Statistics
    attribute(:kills_count, :integer, default: 0)
    attribute(:deaths_count, :integer, default: 0)
    attribute(:isk_destroyed, :decimal, default: 0)
    attribute(:isk_lost, :decimal, default: 0)

    # Activity breakdown by region
    attribute(:region_activity, :map, default: %{})

    # Ship type usage
    attribute(:ship_usage, :map, default: %{})

    # Additional statistics for reporting
    attribute(:top_victim_corps, :map, default: %{})
    attribute(:top_victim_ships, :map, default: %{})
    attribute(:detailed_ship_usage, :map, default: %{})

    timestamps()
  end

  identities do
    identity(:unique_character_period, [:character_id, :period_type, :period_start])
  end

  relationships do
  end

  aggregates do
  end

  calculations do
    calculate(
      :efficiency,
      :decimal,
      expr(
        if kills_count + deaths_count > 0 do
          kills_count / (kills_count + deaths_count) * 100
        else
          0
        end
      )
    )

    calculate(
      :formatted_isk_destroyed,
      :string,
      expr(
        if is_nil(isk_destroyed) or isk_destroyed == 0 do
          "0 ISK"
        else
          cond do
            isk_destroyed < 1000 ->
              "<1k ISK"

            isk_destroyed < 1_000_000 ->
              concat(cast(trunc(isk_destroyed / 1000), :string), "k ISK")

            isk_destroyed < 1_000_000_000 ->
              concat(cast(trunc(isk_destroyed / 1_000_000), :string), "M ISK")

            true ->
              concat(cast(trunc(isk_destroyed / 1_000_000_000), :string), "B ISK")
          end
        end
      )
    )

    calculate(
      :formatted_isk_lost,
      :string,
      expr(
        if is_nil(isk_lost) or isk_lost == 0 do
          "0 ISK"
        else
          cond do
            isk_lost < 1000 ->
              "<1k ISK"

            isk_lost < 1_000_000 ->
              concat(cast(trunc(isk_lost / 1000), :string), "k ISK")

            isk_lost < 1_000_000_000 ->
              concat(cast(trunc(isk_lost / 1_000_000), :string), "M ISK")

            true ->
              concat(cast(trunc(isk_lost / 1_000_000_000), :string), "B ISK")
          end
        end
      )
    )
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :period_type,
        :period_start,
        :period_end,
        :character_id,
        :character_name,
        :kills_count,
        :deaths_count,
        :isk_destroyed,
        :isk_lost,
        :region_activity,
        :ship_usage,
        :top_victim_corps,
        :top_victim_ships,
        :detailed_ship_usage
      ])
    end

    update :update do
      primary?(true)

      accept([
        :kills_count,
        :deaths_count,
        :isk_destroyed,
        :isk_lost,
        :region_activity,
        :ship_usage,
        :top_victim_corps,
        :top_victim_ships,
        :detailed_ship_usage
      ])
    end

    read :by_character_and_period do
      argument(:character_id, :integer)
      argument(:period_type, :atom, constraints: [one_of: @period_types])
      argument(:start_date, :date)

      filter(
        expr(
          character_id == ^arg(:character_id) and
            period_type == ^arg(:period_type) and
            period_start == ^arg(:start_date)
        )
      )
    end

    read :for_character do
      argument(:character_id, :integer)
      argument(:period_type, :atom, constraints: [one_of: @period_types])
      argument(:limit, :integer, default: 10)

      filter(expr(character_id == ^arg(:character_id) and period_type == ^arg(:period_type)))

      prepare(fn query, _context ->
        query
        |> Ash.Query.sort(period_start: :desc)
        |> Ash.Query.limit(arg(:limit))
      end)
    end
  end

  code_interface do
    define_for(WandererNotifier.Resources.Api)
    define(:by_character_and_period, args: [:character_id, :period_type, :start_date])
    define(:for_character, args: [:character_id, :period_type, :limit])
    define(:create, args: [:attributes])
    define(:update, args: [:id, :attributes])
  end
end
