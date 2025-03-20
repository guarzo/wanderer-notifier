defmodule WandererNotifier.ChartService.FallbackStrategy do
  @moduledoc """
  Standardized fallback strategies for chart generation.
  
  This module provides consistent fallback handling for when primary chart generation 
  methods fail. It implements different strategies for handling failures, logging, 
  and providing alternative chart generation methods.
  """
  
  require Logger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  
  @typedoc """
  Options for fallback strategies
  """
  @type fallback_options :: [
    # Function that will be called to attempt download
    download_fn: (binary() -> {:ok, binary()} | {:error, any()}),
    # Options for controlling the fallback behavior
    max_retries: non_neg_integer(),
    # Enable or disable specific fallback methods
    enable_download: boolean(),
    enable_quickchart: boolean(),
    enable_placeholder: boolean()
  ]
  
  @doc """
  Executes a primary chart generation function with a fallback strategy.
  
  ## Parameters
    - primary_fn: The primary chart generation function to attempt first
    - fallback_fn: The fallback function to use if primary fails
    - options: Options to control the fallback behavior
    
  ## Returns
    - {:ok, result} from either the primary or fallback function
    - {:error, reason} if all methods fail
  """
  @spec with_fallback(
    (-> {:ok, any()} | {:error, any()}),
    (-> {:ok, any()} | {:error, any()}),
    Keyword.t()
  ) :: {:ok, any()} | {:error, any()}
  def with_fallback(primary_fn, fallback_fn, _options \\ []) do
    # Try the primary function
    case primary_fn.() do
      {:ok, _result} = success ->
        # Success! Return the result
        success
        
      {:error, reason} ->
        # Log the failure
        Logger.warning("Primary chart generation failed: #{inspect(reason)}. Using fallback.")
        
        # Try the fallback function
        case fallback_fn.() do
          {:ok, _} = success ->
            success
            
          {:error, fallback_reason} ->
            Logger.error("Fallback chart generation also failed: #{inspect(fallback_reason)}")
            {:error, {:fallback_chain_failed, reason, fallback_reason}}
        end
    end
  end
  
  @doc """
  Downloads a chart image from a URL with retries.
  
  ## Parameters
    - url: The URL to download the chart from
    - options: Options for controlling the download behavior
    
  ## Returns
    - {:ok, binary} with the image data
    - {:error, reason} if download fails
  """
  @spec download_with_retry(binary(), Keyword.t()) :: {:ok, binary()} | {:error, any()}
  def download_with_retry(url, options \\ []) do
    max_retries = Keyword.get(options, :max_retries, 2)
    do_download_with_retry(url, max_retries, 0)
  end
  
  # Recursive implementation of download with retry
  defp do_download_with_retry(_url, max_retries, attempt) when attempt > max_retries do
    {:error, :max_retries_exceeded}
  end
  
  defp do_download_with_retry(url, max_retries, attempt) do
    Logger.info("Downloading chart image from: #{url}, attempt #{attempt + 1}/#{max_retries + 1}")
    
    case HttpClient.request("GET", url, [], "") do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}
      
      {:ok, %{status_code: status, body: _body}} ->
        Logger.error("Failed to download chart image. Status: #{status}, attempt: #{attempt + 1}")
        
        # Exponential backoff - wait longer between retries
        if attempt < max_retries do
          # Sleep for 500ms, 1000ms, etc.
          :timer.sleep(500 * (2 ** attempt))
          do_download_with_retry(url, max_retries, attempt + 1)
        else
          {:error, "Failed to download chart image after #{attempt + 1} attempts: HTTP #{status}"}
        end
      
      {:error, reason} ->
        Logger.error("Failed to download chart image: #{inspect(reason)}, attempt: #{attempt + 1}")
        
        if attempt < max_retries do
          # Sleep for 500ms, 1000ms, etc.
          :timer.sleep(500 * (2 ** attempt))
          do_download_with_retry(url, max_retries, attempt + 1)
        else
          {:error, "Failed to download chart image after #{attempt + 1} attempts: #{inspect(reason)}"}
        end
    end
  end
  
  @doc """
  Executes a chart generation attempt with multiple fallback options.
  Provides a multi-level fallback chain:
  1. Try primary Node.js generator
  2. Try QuickChart.io URL generation and download
  3. Fall back to static placeholder image
  
  ## Parameters
    - primary_fn: Function to generate chart using Node.js service
    - quickchart_fn: Function to generate chart URL using QuickChart.io
    - title: Chart title (for placeholder)
    - message: Message to display on placeholder chart
    - options: Additional options
  
  ## Returns
    - {:ok, binary} with the image data from any successful method
    - {:error, reason} if all methods fail
  """
  @spec with_comprehensive_fallback(
    (-> {:ok, binary()} | {:error, any()}),
    (-> {:ok, binary()} | {:error, any()}),
    binary(),
    binary(),
    Keyword.t()
  ) :: {:ok, binary()} | {:error, any()}
  def with_comprehensive_fallback(primary_fn, quickchart_fn, title, message, options \\ []) do
    enable_quickchart = Keyword.get(options, :enable_quickchart, true)
    enable_placeholder = Keyword.get(options, :enable_placeholder, true)
    
    # Try primary function (Node.js service)
    case primary_fn.() do
      {:ok, image_binary} ->
        {:ok, image_binary}
        
      {:error, primary_reason} ->
        Logger.warning("Primary chart generation failed: #{inspect(primary_reason)}.")
        
        if enable_quickchart do
          # Try QuickChart.io
          Logger.info("Falling back to QuickChart.io")
          
          case quickchart_fn.() do
            {:ok, url} ->
              # Download the chart image from the URL
              case download_with_retry(url, options) do
                {:ok, image_data} ->
                  {:ok, image_data}
                  
                {:error, download_reason} ->
                  Logger.error("Failed to download QuickChart.io image: #{inspect(download_reason)}")
                  
                  if enable_placeholder do
                    # Final fallback: Generate a placeholder image
                    Logger.info("Falling back to placeholder chart")
                    generate_placeholder_chart(title, message)
                  else
                    {:error, {:fallback_chain_failed, primary_reason, download_reason}}
                  end
              end
              
            {:error, quickchart_reason} ->
              Logger.error("QuickChart.io fallback failed: #{inspect(quickchart_reason)}")
              
              if enable_placeholder do
                # Final fallback: Generate a placeholder image
                Logger.info("Falling back to placeholder chart")
                generate_placeholder_chart(title, message)
              else
                {:error, {:fallback_chain_failed, primary_reason, quickchart_reason}}
              end
          end
        else
          if enable_placeholder do
            # Skip QuickChart, go straight to placeholder
            Logger.info("QuickChart disabled. Falling back to placeholder chart")
            generate_placeholder_chart(title, message)
          else
            {:error, {:primary_failed_no_fallbacks, primary_reason}}
          end
        end
    end
  end
  
  @doc """
  Generates a simple placeholder chart as a PNG image.
  This is a final fallback for when all other chart generation methods fail.
  
  ## Parameters
    - title: The title to display on the placeholder
    - message: The message to display (default: "Chart data unavailable")
    
  ## Returns
    - {:ok, binary} with the image data
  """
  @spec generate_placeholder_chart(binary(), binary()) :: {:ok, binary()}
  def generate_placeholder_chart(title, message \\ "Chart data unavailable") do
    # This is a very simple 1x1 transparent PNG that we'll use as a fallback
    # In a real implementation, you might want to generate a more useful placeholder
    transparent_png = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 
      1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 10, 73, 68, 65, 84, 120, 
      156, 99, 250, 207, 0, 0, 3, 1, 1, 0, 39, 68, 107, 74, 0, 0, 0, 0, 73, 69, 78, 68, 
      174, 66, 96, 130>>
      
    # Log that we're using the placeholder
    Logger.warning("Using placeholder chart for '#{title}': #{message}")
    
    # Return the placeholder image
    {:ok, transparent_png}
  end
end