import React, { useState, useEffect } from 'react';
import { FaCircleNotch, FaDiscord, FaExclamationTriangle } from 'react-icons/fa';

function ChartCard({ title, description, chartType, chartUrl: propChartUrl }) {
  const [chartUrl, setChartUrl] = useState(propChartUrl || null);
  
  // Update internal state when prop changes
  useEffect(() => {
    if (propChartUrl) {
      setChartUrl(propChartUrl);
    }
  }, [propChartUrl]);
  const [loading, setLoading] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(null);

  const generateChart = () => {
    setLoading(true);
    setError(null);
    
    // Map internal chart type to API chart type
    const typeMapping = {
      'kills_by_ship_type': 'damage_final_blows',
      'kills_by_month': 'combined_losses',
      'total_kills_value': 'kill_activity'
    };
    
    const apiChartType = typeMapping[chartType] || chartType;
    console.log(`Generating ${apiChartType} chart...`);
    
    // Use the correct charts/generate endpoint with the type parameter
    fetch(`/charts/generate?type=${apiChartType}`)
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        
        // Check if the response is a direct image
        const contentType = response.headers.get('content-type');
        if (contentType && contentType.includes('image/')) {
          // For image responses, create a blob URL
          return response.blob().then(blob => {
            const imageUrl = URL.createObjectURL(blob);
            return { directImage: true, imageUrl };
          });
        } else {
          // For JSON responses, parse as usual
          return response.json();
        }
      })
      .then(result => {
        if (result.directImage) {
          // Direct image response
          setChartUrl(result.imageUrl);
        } else if (result.status === 'ok' && result.chart_url) {
          // JSON response with chart URL
          setChartUrl(result.chart_url);
        } else {
          throw new Error(result.message || 'Failed to generate chart');
        }
      })
      .catch(error => {
        console.error(`Error generating ${chartType} chart:`, error);
        setError(error.message);
      })
      .finally(() => {
        setLoading(false);
      });
  };

  const sendToDiscord = () => {
    setSending(true);
    setSuccess(null);
    setError(null);
    
    // Map internal chart type to API chart type
    const typeMapping = {
      'kills_by_ship_type': 'damage_final_blows',
      'kills_by_month': 'combined_losses',
      'total_kills_value': 'kill_activity'
    };
    
    const apiChartType = typeMapping[chartType] || chartType;
    console.log(`Sending ${apiChartType} chart to Discord...`);
    
    // Use the correct endpoint for sending to discord
    fetch(`/charts/send-to-discord?type=${apiChartType}&title=${encodeURIComponent(title)}&description=${encodeURIComponent(description)}`)
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        if (data.status === 'ok') {
          setSuccess('Chart sent to Discord successfully!');
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

  return (
    <div className="bg-white rounded-lg shadow-md overflow-hidden">
      <div className="p-4 border-b">
        <h2 className="text-xl font-semibold text-gray-800">{title}</h2>
        <p className="text-gray-600 text-sm mt-1">{description}</p>
      </div>
      
      <div className="p-4">
        {chartUrl ? (
          <img 
            src={chartUrl} 
            alt={`${title} Chart`} 
            className="w-full h-auto rounded"
          />
        ) : (
          <div className="bg-gray-100 rounded-md h-64 flex items-center justify-center">
            {loading ? (
              <FaCircleNotch className="h-8 w-8 text-blue-500 animate-spin" />
            ) : (
              <button 
                onClick={generateChart}
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
          <FaExclamationTriangle className="mr-2" />
          <span>{error}</span>
        </div>
      )}
      
      {success && (
        <div className="px-4 py-2 bg-green-100 text-green-700">
          {success}
        </div>
      )}
      
      <div className="p-4 border-t bg-gray-50">
        <div className="flex justify-between">
          <button 
            onClick={generateChart}
            disabled={loading}
            className="px-3 py-1 bg-gray-200 text-gray-800 rounded hover:bg-gray-300 transition-colors disabled:opacity-50"
          >
            Refresh
          </button>
          
          <button 
            onClick={sendToDiscord}
            disabled={!chartUrl || sending}
            className="px-3 py-1 bg-indigo-600 text-white rounded hover:bg-indigo-700 transition-colors flex items-center space-x-1 disabled:opacity-50"
          >
            <FaDiscord />
            <span>Send to Discord</span>
          </button>
        </div>
      </div>
    </div>
  );
}

export default ChartCard; 