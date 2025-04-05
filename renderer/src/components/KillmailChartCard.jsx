import React, { useState, useEffect } from 'react';
import { FaSync, FaDiscord, FaExclamationTriangle, FaCircleNotch, FaCheckCircle } from 'react-icons/fa';

function KillmailChartCard({ title, description, chartType, loadChartImage }) {
  const [chartUrl, setChartUrl] = useState(null);
  const [loading, setLoading] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(null);

  const generateChart = async (forceRefresh = false) => {
    setLoading(true);
    setError(null);
    
    // Add a timestamp for force refresh
    const timestamp = forceRefresh ? `?t=${Date.now()}` : '';
    console.log(`Fetching chart for ${chartType}${forceRefresh ? ' (force refresh)' : ''}...`);
    
    try {
      // Use the original endpoint (UI-specific one was removed)
      const response = await fetch(`/api/charts/killmail/generate/${chartType}${timestamp}`);
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }

      // Handle binary image data
      const blob = await response.blob();
      const imageUrl = URL.createObjectURL(blob);
      setChartUrl(imageUrl);
    } catch (error) {
      console.error(`Error generating ${chartType} chart:`, error);
      setError(error.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    generateChart();
    return () => {
      // Cleanup object URLs when component unmounts
      if (chartUrl) {
        URL.revokeObjectURL(chartUrl);
      }
    };
  }, [chartType]);

  const sendToDiscord = async () => {
    setSending(true);
    setSuccess(null);
    setError(null);
    
    console.log('Sending chart to Discord...');
    
    try {
      // Note: We're still using the original endpoint for Discord sending
      // This ensures we use the default Discord-friendly background
      const response = await fetch(`/api/charts/killmail/send-to-discord/${chartType}`);
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      if (data.status === 'ok') {
        setSuccess('Chart sent to Discord!');
        setTimeout(() => setSuccess(null), 5000);
      } else {
        throw new Error(data.message || 'Failed to send chart to Discord');
      }
    } catch (error) {
      console.error('Error sending chart to Discord:', error);
      setError(`Failed to send chart: ${error.message}`);
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="bg-white rounded-lg shadow-md overflow-hidden">
      <div className="p-4 border-b">
        <h2 className="text-xl font-semibold text-gray-800">{title}</h2>
        {chartType !== 'weekly_kills' && (
          <p className="text-gray-600 text-sm mt-1">{description}</p>
        )}
      </div>
      
      <div className="relative bg-black rounded-lg overflow-hidden">
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

      {error && (
        <div className="p-4 bg-red-50">
          <div className="flex items-center text-sm text-red-700">
            <FaExclamationTriangle className="mr-2" />
            {error}
          </div>
        </div>
      )}

      {success && (
        <div className="p-4 bg-green-50">
          <div className="flex items-center text-sm text-green-700">
            <FaCheckCircle className="mr-2" />
            {success}
          </div>
        </div>
      )}

      <div className="p-4 flex justify-end space-x-2">
        <button
          type="button"
          onClick={() => generateChart(true)}
          disabled={loading}
          title="Refresh Chart"
          className="p-3 bg-gray-600 text-white rounded-lg hover:bg-gray-700 transition flex items-center justify-center disabled:opacity-50"
        >
          {loading ? <FaCircleNotch className="animate-spin" /> : <FaSync className="mr-2" />}
          <span>Refresh</span>
        </button>

        <button
          type="button"
          onClick={sendToDiscord}
          disabled={sending || loading}
          title="Send to Discord"
          className="p-3 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition flex items-center justify-center disabled:opacity-50"
        >
          {sending ? <FaCircleNotch className="animate-spin" /> : <FaDiscord className="mr-2" />}
          <span>Send to Discord</span>
        </button>
      </div>
    </div>
  );
}

export default KillmailChartCard;
