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

  // Cleanup function for blob URLs
  const cleanupBlobUrl = (url) => {
    if (url && url.startsWith('blob:')) {
      URL.revokeObjectURL(url);
    }
  };

  const generateChart = (forceRefresh = false) => {
    setLoading(true);
    setError(null);
    setDebugInfo(null);
    
    // Cleanup previous blob URL if it exists
    cleanupBlobUrl(chartUrl);
    
    // Only add timestamp when explicitly forcing a refresh
    const timestamp = forceRefresh ? `?t=${Date.now()}` : '';
    console.log(`Fetching chart for ${chartType}${forceRefresh ? ' (force refresh)' : ''}...`);
    
    fetch(`/api/charts/activity/generate/${chartType}${timestamp}`)
      .then(response => {
        console.log(`Response status: ${response.status}`);
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.blob();
      })
      .then(blob => {
        const imageUrl = URL.createObjectURL(blob);
        setChartUrl(imageUrl);
        console.log('Chart image blob URL created');
        setRetryCount(0);
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
    // Only generate chart on initial load
    generateChart(false);
    // Cleanup blob URL when component unmounts
    return () => cleanupBlobUrl(chartUrl);
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
    setRetryCount(0);
    generateChart(true);
  };

  return (
    <div className="bg-white rounded-lg shadow-md overflow-hidden">
      <div className="p-4 border-b">
        <h2 className="text-xl font-semibold text-gray-800">{title}</h2>
        <p className="text-gray-600 text-sm mt-1">{description}</p>
      </div>

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

      {/* Error Message */}
      {error && (
        <div className="p-4 bg-red-50 text-red-700 flex items-center">
          <FaExclamationTriangle className="mr-2" />
          <span>{error}</span>
        </div>
      )}

      {/* Success Message */}
      {success && (
        <div className="p-4 bg-green-50 text-green-700">
          {success}
        </div>
      )}

      {/* Action Buttons */}
      <div className="p-4 border-t flex justify-end space-x-2">
        <button
          type="button"
          onClick={retryWithDirectUrl}
          title="Refresh chart"
          className="p-2 text-gray-600 hover:text-gray-800 rounded"
        >
          <FaSync size={16} />
        </button>
        <button
          type="button"
          onClick={sendToDiscord}
          disabled={sending || !chartUrl}
          className="flex items-center px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
        >
          {sending ? (
            <FaCircleNotch className="animate-spin mr-2" />
          ) : (
            <FaDiscord className="mr-2" />
          )}
          Send to Discord
        </button>
      </div>
    </div>
  );
}

export default ActivityChartCard;
