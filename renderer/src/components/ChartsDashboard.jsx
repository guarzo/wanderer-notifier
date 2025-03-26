import React, { useState, useEffect } from 'react';
import { FaCircleNotch, FaDiscord, FaExclamationTriangle } from 'react-icons/fa';
import ActivityChartCard from './ActivityChartCard';
import KillmailChartCard from './KillmailChartCard';
import CharacterKillsCard from './CharacterKillsCard';

export default function ChartsDashboard() {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [features, setFeatures] = useState({
    mapChartsEnabled: false,
    killChartsEnabled: false
  });
  const [sendingAllCharts, setSendingAllCharts] = useState(false);
  const [sendAllSuccess, setSendAllSuccess] = useState(false);
  const [sendAllError, setSendAllError] = useState(null);

  useEffect(() => {
    try {
      fetch('/charts/config')
        .then(response => response.json())
        .then(data => {
          setFeatures({
            mapChartsEnabled: data.map_tools_enabled || false,
            killChartsEnabled: data.kill_charts_enabled || false
          });
          setLoading(false);
        })
        .catch(error => {
          console.error('Error fetching chart configuration:', error);
          setError(`Failed to load chart configuration: ${error.message}`);
          setFeatures({
            mapChartsEnabled: false,
            killChartsEnabled: false
          });
          setLoading(false);
        });
    } catch (err) {
      console.error('Unhandled error in chart config fetch:', err);
      setError(`Unhandled error: ${err.message}`);
      setLoading(false);
    }
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
          setTimeout(() => setSendAllSuccess(false), 5000);
        } else {
          let errorMessage = data.message || 'Failed to send charts to Discord';
          if (data.details) {
            errorMessage += `: ${JSON.stringify(data.details)}`;
          }
          throw new Error(errorMessage);
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
          Generate and send charts to Discord channels
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <div className={`p-4 rounded-lg ${features.mapChartsEnabled ? 'bg-green-50 border border-green-200' : 'bg-gray-100 border border-gray-200'}`}>
          <div className="flex items-center">
            <div className={`w-3 h-3 rounded-full mr-2 ${features.mapChartsEnabled ? 'bg-green-500' : 'bg-gray-400'}`}></div>
            <span className="font-medium">Map Charts: {features.mapChartsEnabled ? 'Enabled' : 'Disabled'}</span>
          </div>
        </div>
        <div className={`p-4 rounded-lg ${features.killChartsEnabled ? 'bg-green-50 border border-green-200' : 'bg-gray-100 border border-gray-200'}`}>
          <div className="flex items-center">
            <div className={`w-3 h-3 rounded-full mr-2 ${features.killChartsEnabled ? 'bg-green-500' : 'bg-gray-400'}`}></div>
            <span className="font-medium">Killmail Charts: {features.killChartsEnabled ? 'Enabled' : 'Disabled'}</span>
          </div>
        </div>
      </div>

      {features.mapChartsEnabled && (
        <div className="mb-12">
          <div className="mb-6 flex justify-between items-center">
            <h2 className="text-2xl font-semibold text-gray-800">Character Activity Charts</h2>
            <button 
              type="button"
              onClick={sendAllActivityCharts}
              disabled={sendingAllCharts}
              title="Send all activity charts to Discord"
              className="p-3 bg-indigo-600 text-white rounded-full hover:bg-indigo-700 transition-colors flex items-center justify-center disabled:opacity-50"
            >
              {sendingAllCharts ? 
                <FaCircleNotch className="animate-spin" /> : 
                <FaDiscord />
              }
            </button>
          </div>
          
          {sendAllSuccess && (
            <div className="mb-4 px-4 py-2 bg-green-100 text-green-700 rounded">
              Both weekly kills and ISK destroyed charts have been sent to Discord successfully!
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
          </div>
        </div>
      )}

      {features.killChartsEnabled && (
        <div className="mb-12">
          <div className="mb-6 flex justify-between items-center">
            <h2 className="text-2xl font-semibold text-gray-800">Killmail Charts</h2>
            <button 
              type="button"
              onClick={sendAllKillmailCharts}
              disabled={sendingAllCharts}
              title="Send all killmail charts to Discord"
              className="p-3 bg-indigo-600 text-white rounded-full hover:bg-indigo-700 transition-colors flex items-center justify-center disabled:opacity-50"
            >
              {sendingAllCharts ? 
                <FaCircleNotch className="animate-spin" /> : 
                <FaDiscord />
              }
            </button>
          </div>
          
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-2 gap-6">
            <KillmailChartCard 
              title="Weekly Character Kills" 
              description="Top 20 characters by kills in the past week"
              chartType="weekly_kills"
            />
            
            <KillmailChartCard 
              title="Weekly ISK Destroyed" 
              description="Top 20 characters by ISK destroyed in the past week"
              chartType="weekly_isk"
            />
          </div>
          
          <div className="mt-6">
            <CharacterKillsCard
              title="Character Kill History" 
              description="Fetch and store historical kills for tracked characters"
            />
          </div>
        </div>
      )}

      {(!features.mapChartsEnabled && !features.killChartsEnabled) && (
        <div className="bg-yellow-50 border border-yellow-100 rounded-lg p-6 text-center">
          <h3 className="text-lg font-medium text-yellow-800">No chart features are enabled</h3>
          <p className="mt-2 text-yellow-700">
            Enable Map Charts or Killmail Charts in your configuration to view available charts.
          </p>
        </div>
      )}
    </div>
  );
}
