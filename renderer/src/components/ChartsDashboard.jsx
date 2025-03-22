import React, { useState, useEffect } from 'react';
import { FaSync, FaDiscord, FaChartBar, FaExclamationTriangle, FaCircleNotch } from 'react-icons/fa';
import ActivityChartCard from './ActivityChartCard';
import KillmailChartCard from './KillmailChartCard';

export default function ChartsDashboard() {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [features, setFeatures] = useState({
    mapToolsEnabled: false,
    persistenceEnabled: false
  });
  const [sendingAllCharts, setSendingAllCharts] = useState(false);
  const [sendAllSuccess, setSendAllSuccess] = useState(false);
  const [sendAllError, setSendAllError] = useState(null);

  useEffect(() => {
    // Check available features
    fetch('/charts/config')
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        setFeatures({
          mapToolsEnabled: data.map_tools_enabled || false,
          persistenceEnabled: data.persistence_enabled || false
        });
        setLoading(false);
      })
      .catch(error => {
        console.error('Error fetching feature configuration:', error);
        setError(error.message);
        setLoading(false);
      });
  }, []);

  const sendAllActivityCharts = () => {
    setSendingAllCharts(true);
    setSendAllSuccess(false);
    setSendAllError(null);
    
    console.log("Sending all activity charts to Discord...");
    
    fetch('/charts/activity/send-all')
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        if (data.status === 'ok') {
          setSendAllSuccess(true);
          // Clear success message after 5 seconds
          setTimeout(() => setSendAllSuccess(false), 5000);
        } else {
          throw new Error(data.message || 'Failed to send all charts to Discord');
        }
      })
      .catch(error => {
        console.error('Error sending all charts to Discord:', error);
        setSendAllError(error.message);
      })
      .finally(() => {
        setSendingAllCharts(false);
      });
  };

  const sendAllKillmailCharts = () => {
    setSendingAllCharts(true);
    setSendAllSuccess(false);
    setSendAllError(null);
    
    console.log("Sending all killmail charts to Discord...");
    
    fetch('/charts/killmail/send-all')
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        if (data.status === 'ok') {
          setSendAllSuccess(true);
          // Clear success message after 5 seconds
          setTimeout(() => setSendAllSuccess(false), 5000);
        } else {
          throw new Error(data.message || 'Failed to send all charts to Discord');
        }
      })
      .catch(error => {
        console.error('Error sending all killmail charts to Discord:', error);
        setSendAllError(error.message);
      })
      .finally(() => {
        setSendingAllCharts(false);
      });
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <FaCircleNotch className="h-10 w-10 text-indigo-600 animate-spin" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="container mx-auto px-4 py-8">
        <div className="bg-red-100 border-l-4 border-red-500 text-red-700 p-4 rounded">
          <div className="flex items-center">
            <FaExclamationTriangle className="mr-2" />
            <p>Error loading chart configuration: {error}</p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="mb-8 text-center">
        <h1 className="text-3xl font-bold text-gray-800 mb-2">Charts Dashboard</h1>
        <p className="text-gray-600">
          Generate and send various charts to Discord channels
        </p>
      </div>

      {/* Feature status indicators */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <div className={`p-4 rounded-lg ${features.mapToolsEnabled ? 'bg-green-50 border border-green-200' : 'bg-gray-100 border border-gray-200'}`}>
          <div className="flex items-center">
            <div className={`w-3 h-3 rounded-full mr-2 ${features.mapToolsEnabled ? 'bg-green-500' : 'bg-gray-400'}`}></div>
            <span className="font-medium">Map Tools: {features.mapToolsEnabled ? 'Enabled' : 'Disabled'}</span>
          </div>
        </div>
        <div className={`p-4 rounded-lg ${features.persistenceEnabled ? 'bg-green-50 border border-green-200' : 'bg-gray-100 border border-gray-200'}`}>
          <div className="flex items-center">
            <div className={`w-3 h-3 rounded-full mr-2 ${features.persistenceEnabled ? 'bg-green-500' : 'bg-gray-400'}`}></div>
            <span className="font-medium">Persistence: {features.persistenceEnabled ? 'Enabled' : 'Disabled'}</span>
          </div>
        </div>
      </div>

      {/* Map Tools Charts Section (conditional) */}
      {features.mapToolsEnabled && (
        <div className="mb-12">
          <div className="mb-6 flex justify-between items-center">
            <h2 className="text-2xl font-semibold text-gray-800">Character Activity Charts</h2>
            <button 
              onClick={sendAllActivityCharts}
              disabled={sendingAllCharts}
              className="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition-colors flex items-center space-x-2 disabled:opacity-50"
            >
              {sendingAllCharts ? 
                <span className="flex items-center">
                  <FaCircleNotch className="animate-spin mr-2" />
                  Sending... 
                </span> : 
                <span className="flex items-center">
                  <FaDiscord className="mr-2" />
                  Send All to Discord
                </span>
              }
            </button>
          </div>
          
          {sendAllSuccess && (
            <div className="mb-4 px-4 py-2 bg-green-100 text-green-700 rounded">
              All charts have been sent to Discord successfully!
            </div>
          )}
          
          {sendAllError && (
            <div className="mb-4 px-4 py-2 bg-red-100 text-red-700 rounded flex items-center">
              <FaExclamationTriangle className="mr-2" />
              <span>Error sending charts: {sendAllError}</span>
            </div>
          )}
          
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <ActivityChartCard 
              title="Character Activity Summary" 
              description="Top 10 most active characters by connections, passages, and signatures"
              chartType="activity_summary"
            />
            <ActivityChartCard 
              title="Activity Timeline" 
              description="Activity trends over time for the top 5 most active characters"
              chartType="activity_timeline"
            />
            <ActivityChartCard 
              title="Activity Distribution" 
              description="Distribution of activity types across all characters"
              chartType="activity_distribution"
            />
          </div>
        </div>
      )}

      {/* Killmail Charts Section (conditional) */}
      {features.persistenceEnabled && (
        <div className="mb-12">
          <div className="mb-6 flex justify-between items-center">
            <h2 className="text-2xl font-semibold text-gray-800">Killmail Charts</h2>
            <button 
              onClick={sendAllKillmailCharts}
              disabled={sendingAllCharts}
              className="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition-colors flex items-center space-x-2 disabled:opacity-50"
            >
              {sendingAllCharts ? 
                <span className="flex items-center">
                  <FaCircleNotch className="animate-spin mr-2" />
                  Sending... 
                </span> : 
                <span className="flex items-center">
                  <FaDiscord className="mr-2" />
                  Send All to Discord
                </span>
              }
            </button>
          </div>
          
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <KillmailChartCard 
              title="Weekly Character Kills" 
              description="Top 20 characters by kills in the past week"
              chartType="weekly_kills"
            />
            {/* Add more killmail chart types here in the future */}
          </div>
        </div>
      )}

      {/* No features enabled message */}
      {!features.mapToolsEnabled && !features.persistenceEnabled && (
        <div className="bg-yellow-50 border border-yellow-100 rounded-lg p-6 text-center">
          <h3 className="text-lg font-medium text-yellow-800">No chart features are enabled</h3>
          <p className="mt-2 text-yellow-700">
            Enable Map Tools or Persistence in your configuration to view available charts.
          </p>
        </div>
      )}
    </div>
  );
} 