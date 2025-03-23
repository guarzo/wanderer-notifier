import React, { useState, useEffect } from 'react';
import { FaCircleNotch, FaDiscord, FaExclamationTriangle, FaBug, FaSync, FaPlus } from 'react-icons/fa';

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
        console.log('Chart data received:', data);
        if (data.status === 'ok' && data.chart_url) {
          const urlWithCache = `${data.chart_url}${data.chart_url.includes('?') ? '&' : '?'}cache=${Date.now()}`;
          setChartUrl(urlWithCache);
          console.log('Chart URL set to:', urlWithCache);
          setRetryCount(0);
        } else {
          setDebugInfo(JSON.stringify(data, null, 2));
          throw new Error(data.message || 'Failed to generate chart');
        }
      })
      .catch(error => {
        console.error(`Error generating ${chartType} chart:`, error);
        setError(error.message);
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
          setTimeout(() => setSuccess(null), 5000);
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
      const baseUrl = chartUrl.split('?')[0];
      const newUrl = `${baseUrl}?t=${Date.now()}`;
      setDebugInfo(`Trying to load: ${newUrl}`);
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
                  const newSrc = `${chartUrl.split('?')[0]}?t=${Date.now()}`;
                  console.log(`Retrying with new URL: ${newSrc}`);
                  e.target.src = newSrc;
                  setRetryCount(prev => prev + 1);
                } else {
                  setChartUrl(null);
                  setError("Failed to load chart image. Try generating again.");
                }
              }}
            />
            <div className="absolute top-2 right-2 flex space-x-1">
              <button
                onClick={retryWithDirectUrl}
                title="Debug chart loading"
                className="p-2 bg-gray-800 text-white rounded-full opacity-75 hover:opacity-100 transition"
              >
                <FaBug size={14} />
              </button>
              <button
                onClick={() => {
                  setRetryCount(0);
                  generateChart(true);
                }}
                title="Force refresh chart"
                className="p-2 bg-gray-800 text-white rounded-full opacity-75 hover:opacity-100 transition"
              >
                <FaSync size={14} />
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
                title="Generate Chart"
                className="p-3 bg-blue-600 text-white rounded-full hover:bg-blue-700 transition"
              >
                <FaPlus size={16} />
              </button>
            )}
          </div>
        )}
      </div>
      
      {error && (
        <div className="px-4 py-2 bg-red-100 text-red-700 flex items-center">
          <FaExclamationTriangle className="mr-2" />
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
        <div className="flex justify-end space-x-2">
          <button 
            onClick={() => {
              setRetryCount(0);
              generateChart(true);
            }}
            disabled={loading}
            title="Refresh"
            className="p-2 bg-gray-200 text-gray-800 rounded-full hover:bg-gray-300 transition disabled:opacity-50"
          >
            {loading ? <FaCircleNotch className="h-4 w-4 animate-spin" /> : <FaSync />}
          </button>
          <button 
            onClick={sendToDiscord}
            disabled={!chartUrl || sending}
            title="Send to Discord"
            className="p-2 bg-indigo-600 text-white rounded-full hover:bg-indigo-700 transition disabled:opacity-50"
          >
            {sending ? <FaCircleNotch className="h-4 w-4 animate-spin" /> : <FaDiscord />}
          </button>
        </div>
      </div>
    </div>
  );
}

export default ActivityChartCard;
