import React, { useState, useEffect } from 'react';
import { FaCircleNotch, FaDiscord, FaExclamationTriangle, FaCheckCircle, FaChartBar, FaInfoCircle, FaMapMarkedAlt } from 'react-icons/fa';
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
  const [sendAllSuccess, setSendAllSuccess] = useState(null);
  const [sendAllError, setSendAllError] = useState(null);

  useEffect(() => {
    try {
      fetch('/api/debug/status')
        .then(response => response.json())
        .then(response => {
          const features = response.data.features;
          setFeatures({
            mapChartsEnabled: features.map_charts || false,
            killChartsEnabled: features.kill_charts || false
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

  const loadChartImage = async (url) => {
    try {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      const blob = await response.blob();
      return URL.createObjectURL(blob);
    } catch (error) {
      console.error('Error loading chart image:', error);
      throw error;
    }
  };

  const sendAllKillmailCharts = () => {
    setSendingAllCharts(true);
    setSendAllSuccess(null);
    setSendAllError(null);
    
    console.log("Sending all killmail charts to Discord...");
    
    fetch('/api/charts/killmail/send-all')
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        if (data.status === 'ok') {
          setSendAllSuccess('All charts successfully sent to Discord!');
          setTimeout(() => setSendAllSuccess(null), 5000);
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
      <div className="flex flex-col items-center justify-center min-h-screen bg-gray-50">
        <FaCircleNotch className="h-12 w-12 text-indigo-600 animate-spin mb-4" />
        <h2 className="text-xl font-semibold text-gray-700">Loading Charts Dashboard...</h2>
      </div>
    );
  }

  if (error) {
    return (
      <div className="container mx-auto px-4 py-16">
        <div className="bg-red-100 border border-red-200 rounded-lg p-6 shadow-md">
          <div className="flex items-center mb-4">
            <FaExclamationTriangle className="text-red-500 h-8 w-8 mr-3" />
            <h2 className="text-xl font-bold text-red-700">Configuration Error</h2>
          </div>
          <p className="text-red-700 mb-4">{error}</p>
          <p className="text-gray-600">
            Please check your configuration settings and ensure the backend services are running.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-8">
      {/* Header with EVE-inspired styling */}
      <div className="mb-8 text-center">
        <div className="inline-block bg-gradient-to-r from-blue-600 to-indigo-800 p-2 rounded-lg shadow-lg mb-4">
          <FaChartBar className="h-8 w-8 text-white" />
        </div>
        <h1 className="text-3xl font-bold text-gray-800 mb-2">EVE Online Charts Dashboard</h1>
        <p className="text-gray-600">
          Killmail visualization and statistics for tracked characters
        </p>
      </div>

      {/* Feature Status Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <div className={`p-4 rounded-lg shadow-sm transition-all duration-300 ${features.mapChartsEnabled ? 'bg-green-50 border border-green-200 hover:shadow-md' : 'bg-gray-100 border border-gray-200'}`}>
          <div className="flex items-center">
            <div className={`flex-shrink-0 rounded-full p-2 mr-3 ${features.mapChartsEnabled ? 'bg-green-100 text-green-500' : 'bg-gray-200 text-gray-400'}`}>
              <FaMapMarkedAlt className="h-5 w-5" />
            </div>
            <div>
              <span className="block font-medium">Map Charts</span>
              <span className={`text-sm ${features.mapChartsEnabled ? 'text-green-600' : 'text-gray-500'}`}>
                {features.mapChartsEnabled ? 'Enabled' : 'Disabled'}
              </span>
            </div>
          </div>
        </div>
        <div className={`p-4 rounded-lg shadow-sm transition-all duration-300 ${features.killChartsEnabled ? 'bg-green-50 border border-green-200 hover:shadow-md' : 'bg-gray-100 border border-gray-200'}`}>
          <div className="flex items-center">
            <div className={`flex-shrink-0 rounded-full p-2 mr-3 ${features.killChartsEnabled ? 'bg-green-100 text-green-500' : 'bg-gray-200 text-gray-400'}`}>
              <FaChartBar className="h-5 w-5" />
            </div>
            <div>
              <span className="block font-medium">Kill Charts</span>
              <span className={`text-sm ${features.killChartsEnabled ? 'text-green-600' : 'text-gray-500'}`}>
                {features.killChartsEnabled ? 'Enabled' : 'Disabled'}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Status Messages */}
      {sendAllSuccess && (
        <div className="mb-6 p-4 bg-green-50 border border-green-200 rounded-lg shadow-sm">
          <div className="flex items-center text-green-700">
            <FaCheckCircle className="mr-2" />
            {sendAllSuccess}
          </div>
        </div>
      )}

      {sendAllError && (
        <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg shadow-sm">
          <div className="flex items-center text-red-700">
            <FaExclamationTriangle className="mr-2" />
            {sendAllError}
          </div>
        </div>
      )}

      {/* Send All Charts Button (only visible if Kill Charts are enabled) */}
      {features.killChartsEnabled && (
        <div className="mb-6">
          <button 
            type="button"
            onClick={sendAllKillmailCharts}
            disabled={sendingAllCharts}
            className="flex items-center justify-center px-6 py-3 bg-indigo-600 hover:bg-indigo-700 text-white font-medium rounded-lg shadow-sm transition-colors disabled:opacity-50"
          >
            {sendingAllCharts ? (
              <FaCircleNotch className="animate-spin mr-2" />
            ) : (
              <FaDiscord className="mr-2" />
            )}
            Send All Killmail Charts to Discord
          </button>
        </div>
      )}

      {/* Chart Cards with better layout */}
      {features.mapChartsEnabled && (
        <div className="mb-10">
          <div className="flex items-center mb-4">
            <FaMapMarkedAlt className="text-indigo-500 mr-2" />
            <h2 className="text-xl font-semibold text-gray-800">Activity Charts</h2>
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <ActivityChartCard 
              title="Activity Summary"
              description="Character activity summary for the last 24 hours"
              chartType="activity_summary"
              loadChartImage={loadChartImage}
            />
          </div>
        </div>
      )}

      {features.killChartsEnabled && (
        <div>
          <div className="flex items-center mb-4">
            <FaChartBar className="text-indigo-500 mr-2" />
            <h2 className="text-xl font-semibold text-gray-800">Killmail Charts</h2>
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
            <KillmailChartCard 
              title="Weekly Character Kills"
              description="Top characters by kills in the past week"
              chartType="weekly_kills"
              loadChartImage={loadChartImage}
            />
            <KillmailChartCard 
              title="Weekly ISK Destroyed"
              description="Top characters by ISK destroyed in the past week"
              chartType="weekly_isk"
              loadChartImage={loadChartImage}
            />
            <KillmailChartCard 
              title="Kill Validation"
              description="Comparison of kills in ZKillboard API vs Database"
              chartType="validation"
              loadChartImage={loadChartImage}
            />
          </div>
          <div className="mt-6">
            <CharacterKillsCard 
              title="Character Kill Data" 
              description="Load and aggregate kill data for tracked characters"
            />
          </div>
        </div>
      )}

      {(!features.mapChartsEnabled && !features.killChartsEnabled) && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-6 text-center shadow-md">
          <FaInfoCircle className="h-10 w-10 text-yellow-500 mx-auto mb-4" />
          <h3 className="text-xl font-medium text-yellow-800 mb-2">No Chart Features Enabled</h3>
          <p className="text-yellow-700 mb-4">
            Both map and kill chart features are currently disabled in your configuration.
          </p>
          <p className="text-gray-600 text-sm">
            Enable these features in your application configuration to view available charts.
          </p>
        </div>
      )}
    </div>
  );
}
