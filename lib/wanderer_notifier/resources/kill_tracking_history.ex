defmodule WandererNotifier.Resources.KillTrackingHistory do
  use Ash.Resource,
    domain: WandererNotifier.Resources.Api,
    data_layer: AshPostgres.DataLayer,
    extensions: [
      AshPostgres.Resource
    ]

  postgres do
    table("kill_tracking_history")
    repo(WandererNotifier.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :character_id, :integer do
      allow_nil?(false)
    end

    attribute :timestamp, :utc_datetime do
      allow_nil?(false)
    end

    attribute :our_kills_count, :integer do
      allow_nil?(false)
    end

    attribute :zkill_kills_count, :integer do
      allow_nil?(false)
    end

    attribute :missing_kills, {:array, :integer} do
      allow_nil?(true)
    end

    attribute :analysis_results, :map do
      allow_nil?(true)
    end

    attribute :api_metrics, :map do
      allow_nil?(true)
    end

    attribute :time_range_type, :string do
      allow_nil?(false)
    end

    timestamps()
  end

  actions do
    defaults([:create, :read, :update, :destroy])

    create :record_comparison do
      accept([
        :character_id,
        :timestamp,
        :our_kills_count,
        :zkill_kills_count,
        :missing_kills,
        :analysis_results,
        :api_metrics,
        :time_range_type
      ])

      primary?(true)
    end

    read :get_latest_for_character do
      filter(
        expr(
          character_id == ^arg(:character_id) and
            time_range_type == ^arg(:time_range_type)
        )
      )

      prepare(fn query, _context ->
        query
        |> Ash.Query.sort(timestamp: :desc)
        |> Ash.Query.limit(1)
      end)
    end

    read :get_history_for_character do
      filter(
        expr(
          character_id == ^arg(:character_id) and
            time_range_type == ^arg(:time_range_type)
        )
      )

      argument(:limit, :integer, default: 100)

      prepare(fn query, _context ->
        query
        |> Ash.Query.sort(timestamp: :desc)
        |> Ash.Query.limit(arg(:limit))
      end)
    end
  end

  code_interface do
    define(:get, action: :read)
    define(:record_comparison, action: :record_comparison)

    define(:get_latest_for_character,
      action: :get_latest_for_character,
      args: [:character_id, :time_range_type]
    )

    define(:get_history_for_character,
      action: :get_history_for_character,
      args: [:character_id, :time_range_type, :limit]
    )

    define(:create, action: :create)
    define(:update, action: :update)
    define(:destroy, action: :destroy)
  end
end
