import React, { useState, useEffect } from 'react';
import { FaSync, FaDiscord, FaChartBar, FaExclamationTriangle, FaCircleNotch, FaUsers } from 'react-icons/fa';
import ChartCard from './ChartCard';
import ActivityTable from './ActivityTable';

export default function ChartDashboard() {
  const [charts, setCharts] = useState({
    kills_by_ship_type: null,
    kills_by_month: null,
    total_kills_value: null
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [statusMessages, setStatusMessages] = useState({});
  const [activeTab, setActiveTab] = useState('charts');
  const [status, setStatus] = useState(null);

  useEffect(() => {
    // Initialize the dashboard and load charts when component mounts
    console.log("Fetching status from /api/status");
    fetch('/api/status')
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        if (!data.features.enabled.web_dashboard_full) {
          throw new Error('Full dashboard functionality is not available with your license');
        }
        console.log("API status check successful, loading charts...");
        // Save the status data for feature checking
        setStatus(data);
        // Load charts once we verify API is available
        loadCharts();
      })
      .catch(error => {
        console.error('Error connecting to API:', error);
        setError(error.message);
        setLoading(false);
      });
  }, []);

  async function loadCharts() {
    setLoading(true);
    setError(null);
    
    try {
      // Generate each chart type
      const chartTypes = ['damage_final_blows', 'combined_losses', 'kill_activity'];
      console.log("Loading charts:", chartTypes);
      
      const chartPromises = chartTypes.map(type => {
        console.log(`Fetching chart for ${type}...`);
        // Use the /charts/generate endpoint with the type parameter
        return fetch(`/charts/generate?type=${type}`)
          .then(response => {
            if (!response.ok) {
              throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
          });
      });
      
      const results = await Promise.all(chartPromises);
      
      // Process results
      const newCharts = {};
      // Map chart types to our internal naming convention
      const mappedTypes = {
        'damage_final_blows': 'kills_by_ship_type', 
        'combined_losses': 'kills_by_month',
        'kill_activity': 'total_kills_value'
      };
      
      results.forEach((result, index) => {
        if (result.status === 'ok' && result.chart_url) {
          const internalType = mappedTypes[chartTypes[index]];
          newCharts[internalType] = result.chart_url;
        }
      });
      
      console.log("Charts loaded successfully:", Object.keys(newCharts));
      setCharts(newCharts);
    } catch (err) {
      console.error('Error loading charts:', err);
      setError(`Failed to load charts: ${err.message}`);
    } finally {
      setLoading(false);
    }
  }

  async function sendToDiscord(chartType) {
    setStatusMessages(prev => ({
      ...prev,
      [chartType]: { loading: true }
    }));
    
    try {
      const title = getChartTitle(chartType);
      const description = getChartDescription(chartType);
      
      // Map internal chart type to API chart type
      const typeMapping = {
        'kills_by_ship_type': 'damage_final_blows',
        'kills_by_month': 'combined_losses',
        'total_kills_value': 'kill_activity'
      };
      
      const apiChartType = typeMapping[chartType] || chartType;
      console.log(`Sending ${apiChartType} chart to Discord...`);
      
      // Use correct endpoint
      const response = await fetch(`/charts/send-to-discord?type=${apiChartType}&title=${encodeURIComponent(title)}&description=${encodeURIComponent(description)}`);
      
      if (!response.ok) {
        throw new Error(`Failed to send chart to Discord: ${response.status}`);
      }
      
      const data = await response.json();
      
      if (data.status === 'ok') {
        setStatusMessages(prev => ({
          ...prev,
          [chartType]: { success: 'Chart sent to Discord!' }
        }));
      } else {
        throw new Error(data.message || 'Unknown error');
      }
    } catch (err) {
      console.error(`Error sending ${chartType} chart to Discord:`, err);
      setStatusMessages(prev => ({
        ...prev,
        [chartType]: { error: `Failed to send chart: ${err.message}` }
      }));
    }
  }

  function getChartTitle(chartType) {
    switch (chartType) {
      case 'kills_by_ship_type':
        return 'Ship Type Distribution';
      case 'kills_by_month':
        return 'Monthly Kill Activity';
      case 'total_kills_value':
        return 'Kills and Value Analysis';
      default:
        return 'EVE Online Chart';
    }
  }

  function getChartDescription(chartType) {
    switch (chartType) {
      case 'kills_by_ship_type':
        return 'Top ship types used in kills over the last 12 months';
      case 'kills_by_month':
        return 'Kill activity trend over the last 12 months';
      case 'total_kills_value':
        return 'Kill count and estimated value over the last 12 months';
      default:
        return 'Generated chart from EVE Corp Tools data';
    }
  }

  function debugTpsStructure() {
    window.open('/charts/debug-tps-structure', '_blank');
  }

  const renderTabContent = () => {
    switch (activeTab) {
      case 'charts':
        return (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {/* These cards should only be shown if the appropriate features are enabled */}
            {status?.features?.enabled?.tps_charts && (
              <ChartCard
                title="Ship Type Distribution"
                description="Top ship types used in kills over the last 12 months"
                chartType="kills_by_ship_type"
                chartUrl={charts.kills_by_ship_type}
              />
            )}
            
            {status?.features?.enabled?.tps_charts && (
              <ChartCard
                title="Monthly Kill Activity"
                description="Kill activity trend over the last 12 months"
                chartType="kills_by_month"
                chartUrl={charts.kills_by_month}
              />
            )}
            
            {status?.features?.enabled?.activity_charts && (
              <ChartCard
                title="Kills & Value Analysis"
                description="Kill count and estimated value over time"
                chartType="total_kills_value"
                chartUrl={charts.total_kills_value}
              />
            )}
            
            {/* Show a message when no chart features are enabled */}
            {!status?.features?.enabled?.tps_charts && !status?.features?.enabled?.activity_charts && (
              <div className="col-span-full p-6 bg-gray-50 rounded-lg border border-gray-200">
                <div className="text-center">
                  <h3 className="text-lg font-medium text-gray-900">Chart features are not enabled</h3>
                  <p className="mt-2 text-sm text-gray-600">
                    To enable charts, set ENABLE_TPS_CHARTS=true or ENABLE_ACTIVITY_CHARTS=true in your environment variables.
                  </p>
                </div>
              </div>
            )}
          </div>
        );
      case 'activity':
        return <ActivityTable />;
      default:
        return <div>Select a tab to view content</div>;
    }
  };

  if (loading && !Object.values(charts).some(chart => chart)) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <FaCircleNotch className="h-10 w-10 text-indigo-600 animate-spin" />
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="mb-8 flex flex-col items-center justify-center">
        <h1 className="text-3xl font-bold text-gray-800 mb-2">Corp Tools Dashboard</h1>
        <p className="text-gray-600 mb-4">
          View and manage EVE Online corporation analytics and tools
        </p>
        
        <div className="flex space-x-2">
          <button 
            onClick={loadCharts}
            disabled={loading}
            className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors flex items-center space-x-1 disabled:opacity-50"
          >
            {loading ? (
              <FaCircleNotch className="animate-spin mr-1" />
            ) : (
              <FaSync className="mr-1" />
            )}
            <span>Refresh Charts</span>
          </button>
          
          <button 
            onClick={() => window.open('/api/corp-tools/charts/all', '_blank')}
            className="px-4 py-2 bg-gray-600 text-white rounded-md hover:bg-gray-700 transition-colors"
          >
            <span>View All Charts</span>
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="mb-6 border-b border-gray-200">
        <ul className="flex flex-wrap -mb-px">
          <li className="mr-2">
            <button
              className={`inline-flex items-center py-4 px-4 text-sm font-medium text-center border-b-2 ${
                activeTab === 'charts'
                  ? 'text-blue-600 border-blue-600'
                  : 'text-gray-500 border-transparent hover:text-gray-600 hover:border-gray-300'
              }`}
              onClick={() => setActiveTab('charts')}
            >
              <FaChartBar className="mr-2" />
              Charts
            </button>
          </li>
          <li className="mr-2">
            <button
              className={`inline-flex items-center py-4 px-4 text-sm font-medium text-center border-b-2 ${
                activeTab === 'activity'
                  ? 'text-blue-600 border-blue-600'
                  : 'text-gray-500 border-transparent hover:text-gray-600 hover:border-gray-300'
              }`}
              onClick={() => setActiveTab('activity')}
            >
              <FaUsers className="mr-2" />
              Activity
            </button>
          </li>
        </ul>
      </div>

      {loading ? (
        <div className="flex justify-center items-center h-64">
          <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-blue-500"></div>
        </div>
      ) : error ? (
        <div className="bg-red-100 border-l-4 border-red-500 text-red-700 p-4 mb-6 rounded">
          <div className="flex items-center">
            <FaExclamationTriangle className="mr-2" />
            <p>Error loading data: {error}</p>
          </div>
          <p className="mt-2 text-sm">Please check your connection and try again.</p>
        </div>
      ) : (
        renderTabContent()
      )}
    </div>
  );
} 