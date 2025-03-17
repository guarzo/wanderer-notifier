import React, { useState, useEffect } from 'react';
import { FaSync, FaDiscord, FaChartBar, FaExclamationTriangle, FaCircleNotch, FaUsers } from 'react-icons/fa';
import ChartCard from './ChartCard';
import ActivityTable from './ActivityTable';

export default function ChartDashboard() {
  const [charts, setCharts] = useState({
    damage_final_blows: null,
    combined_losses: null,
    kill_activity: null
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [statusMessages, setStatusMessages] = useState({});
  const [activeTab, setActiveTab] = useState('charts');

  useEffect(() => {
    // Check if the API is available
    fetch('/charts/config')
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        if (!data.corp_tools_enabled) {
          throw new Error('Corp Tools functionality is not enabled');
        }
        setLoading(false);
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
      const chartPromises = chartTypes.map(type => 
        fetch(`/charts/generate?type=${type}`)
          .then(response => {
            if (!response.ok) {
              throw new Error(`Failed to generate ${type} chart: ${response.status}`);
            }
            return response.json();
          })
      );
      
      const results = await Promise.all(chartPromises);
      
      // Process results
      const newCharts = {};
      results.forEach((result, index) => {
        if (result.status === 'ok' && result.chart_url) {
          newCharts[chartTypes[index]] = result.chart_url;
        }
      });
      
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
      
      const response = await fetch(`/charts/send-to-discord?type=${chartType}&title=${encodeURIComponent(title)}&description=${encodeURIComponent(description)}`);
      
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
      case 'damage_final_blows':
        return 'Damage and Final Blows Analysis';
      case 'combined_losses':
        return 'Combined Losses Analysis';
      case 'kill_activity':
        return 'Kill Activity Over Time';
      default:
        return 'EVE Online Chart';
    }
  }

  function getChartDescription(chartType) {
    switch (chartType) {
      case 'damage_final_blows':
        return 'Top 20 characters by damage done and final blows';
      case 'combined_losses':
        return 'Top 10 characters by losses value and count';
      case 'kill_activity':
        return 'Kill activity trend over time';
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
            <ChartCard
              title="Damage & Final Blows"
              description="Top pilots by damage done and final blows"
              chartType="damage_final_blows"
            />
            <ChartCard
              title="Combined Losses"
              description="Top pilots by combined ship and pod losses"
              chartType="combined_losses"
            />
            <ChartCard
              title="Kill Activity"
              description="Kill activity over time"
              chartType="kill_activity"
            />
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
      <div className="mb-8 text-center">
        <h1 className="text-3xl font-bold text-gray-800 mb-2">Corp Tools Dashboard</h1>
        <p className="text-gray-600">
          View and manage EVE Online corporation analytics and tools
        </p>
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