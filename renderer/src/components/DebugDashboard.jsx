import React, { useState, useEffect } from 'react';
import { FaSync, FaDiscord, FaChartBar, FaExclamationTriangle, FaCircleNotch, FaUsers, FaMap, FaUserFriends, FaBug } from 'react-icons/fa';
import ChartCard from './ChartCard';
import ActivityChartCard from './ActivityChartCard';

export default function DebugDashboard() {
  const [charts, setCharts] = useState({
    damage_final_blows: null,
    combined_losses: null,
    kill_activity: null
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [statusMessage, setStatusMessage] = useState(null);
  
  // Feature flags
  const [corpToolsEnabled, setCorpToolsEnabled] = useState(false);
  const [mapToolsEnabled, setMapToolsEnabled] = useState(false);

  useEffect(() => {
    // Check if the API is available and fetch configuration
    fetch('/charts/config')
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        setCorpToolsEnabled(data.corp_tools_enabled);
        setMapToolsEnabled(data.map_tools_enabled);
        
        if (!data.corp_tools_enabled && !data.map_tools_enabled) {
          setStatusMessage("No debug features are currently enabled. Enable Corp Tools or Map Tools in your configuration.");
        }
        
        setLoading(false);
      })
      .catch(error => {
        console.error('Error connecting to API:', error);
        setError(error.message);
        setLoading(false);
      });
  }, []);

  // Load chart data when component mounts
  useEffect(() => {
    if (corpToolsEnabled) {
      loadChartData();
    }
  }, [corpToolsEnabled]);

  const loadChartData = async () => {
    try {
      setLoading(true);
      
      // Function to fetch a specific chart
      const fetchChart = async (chartType) => {
        try {
          const response = await fetch(`/charts/${chartType}`);
          if (!response.ok) {
            throw new Error(`HTTP error! Status: ${response.status}`);
          }
          const data = await response.json();
          return data;
        } catch (err) {
          console.error(`Error fetching ${chartType} chart:`, err);
          return null;
        }
      };
      
      // Fetch all chart data in parallel
      const [damageData, lossesData, activityData] = await Promise.all([
        fetchChart('damage_final_blows'),
        fetchChart('combined_losses'),
        fetchChart('kill_activity')
      ]);
      
      setCharts({
        damage_final_blows: damageData,
        combined_losses: lossesData,
        kill_activity: activityData
      });
      
      setLoading(false);
    } catch (err) {
      console.error("Error loading chart data:", err);
      setError("Failed to load chart data. Please try again.");
      setLoading(false);
    }
  };

  // Send chart to Discord
  const sendChartToDiscord = async (chartType) => {
    try {
      setStatusMessage(`Sending ${chartType} chart to Discord...`);
      
      const response = await fetch(`/charts/send/${chartType}`, {
        method: 'POST'
      });
      
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      
      const data = await response.json();
      setStatusMessage(data.message || "Chart sent successfully!");
      
      setTimeout(() => {
        setStatusMessage(null);
      }, 3000);
    } catch (err) {
      console.error(`Error sending ${chartType} chart:`, err);
      setStatusMessage(`Error sending chart: ${err.message}`);
    }
  };

  // Send activity chart to Discord
  const sendActivityChartToDiscord = async (chartType) => {
    try {
      setStatusMessage(`Sending ${chartType} chart to Discord...`);
      
      const response = await fetch(`/map-tools/send/${chartType}`, {
        method: 'POST'
      });
      
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      
      const data = await response.json();
      setStatusMessage(data.message || "Activity chart sent successfully!");
      
      setTimeout(() => {
        setStatusMessage(null);
      }, 3000);
    } catch (err) {
      console.error(`Error sending ${chartType} chart:`, err);
      setStatusMessage(`Error sending chart: ${err.message}`);
    }
  };

  // Loading state
  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <FaCircleNotch className="animate-spin text-indigo-600 text-4xl" />
      </div>
    );
  }

  // Error state
  if (error) {
    return (
      <div className="flex items-center justify-center min-h-screen p-4">
        <div className="bg-red-50 border border-red-200 rounded-md p-4 max-w-lg w-full">
          <div className="flex items-center text-red-700 mb-2">
            <FaExclamationTriangle className="mr-2" />
            <h2 className="text-lg font-semibold">Error</h2>
          </div>
          <p className="text-red-600">{error}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto px-4 py-8 sm:px-6 lg:px-8 space-y-8">
      {/* Header */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 flex items-center">
            <FaBug className="mr-2 text-purple-600" />
            Debug Dashboard
          </h1>
          <p className="text-gray-600 mt-1">
            Combined tools for debugging and troubleshooting
          </p>
        </div>
        
        {/* Refresh button (for Corp Tools) */}
        {corpToolsEnabled && (
          <button
            onClick={loadChartData}
            className="mt-4 sm:mt-0 inline-flex items-center px-4 py-2 border border-transparent 
                      rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 
                      hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
          >
            <FaSync className="mr-2" />
            Refresh Charts
          </button>
        )}
      </div>
      
      {/* Status message */}
      {statusMessage && (
        <div className="bg-blue-50 border border-blue-200 text-blue-700 px-4 py-3 rounded-md">
          {statusMessage}
        </div>
      )}
      
      {/* Feature status indicators */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <div className={`p-4 rounded-lg ${corpToolsEnabled ? 'bg-green-50 border border-green-200' : 'bg-gray-100 border border-gray-200'}`}>
          <div className="flex items-center">
            <div className={`w-3 h-3 rounded-full mr-2 ${corpToolsEnabled ? 'bg-green-500' : 'bg-gray-400'}`}></div>
            <span className="font-medium">Corp Tools: {corpToolsEnabled ? 'Enabled' : 'Disabled'}</span>
          </div>
        </div>
        <div className={`p-4 rounded-lg ${mapToolsEnabled ? 'bg-green-50 border border-green-200' : 'bg-gray-100 border border-gray-200'}`}>
          <div className="flex items-center">
            <div className={`w-3 h-3 rounded-full mr-2 ${mapToolsEnabled ? 'bg-green-500' : 'bg-gray-400'}`}></div>
            <span className="font-medium">Map Tools: {mapToolsEnabled ? 'Enabled' : 'Disabled'}</span>
          </div>
        </div>
      </div>
      
      {/* Chart grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
        {/* Corp Tools Charts */}
        {corpToolsEnabled && (
          <>
            {/* Damage & Final Blows */}
            <ChartCard
              title="Damage & Final Blows"
              description="Top pilots by damage done and final blows"
              chartType="damage_final_blows"
              chartData={charts.damage_final_blows}
              onSendToDiscord={() => sendChartToDiscord('damage_final_blows')}
            />
            
            {/* Combined Losses */}
            <ChartCard
              title="Combined Losses"
              description="Top pilots by combined ship and pod losses"
              chartType="combined_losses"
              chartData={charts.combined_losses}
              onSendToDiscord={() => sendChartToDiscord('combined_losses')}
            />
            
            {/* Kill Activity */}
            <ChartCard
              title="Kill Activity"
              description="Kill activity over time"
              chartType="kill_activity"
              chartData={charts.kill_activity}
              onSendToDiscord={() => sendChartToDiscord('kill_activity')}
            />
          </>
        )}
        
        {/* Map Tools Charts */}
        {mapToolsEnabled && (
          <ActivityChartCard 
            title="Character Activity Summary" 
            description="Top characters by connections, passages, and signatures"
            chartType="activity_summary"
            onSendToDiscord={() => sendActivityChartToDiscord('activity_summary')}
          />
        )}
        
        {/* If neither is enabled, show a message */}
        {!corpToolsEnabled && !mapToolsEnabled && (
          <div className="col-span-full bg-yellow-50 p-4 rounded-lg border border-yellow-200">
            <div className="flex items-center text-yellow-700">
              <FaExclamationTriangle className="mr-2" />
              <span>No debug features are currently enabled. Enable Corp Tools or Map Tools in your configuration.</span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
} 