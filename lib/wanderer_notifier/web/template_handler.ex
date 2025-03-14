defmodule WandererNotifier.Web.TemplateHandler do
  @moduledoc """
  Handles loading and rendering templates for the web interface.
  """
  require Logger

  @doc """
  Loads a template file from the appropriate location based on the environment.

  In production, templates are loaded from the priv directory.
  In development, templates are loaded from the lib directory.

  Returns the template content or an error message if the template is not found.
  """
  def load_template(template_name) do
    # Try to load from priv dir (for production/release)
    priv_path = Path.join(:code.priv_dir(:wanderer_notifier), "templates/#{template_name}")

    # Fallback to development path
    dev_path = Path.join(File.cwd!(), "lib/wanderer_notifier/web/templates/#{template_name}")

    cond do
      File.exists?(priv_path) ->
        {:ok, File.read!(priv_path)}

      File.exists?(dev_path) ->
        Logger.info("Loading template from development path: #{dev_path}")
        {:ok, File.read!(dev_path)}

      true ->
        Logger.warning("Template not found: #{template_name}")
        Logger.warning("Checked paths: #{priv_path}, #{dev_path}")
        {:error, "Template not found: #{template_name}"}
    end
  end

  @doc """
  Loads the dashboard template.

  Returns the dashboard HTML or a fallback message if the template is not found.
  """
  def dashboard_template do
    case load_template("dashboard.html.eex") do
      {:ok, content} -> content
      {:error, message} ->
        """
        <!DOCTYPE html>
        <html>
        <head><title>Wanderer Notifier - Template Error</title></head>
        <body>
          <h1>Template Error</h1>
          <p>#{message}</p>
          <p>Please ensure the dashboard template exists in one of the following locations:</p>
          <ul>
            <li>priv/templates/dashboard.html.eex</li>
            <li>lib/wanderer_notifier/web/templates/dashboard.html.eex</li>
          </ul>
        </body>
        </html>
        """
    end
  end
end
