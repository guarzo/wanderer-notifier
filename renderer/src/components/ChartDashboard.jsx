import React, { useState, useEffect } from 'react';
import { FaSync, FaDiscord, FaChartBar, FaExclamationTriangle, FaCircleNotch } from 'react-icons/fa';

export default function ChartDashboard() {
  const [charts, setCharts] = useState({
    damage_final_blows: null,
    combined_losses: null,
    kill_activity: null
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [statusMessages, setStatusMessages] = useState({});

  useEffect(() => {
    loadCharts();
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

  if (loading && !Object.values(charts).some(chart => chart)) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <FaCircleNotch className="h-10 w-10 text-indigo-600 animate-spin" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-900 text-white">
      <div className="max-w-7xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
        {/* Header */}
        <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between mb-8">
          <h1 className="text-2xl font-bold text-indigo-400 flex items-center space-x-2 mb-4 sm:mb-0">
            <FaChartBar />
            <span>EVE Corp Tools Charts</span>
          </h1>
          <div className="flex space-x-3">
            <button 
              onClick={loadCharts}
              className="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition-colors flex items-center space-x-2"
            >
              <FaSync className={loading ? "animate-spin" : ""} />
              <span>Refresh Charts</span>
            </button>
            <button 
              onClick={debugTpsStructure}
              className="px-4 py-2 bg-gray-700 text-white rounded-md hover:bg-gray-600 transition-colors"
            >
              Debug TPS Structure
            </button>
          </div>
        </div>

        {/* Error Message */}
        {error && (
          <div className="bg-red-900 border border-red-700 text-white p-4 rounded-md mb-6 flex items-center space-x-2">
            <FaExclamationTriangle className="text-red-400" />
            <span>{error}</span>
          </div>
        )}

        {/* Charts Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Damage and Final Blows Chart */}
          <div className="bg-gray-800 rounded-lg overflow-hidden shadow-lg">
            <div className="p-4 border-b border-gray-700">
              <h2 className="text-xl font-semibold text-indigo-300">Damage and Final Blows</h2>
              <p className="text-gray-400 text-sm mt-1">Top 20 characters by damage done and final blows</p>
            </div>
            <div className="p-4">
              {charts.damage_final_blows ? (
                <img 
                  src={charts.damage_final_blows} 
                  alt="Damage and Final Blows Chart" 
                  className="w-full h-auto rounded"
                />
              ) : (
                <div className="bg-gray-700 rounded-md h-64 flex items-center justify-center">
                  {loading ? (
                    <FaCircleNotch className="h-8 w-8 text-indigo-400 animate-spin" />
                  ) : (
                    <span className="text-gray-400">No chart available</span>
                  )}
                </div>
              )}
            </div>
            <div className="p-4 border-t border-gray-700">
              <button 
                onClick={() => sendToDiscord('damage_final_blows')}
                disabled={!charts.damage_final_blows || statusMessages.damage_final_blows?.loading}
                className="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition-colors flex items-center space-x-2 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <FaDiscord />
                <span>Send to Discord</span>
              </button>
              
              {statusMessages.damage_final_blows?.success && (
                <div className="mt-2 text-green-400 text-sm">
                  {statusMessages.damage_final_blows.success}
                </div>
              )}
              
              {statusMessages.damage_final_blows?.error && (
                <div className="mt-2 text-red-400 text-sm">
                  {statusMessages.damage_final_blows.error}
                </div>
              )}
            </div>
          </div>

          {/* Combined Losses Chart */}
          <div className="bg-gray-800 rounded-lg overflow-hidden shadow-lg">
            <div className="p-4 border-b border-gray-700">
              <h2 className="text-xl font-semibold text-indigo-300">Combined Losses</h2>
              <p className="text-gray-400 text-sm mt-1">Top 10 characters by losses value and count</p>
            </div>
            <div className="p-4">
              {charts.combined_losses ? (
                <img 
                  src={charts.combined_losses} 
                  alt="Combined Losses Chart" 
                  className="w-full h-auto rounded"
                />
              ) : (
                <div className="bg-gray-700 rounded-md h-64 flex items-center justify-center">
                  {loading ? (
                    <FaCircleNotch className="h-8 w-8 text-indigo-400 animate-spin" />
                  ) : (
                    <span className="text-gray-400">No chart available</span>
                  )}
                </div>
              )}
            </div>
            <div className="p-4 border-t border-gray-700">
              <button 
                onClick={() => sendToDiscord('combined_losses')}
                disabled={!charts.combined_losses || statusMessages.combined_losses?.loading}
                className="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition-colors flex items-center space-x-2 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <FaDiscord />
                <span>Send to Discord</span>
              </button>
              
              {statusMessages.combined_losses?.success && (
                <div className="mt-2 text-green-400 text-sm">
                  {statusMessages.combined_losses.success}
                </div>
              )}
              
              {statusMessages.combined_losses?.error && (
                <div className="mt-2 text-red-400 text-sm">
                  {statusMessages.combined_losses.error}
                </div>
              )}
            </div>
          </div>

          {/* Kill Activity Chart */}
          <div className="bg-gray-800 rounded-lg overflow-hidden shadow-lg lg:col-span-2">
            <div className="p-4 border-b border-gray-700">
              <h2 className="text-xl font-semibold text-indigo-300">Kill Activity Over Time</h2>
              <p className="text-gray-400 text-sm mt-1">Kill activity trend over time</p>
            </div>
            <div className="p-4">
              {charts.kill_activity ? (
                <img 
                  src={charts.kill_activity} 
                  alt="Kill Activity Chart" 
                  className="w-full h-auto rounded"
                />
              ) : (
                <div className="bg-gray-700 rounded-md h-64 flex items-center justify-center">
                  {loading ? (
                    <FaCircleNotch className="h-8 w-8 text-indigo-400 animate-spin" />
                  ) : (
                    <span className="text-gray-400">No chart available</span>
                  )}
                </div>
              )}
            </div>
            <div className="p-4 border-t border-gray-700">
              <button 
                onClick={() => sendToDiscord('kill_activity')}
                disabled={!charts.kill_activity || statusMessages.kill_activity?.loading}
                className="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition-colors flex items-center space-x-2 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <FaDiscord />
                <span>Send to Discord</span>
              </button>
              
              {statusMessages.kill_activity?.success && (
                <div className="mt-2 text-green-400 text-sm">
                  {statusMessages.kill_activity.success}
                </div>
              )}
              
              {statusMessages.kill_activity?.error && (
                <div className="mt-2 text-red-400 text-sm">
                  {statusMessages.kill_activity.error}
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
} 