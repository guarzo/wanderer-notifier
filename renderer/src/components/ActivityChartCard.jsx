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
    
    fetch(`/api/charts/activity/generate/${chartType}${timestamp}`)
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
  }, [chartType]);

  const sendToDiscord = () => {
    setSending(true);
    setSuccess(null);
    setError(null);
    
    console.log('Sending chart to Discord...');
    
    fetch(`/api/charts/activity/send-to-discord/${chartType}`)
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        if (data.status === 'ok') {
          setSuccess('Chart sent to Discord!');
          setTimeout(() => setSuccess(null), 5000);
        } else {
          throw new Error(data.message || 'Failed to send chart to Discord');
        }
      })
      .catch(error => {
        console.error('Error sending chart to Discord:', error);
        setError(`Failed to send chart: ${error.message}`);
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
    <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
      <div className="flex justify-between items-start mb-4">
        <div>
          <h3 className="text-lg font-semibold text-gray-800">{title}</h3>
          {description && (
            <p className="text-sm text-gray-600 mt-1">{description}</p>
          )}
        </div>
        <div className="flex space-x-2">
          <button
            className="p-2 text-gray-600 hover:bg-gray-100 rounded-md transition-colors"
            onClick={() => generateChart(true)}
            disabled={loading}
          >
            <FaSync className={loading ? 'animate-spin' : ''} />
          </button>
          <button
            className="p-2 text-gray-600 hover:bg-gray-100 rounded-md transition-colors"
            onClick={sendToDiscord}
            disabled={sending || loading || !chartUrl}
          >
            <FaDiscord className={sending ? 'animate-pulse' : ''} />
          </button>
        </div>
      </div>

      {/* Status Messages */}
      {error && (
        <div className="mb-4 p-3 bg-red-50 text-red-700 rounded-md flex items-center">
          <FaExclamationTriangle className="mr-2" />
          <span>{error}</span>
        </div>
      )}
      
      {success && (
        <div className="mb-4 p-3 bg-green-50 text-green-700 rounded-md">
          {success}
        </div>
      )}

      {/* Chart Display */}
      <div className="relative bg-gray-100 rounded-lg overflow-hidden">
        {loading ? (
          <div className="flex items-center justify-center h-64">
            <FaCircleNotch className="h-8 w-8 text-gray-400 animate-spin" />
          </div>
        ) : chartUrl ? (
          <img
            src={chartUrl}
            alt={title}
            className="w-full h-auto"
            onError={(e) => {
              console.error('Error loading chart image');
              setError('Failed to load chart image');
              e.target.style.display = 'none';
            }}
          />
        ) : (
          <div className="flex items-center justify-center h-64 text-gray-500">
            No chart available
          </div>
        )}
      </div>

      {/* Debug Information */}
      {debugInfo && (
        <div className="mt-4">
          <button
            className="flex items-center text-sm text-gray-600 hover:text-gray-800"
            onClick={() => setDebugInfo(null)}
          >
            <FaBug className="mr-1" />
            <span>Debug Info</span>
          </button>
          <pre className="mt-2 p-2 bg-gray-50 rounded text-xs overflow-x-auto">
            {debugInfo}
          </pre>
        </div>
      )}
    </div>
  );
}

export default ActivityChartCard;
