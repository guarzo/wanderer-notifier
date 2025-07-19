defmodule WandererNotifier.Infrastructure.Adapters.ESI.ClientV2 do
  @moduledoc """
  Client for interacting with the EVE Online ESI API.

  This is the refactored version using the unified HTTP client base.
  """

  use WandererNotifier.Infrastructure.Http.ClientBase,
    base_url: "https://esi.evetech.net/latest",
    timeout: 15_000,
    recv_timeout: 15_000,
    service_name: "eve_esi"

  alias WandererNotifier.Infrastructure.Http.Headers
  alias WandererNotifier.Shared.Utils.ErrorHandler
  @behaviour WandererNotifier.Infrastructure.Adapters.ESI.ClientBehaviour

  # Don't use ApiLoggerMacros since ClientBase provides logging functions

  @impl true
  @doc """
  Gets killmail information from ESI.
  """
  def get_killmail(kill_id, hash, opts \\ []) do
    url = "#{base_url()}/killmails/#{kill_id}/#{hash}/"

    ErrorHandler.with_retry(
      fn ->
        request(:get, url,
          with_timing: true,
          headers: esi_headers(),
          opts: build_request_opts(opts)
        )
        |> handle_esi_response("killmail", %{kill_id: kill_id})
      end,
      max_attempts: 3,
      retry_on: [:timeout, :network_error, :service_unavailable],
      base_delay: 500
    )
  end

  @impl true
  @doc """
  Gets character information from ESI.
  """
  def get_character_info(character_id, _opts \\ []) do
    url = "#{base_url()}/characters/#{character_id}/"

    ErrorHandler.with_retry(
      fn ->
        request(:get, url,
          headers: esi_headers(),
          opts: build_request_opts()
        )
        |> handle_esi_response("character", %{character_id: character_id})
      end,
      max_attempts: 3,
      retry_on: [:timeout, :network_error, :service_unavailable],
      base_delay: 500
    )
  end

  @impl true
  @doc """
  Gets corporation information from ESI.
  """
  def get_corporation_info(corporation_id, _opts \\ []) do
    url = "#{base_url()}/corporations/#{corporation_id}/"

    ErrorHandler.with_retry(
      fn ->
        request(:get, url,
          headers: esi_headers(),
          opts: build_request_opts()
        )
        |> handle_esi_response("corporation", %{corporation_id: corporation_id})
      end,
      max_attempts: 3,
      retry_on: [:timeout, :network_error, :service_unavailable],
      base_delay: 500
    )
  end

  @impl true
  @doc """
  Gets alliance information from ESI.
  """
  def get_alliance_info(alliance_id, _opts \\ []) do
    url = "#{base_url()}/alliances/#{alliance_id}/"

    ErrorHandler.with_retry(
      fn ->
        request(:get, url,
          headers: esi_headers(),
          opts: build_request_opts()
        )
        |> handle_esi_response("alliance", %{alliance_id: alliance_id})
      end,
      max_attempts: 3,
      retry_on: [:timeout, :network_error, :service_unavailable],
      base_delay: 500
    )
  end

  @impl true
  @doc """
  Gets type information from ESI.
  """
  def get_universe_type(type_id, _opts \\ []) do
    url = "#{base_url()}/universe/types/#{type_id}/"

    ErrorHandler.with_retry(
      fn ->
        request(:get, url,
          headers: esi_headers(),
          opts: build_request_opts()
        )
        |> handle_esi_response("type", %{type_id: type_id})
      end,
      max_attempts: 3,
      retry_on: [:timeout, :network_error, :service_unavailable],
      base_delay: 500
    )
  end

  @impl true
  @doc """
  Searches for inventory types in ESI.
  """
  def search_inventory_type(query, strict \\ false) do
    query_params = %{
      "categories" => "inventory_type",
      "search" => query,
      "strict" => to_string(strict)
    }

    url = "#{base_url()}/search/?#{URI.encode_query(query_params)}"

    log_api_info("ESI searching inventory type", %{
      query: query,
      strict: strict,
      method: "search_inventory_type"
    })

    request(:get, url,
      headers: esi_headers(),
      opts: build_request_opts()
    )
    |> handle_esi_response("search", %{query: query})
  end

  @impl true
  @doc """
  Gets solar system information from ESI.
  """
  def get_system(system_id, _opts \\ []) do
    url = "#{base_url()}/universe/systems/#{system_id}/?datasource=tranquility"

    ErrorHandler.with_retry(
      fn ->
        request(:get, url,
          headers: esi_headers(),
          opts: build_request_opts()
        )
        |> handle_system_response(system_id)
      end,
      max_attempts: 3,
      retry_on: [:timeout, :network_error, :service_unavailable],
      base_delay: 500
    )
  end

  @impl true
  @doc """
  Gets system kill statistics from ESI.
  """
  def get_system_kills(system_id, _limit \\ 5, _opts \\ []) do
    url = "#{base_url()}/universe/system_kills/"

    request(:get, url,
      headers: esi_headers(),
      opts: build_request_opts()
    )
    |> handle_esi_response("system_kills", %{system_id: system_id})
  end

  # Private helper functions

  defp esi_headers do
    Headers.esi_headers()
  end

  defp build_request_opts(additional_opts \\ []) do
    config = %{
      timeout: default_timeout(),
      recv_timeout: default_recv_timeout(),
      retry_options: [
        max_attempts: 3,
        base_backoff: 1000,
        retryable_errors: [:timeout, :connect_timeout, :econnrefused],
        retryable_status_codes: [429, 500, 502, 503, 504],
        context: "ESI request"
      ],
      rate_limit_options: [
        per_host: true,
        requests_per_second: 20,
        burst_capacity: 40
      ],
      telemetry_options: [
        service_name: service_name()
      ]
    }

    build_default_opts(additional_opts, config)
  end

  defp handle_esi_response(response, resource_type, context) do
    handle_response(response,
      resource_type: resource_type,
      context: context,
      custom_handlers: [
        {404,
         fn _status, _body ->
           log_api_info("ESI #{resource_type} not found", context)
           {:error, :not_found}
         end}
      ]
    )
  end

  defp handle_system_response({:ok, %{status_code: status, body: body}}, _system_id)
       when status in 200..299 do
    {:ok, body}
  end

  defp handle_system_response({:ok, %{status_code: 404, body: _body}}, system_id) do
    error = {:error, :not_found}
    ErrorHandler.enrich_error(error, %{resource: "system", system_id: system_id})
  end

  defp handle_system_response({:ok, %{status_code: status, body: body}}, system_id) do
    error = ErrorHandler.http_error_to_tuple(status)

    ErrorHandler.log_error("ESI solar system error response", elem(error, 1), %{
      system_id: system_id,
      status: status,
      body: inspect(body)
    })

    error
  end

  defp handle_system_response({:error, reason}, system_id) do
    normalized = ErrorHandler.normalize_error({:error, reason})

    ErrorHandler.log_error("ESI solar system failed", elem(normalized, 1), %{
      system_id: system_id
    })

    normalized
  end
end
