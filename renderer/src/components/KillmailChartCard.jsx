import React, { useState, useEffect } from 'react';
import { FaSync, FaDiscord, FaChartBar, FaExclamationTriangle, FaCircleNotch, FaBug, FaSearch, FaUsers, FaHammer } from 'react-icons/fa';

function KillmailChartCard({ title, description, chartType }) {
  const [chartUrl, setChartUrl] = useState(null);
  const [loading, setLoading] = useState(false);
  const [sending, setSending] = useState(false);
  const [aggregating, setAggregating] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(null);
  const [debugInfo, setDebugInfo] = useState(null);
  const [debugData, setDebugData] = useState(null);
  const [retryCount, setRetryCount] = useState(0);
  const [forceSyncing, setForceSyncing] = useState(false);

  const addTimestampToUrl = (url) => {
    const separator = url.includes('?') ? '&' : '?';
    return `${url}${separator}cache=${Date.now()}`;
  };

  const generateChart = (forceRefresh = false) => {
    setLoading(true);
    setError(null);
    setDebugInfo(null);
    
    const timestamp = forceRefresh ? `?t=${Date.now()}` : '';
    console.log(`Fetching chart for ${chartType}${forceRefresh ? ' (force refresh)' : ''}...`);
    
    fetch(`/charts/killmail/generate/${chartType}${timestamp}`)
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
          const urlWithCache = addTimestampToUrl(data.chart_url);
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
    
    fetch(`/charts/killmail/send-to-discord/${chartType}?title=${encodeURIComponent(title)}&description=${encodeURIComponent(description)}`)
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

  const triggerAggregation = () => {
    setAggregating(true);
    setSuccess(null);
    setError(null);
    setDebugInfo(null);
    
    console.log('Triggering killmail data aggregation...');
    
    fetch(`/charts/killmail/aggregate?type=weekly`)
      .then(response => {
        console.log(`Aggregation response status: ${response.status}`);
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        console.log('Aggregation result:', data);
        if (data.status === 'ok') {
          setSuccess('Aggregation completed! Refreshing chart...');
          setTimeout(() => {
            generateChart(true);
          }, 1000);
          setTimeout(() => {
            setSuccess(null);
          }, 5000);
        } else {
          setDebugInfo(JSON.stringify(data, null, 2));
          throw new Error(data.message || 'Failed to aggregate data');
        }
      })
      .catch(error => {
        console.error('Error during data aggregation:', error);
        setError(`Aggregation error: ${error.message}`);
      })
      .finally(() => {
        setAggregating(false);
      });
  };
  
  const fetchDebugData = () => {
    setDebugData(null);
    setDebugInfo("Loading debug information...");
    
    fetch(`/charts/killmail/debug`)
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        console.log('Debug data:', data);
        setDebugData(data);
        setDebugInfo(JSON.stringify(data, null, 2));
      })
      .catch(error => {
        console.error('Error fetching debug data:', error);
        setDebugInfo(`Error fetching debug data: ${error.message}`);
      });
  };

  const retryWithDirectUrl = () => {
    if (chartUrl) {
      const baseUrl = chartUrl.split('?')[0];
      const newUrl = addTimestampToUrl(baseUrl);
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

  const forceSync = () => {
    if (!window.confirm('This will DELETE all characters from the database and resync from cache. Continue?')) {
      return;
    }
    
    setForceSyncing(true);
    setSuccess(null);
    setError(null);
    setDebugInfo(null);
    
    console.log('Force syncing characters from cache to database...');
    
    fetch(`/charts/killmail/force-sync-characters`)
      .then(response => {
        console.log(`Force sync response status: ${response.status}`);
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        console.log('Force sync result:', data);
        if (data.status === 'ok') {
          setSuccess(`Force sync completed successfully! Database now contains ${data.details.db_count || 0} characters.`);
          
          setTimeout(() => {
            setSuccess(null);
          }, 5000);
        } else {
          setDebugInfo(JSON.stringify(data, null, 2));
          throw new Error(data.message || 'Failed to force sync characters');
        }
      })
      .catch(error => {
        console.error('Error during force sync:', error);
        setError(`Force sync error: ${error.message}`);
      })
      .finally(() => {
        setForceSyncing(false);
      });
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
                  const newSrc = addTimestampToUrl(chartUrl.split('?')[0]);
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
                type="button"
                onClick={retryWithDirectUrl}
                title="Debug chart loading"
                className="p-2 bg-gray-800 text-white rounded-full opacity-75 hover:opacity-100 transition"
              >
                <FaBug size={14} />
              </button>
              <button
                type="button"
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
                type="button"
                onClick={() => {
                  setRetryCount(0);
                  generateChart(true);
                }}
                title="Generate Chart"
                className="p-3 bg-blue-600 text-white rounded-full hover:bg-blue-700 transition"
              >
                <FaSync size={16} />
              </button>
            )}
          </div>
        )}
      </div>
      
      {debugData && (
        <div className="px-4 py-3 bg-gray-50 border-y">
          <h4 className="font-medium text-gray-800 mb-2">Database Status</h4>
          <div className="grid grid-cols-3 gap-2 text-sm">
            <div className="bg-blue-50 p-2 rounded">
              <span className="font-medium">Killmails:</span> {debugData.counts.killmails}
            </div>
            <div className="bg-green-50 p-2 rounded">
              <span className="font-medium">Statistics:</span> {debugData.counts.statistics}
            </div>
            <div className="bg-purple-50 p-2 rounded">
              <span className="font-medium">Periods:</span> {Object.keys(debugData.counts.by_period || {}).join(', ')}
            </div>
          </div>
        </div>
      )}
      
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
        <div className="flex flex-wrap gap-2">
          <button 
            type="button"
            onClick={() => {
              setRetryCount(0);
              generateChart(true);
            }}
            disabled={loading}
            className="px-3 py-1 bg-gray-200 text-gray-800 rounded hover:bg-gray-300 transition-colors disabled:opacity-50 flex items-center"
          >
            {loading ? <FaCircleNotch className="h-3 w-3 mr-1 animate-spin" /> : <FaSync className="mr-1" />}
            <span>Refresh Chart</span>
          </button>
          
          <button 
            type="button"
            onClick={forceSync}
            disabled={forceSyncing}
            className="px-3 py-1 bg-red-500 text-white rounded hover:bg-red-600 transition-colors disabled:opacity-50 flex items-center"
          >
            {forceSyncing ? <FaCircleNotch className="h-3 w-3 mr-1 animate-spin" /> : <FaHammer className="mr-1" />}
            <span>Force Sync Characters</span>
          </button>
          
          <button 
            type="button"
            onClick={triggerAggregation}
            disabled={aggregating}
            className="px-3 py-1 bg-orange-500 text-white rounded hover:bg-orange-600 transition-colors disabled:opacity-50 flex items-center"
          >
            {aggregating ? <FaCircleNotch className="h-3 w-3 mr-1 animate-spin" /> : <FaChartBar className="mr-1" />}
            <span>Run Aggregation</span>
          </button>
          
          <button 
            type="button"
            onClick={fetchDebugData}
            className="px-3 py-1 bg-purple-500 text-white rounded hover:bg-purple-600 transition-colors flex items-center"
          >
            <FaSearch className="mr-1" />
            <span>View Database Status</span>
          </button>
          
          <button 
            type="button"
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

export default KillmailChartCard;
