- [ ] **Organize Code into Domain Contexts**  
  - Evaluate your modules and group them by business domain (e.g. \`Character\`, \`Kill\`, \`Chart\`).  
  - Move overlapping functionalities into shared context modules to isolate concerns and improve clarity.

- [ ] **Extract Common Controller Functions**  
  - Create helper functions in a base controller (e.g. in a module like \`BaseController\`) to send JSON responses.  
  - Example helper functions might include:  
    - \`send_json(conn, status, body)\` – sets the content type and sends the response.  
    - \`send_success(conn, data)\` – wraps a successful response with a standard format.  
    - \`send_error(conn, status, message)\` – standardizes error responses.  
  - Refactor all controllers to replace duplicate response code with calls to these helpers.

- [ ] **Consolidate Data Fetching Logic**  
  - Identify repeated calls (such as \`CharactersClient.get_character_activity(nil, 7)\`) and extract them into dedicated helper functions.  
  - Consider caching the fetched results for a short duration to reduce redundant external API calls and standardize error handling.

- [ ] **Refactor the Cache-then-API Pattern**  
  - Extract the pattern of attempting to fetch data from a cache and then falling back to an API call into its own helper function.  
  - This will simplify service modules (e.g. in \`KillsService\`) and make error handling uniform across your codebase.

- [ ] **Improve Error Handling with the \`with\` Construct**  
  - Replace nested \`case\` expressions with the \`with\` construct to flatten error handling.  
  - For example, refactor code like:  
    ```elixir
    case deps.esi_service.get_character(victim_id) do
      {:ok, victim} ->
        case deps.esi_service.get_type(ship_id) do
          {:ok, ship} ->
            {:ok, %{victim_name: victim["name"], ship_name: ship["name"]}}
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
    ```  
    Into:  
    ```elixir
    with {:ok, victim} <- deps.esi_service.get_character(victim_id),
         {:ok, ship} <- deps.esi_service.get_type(ship_id) do
      {:ok, %{victim_name: victim["name"], ship_name: ship["name"]}}
    else
      error -> 
        deps.logger.error("Error enriching kill", error: inspect(error))
        {:error, :api_error}
    end
    ```

- [ ] **Define Magic Numbers as Module Attributes**  
  - Replace hard-coded values (such as \`7\` for days or \`25\` for limits) with module attributes (e.g. \`@default_days 7\`).  
  - This centralizes configuration and makes future adjustments easier.

- [ ] **Enhance Documentation and Type Specifications**  
  - Ensure every public function has proper \`@doc\` and \`@spec\` annotations.  
  - Comprehensive documentation and type specifications improve code clarity, aid Dialyzer analysis, and support long-term maintainability.

- [ ] **Standardize Logging Practices**   - use AppLogger everywhere - map instead of keyword list
  - Create helper macros or functions for logging to enforce consistent log formatting and context information (such as request path or parameters).  
  - Use these standardized logging functions across controllers and services to make logs more uniform and easier to analyze.

- [ ] **Review and Simplify Configuration Mapping**  
  - Examine the legacy-to-new environment variable mapping in your \`runtime.exs\` file.  
  - Document the purpose of each mapping and refactor if possible to reduce complexity, ensuring future maintainers understand the rationale behind the mappings.

- [ ] **Ensure Consistent Dependency Injection**  
  - Verify that all service modules consistently use dependency injection (e.g. passing dependencies as maps).  
  - This approach improves testability and simplifies mocking during tests.

- [ ] **Consider Future Migration to Phoenix (Optional)**  
  - Assess whether your current Plug-based approach meets your growing needs.  
  - If your project increases in complexity, migrating to Phoenix may provide additional benefits like standardized error handling, parameter parsing, and built-in testing conveniences.

- [ ] **Refactor Controller Endpoints to Use New Helpers**  
  - Apply the new \`BaseController\` helper functions to all endpoints in controllers (e.g. in \`CharacterController\` and \`ChartController\`).  
  - Remove inline JSON response logic and replace it with calls to \`send_success/2\` and \`send_error/3\` for cleaner, more maintainable code.

