defmodule HttpBench do
  use Benchfella
  alias WandererNotifier.Infrastructure.Http

  setup_all do
    # Mock HTTP client to avoid real network calls in benchmarks
    Application.put_env(:wanderer_notifier, :http_client, HttpBenchMock)
    
    # Create a simple mock module
    defmodule HttpBenchMock do
      def get(_url, _headers, _opts) do
        {:ok, %{status_code: 200, body: "{\"test\": \"data\"}", headers: []}}
      end

      def post(_url, _body, _headers, _opts) do
        {:ok, %{status_code: 201, body: "{\"created\": true}", headers: []}}
      end
    end

    {:ok, []}
  end

  bench "http client with ESI config" do
    # Mock response for benchmarking
    Http.request(:get, "https://esi.evetech.net/latest/characters/123456/", nil, [], service: :esi)
  end

  bench "http client with WandererKills config" do
    Http.request(:get, "https://wanderer-kills.example.com/api/kills", nil, [], 
      service: :wanderer_kills
    )
  end

  bench "http client with retry logic" do
    Http.request(:get, "https://api.example.com/test", nil, [], 
      retry_count: 3, 
      timeout: 5000
    )
  end

  bench "http client basic get" do
    Http.request(:get, "https://api.example.com/data", nil, [], [])
  end

  bench "http client post with body" do
    Http.request(:post, "https://api.example.com/create", %{data: "test"}, [], 
      service: :license
    )
  end

  bench "http client with authentication" do
    Http.request(:get, "https://api.example.com/protected", nil, [], 
      auth: [type: :bearer, token: "test_token"]
    )
  end
end