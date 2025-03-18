import React, { useState, useEffect } from 'react';
import { FaCircleNotch, FaDiscord, FaExclamationTriangle, FaBug, FaSync } from 'react-icons/fa';

function ActivityChartCard({ title, description, chartType }) {
  const [chartUrl, setChartUrl] = useState(null);
  const [loading, setLoading] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(null);
  const [debugInfo, setDebugInfo] = useState(null);
  const [retryCount, setRetryCount] = useState(0);

  const generateChart = (forceRefresh = false) => {
    setLoading(true);
    setError(null);
    setDebugInfo(null);
    
    const timestamp = forceRefresh ? `?t=${Date.now()}` : '';
    console.log(`Fetching chart for ${chartType}${forceRefresh ? ' (force refresh)' : ''}...`);
    
    fetch(`/charts/activity/generate/${chartType}${timestamp}`)
      .then(response => {
        console.log(`Response status: ${response.status}`);
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        console.log(`Chart data received:`, data);
        if (data.status === 'ok' && data.chart_url) {
          // Add a timestamp to ensure the browser doesn't use cached image
          const urlWithCache = `${data.chart_url}${data.chart_url.includes('?') ? '&' : '?'}cache=${Date.now()}`;
          setChartUrl(urlWithCache);
          console.log(`Chart URL set to: ${urlWithCache}`);
          setRetryCount(0); // Reset retry count on success
        } else {
          setDebugInfo(JSON.stringify(data, null, 2));
          throw new Error(data.message || 'Failed to generate chart');
        }
      })
      .catch(error => {
        console.error(`Error generating ${chartType} chart:`, error);
        setError(error.message);
        
        // Auto-retry with exponential backoff if we haven't tried too many times
        if (retryCount < 2) {
          console.log(`Auto-retrying (attempt ${retryCount + 1})...`);
          const timeout = Math.pow(2, retryCount) * 1000;
          setTimeout(() => {
            setRetryCount(prev => prev + 1);
            generateChart(true);
          }, timeout);
        }
      })
      .finally(() => {
        setLoading(false);
      });
  };

  // Try to generate the chart when the component mounts
  useEffect(() => {
    generateChart();
  }, []);

  const sendToDiscord = () => {
    setSending(true);
    setSuccess(null);
    setError(null);
    
    fetch(`/charts/activity/send-to-discord/${chartType}?title=${encodeURIComponent(title)}&description=${encodeURIComponent(description)}`)
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        if (data.status === 'ok') {
          setSuccess('Chart sent to Discord successfully!');
          
          // Clear success message after 5 seconds
          setTimeout(() => {
            setSuccess(null);
          }, 5000);
        } else {
          throw new Error(data.message || 'Failed to send chart to Discord');
        }
      })
      .catch(error => {
        console.error(`Error sending ${chartType} chart to Discord:`, error);
        setError(error.message);
      })
      .finally(() => {
        setSending(false);
      });
  };

  const retryWithDirectUrl = () => {
    if (chartUrl) {
      // Extract the base URL without cache parameters
      const baseUrl = chartUrl.split('?')[0];
      const newUrl = `${baseUrl}?t=${Date.now()}`;
      
      setDebugInfo(`Trying to load: ${newUrl}`);
      
      // For debugging - create a new img element and try loading directly
      const img = new Image();
      img.onload = () => {
        setDebugInfo(`Image loaded successfully via direct URL: ${newUrl}`);
        setChartUrl(newUrl);
      };
      img.onerror = (e) => {
        setDebugInfo(`Failed to load image directly from URL: ${newUrl}. Error: ${e.message || 'Unknown error'}`);
      };
      img.src = newUrl;
    }
  };

  return (
    <div className="bg-white rounded-lg shadow-md overflow-hidden">
      <div className="p-4 border-b">
        <h2 className="text-xl font-semibold text-gray-800">{title}</h2>
        <p className="text-gray-600 text-sm mt-1">{description}</p>
      </div>
      
      <div className="p-4">
        {chartUrl ? (
          <div className="relative">
            <img 
              src={chartUrl}
              alt={`${title} Chart`} 
              className="w-full h-auto rounded"
              onError={(e) => {
                console.error(`Failed to load image from ${chartUrl}:`, e);
                if (retryCount < 3) {
                  // Try to load with a new URL on error
                  const newSrc = `${chartUrl.split('?')[0]}?t=${Date.now()}`;
                  console.log(`Retrying with new URL: ${newSrc}`);
                  e.target.src = newSrc;
                  setRetryCount(prev => prev + 1);
                } else {
                  // After several failures, show the error state
                  setChartUrl(null);
                  setError("Failed to load chart image. Try generating again.");
                }
              }}
            />
            <div className="absolute top-2 right-2 flex space-x-1">
              <button
                onClick={retryWithDirectUrl}
                className="p-1 bg-gray-800 text-white rounded-full opacity-50 hover:opacity-100"
                title="Debug chart loading"
              >
                <FaBug size={12} />
              </button>
              <button
                onClick={() => {
                  setRetryCount(0);
                  generateChart(true);
                }}
                className="p-1 bg-gray-800 text-white rounded-full opacity-50 hover:opacity-100"
                title="Force refresh chart"
              >
                <FaSync size={12} />
              </button>
            </div>
          </div>
        ) : (
          <div className="bg-gray-100 rounded-md h-64 flex items-center justify-center">
            {loading ? (
              <div className="text-center">
                <FaCircleNotch className="h-8 w-8 text-blue-500 animate-spin mx-auto mb-2" />
                <p className="text-sm text-gray-500">
                  {retryCount > 0 ? `Retrying (${retryCount})...` : 'Generating chart...'}
                </p>
              </div>
            ) : (
              <button 
                onClick={() => {
                  setRetryCount(0);
                  generateChart(true);
                }}
                className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors"
              >
                Generate Chart
              </button>
            )}
          </div>
        )}
      </div>
      
      {error && (
        <div className="px-4 py-2 bg-red-100 text-red-700 flex items-center">
          <FaExclamationTriangle className="mr-2 flex-shrink-0" />
          <span className="text-sm">{error}</span>
        </div>
      )}
      
      {success && (
        <div className="px-4 py-2 bg-green-100 text-green-700">
          {success}
        </div>
      )}
      
      {debugInfo && (
        <div className="px-4 py-2 bg-gray-100 text-gray-700 text-xs overflow-auto max-h-32">
          <pre>{debugInfo}</pre>
        </div>
      )}
      
      <div className="p-4 border-t bg-gray-50">
        <div className="flex justify-between">
          <button 
            onClick={() => {
              setRetryCount(0);
              generateChart(true);
            }}
            disabled={loading}
            className="px-3 py-1 bg-gray-200 text-gray-800 rounded hover:bg-gray-300 transition-colors disabled:opacity-50 flex items-center"
          >
            {loading ? <FaCircleNotch className="h-3 w-3 mr-1 animate-spin" /> : <FaSync className="mr-1" />}
            <span>Refresh</span>
          </button>
          
          <button 
            onClick={sendToDiscord}
            disabled={!chartUrl || sending}
            className="px-3 py-1 bg-indigo-600 text-white rounded hover:bg-indigo-700 transition-colors flex items-center space-x-1 disabled:opacity-50"
          >
            {sending ? <FaCircleNotch className="h-3 w-3 mr-1 animate-spin" /> : <FaDiscord className="mr-1" />}
            <span>Send to Discord</span>
          </button>
        </div>
      </div>
    </div>
  );
}

export default ActivityChartCard; 