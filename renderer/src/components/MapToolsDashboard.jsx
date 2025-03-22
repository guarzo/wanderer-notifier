import React, { useState, useEffect } from 'react';
import ActivityTable from './ActivityTable';
import ActivityChartCard from './ActivityChartCard';
import { FaExclamationTriangle, FaMap, FaChartBar, FaUserFriends, FaDiscord } from 'react-icons/fa';

function MapToolsDashboard() {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [activeTab, setActiveTab] = useState('activity');
  const [sendingAllCharts, setSendingAllCharts] = useState(false);
  const [sendAllSuccess, setSendAllSuccess] = useState(false);
  const [sendAllError, setSendAllError] = useState(null);

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
        if (!data.map_tools_enabled) {
          throw new Error('Map Tools functionality is not enabled');
        }
        setLoading(false);
      })
      .catch(error => {
        console.error('Error connecting to API:', error);
        setError(error.message);
        setLoading(false);
      });
  }, []);

  const sendAllChartsToDiscord = () => {
    setSendingAllCharts(true);
    setSendAllSuccess(false);
    setSendAllError(null);
    
    console.log("Sending all activity charts to Discord...");
    
    fetch('/charts/activity/send-all')
      .then(response => {
        console.log(`Response status: ${response.status}`);
        if (!response.ok) {
          if (response.status === 404) {
            throw new Error("Endpoint not found. Check server routes configuration.");
          }
          return response.json().then(data => {
            throw new Error(data.message || `HTTP error! Status: ${response.status}`);
          });
        }
        return response.json();
      })
      .then(data => {
        console.log("Send all charts response:", data);
        if (data.status === 'ok') {
          setSendAllSuccess(true);
          if (data.results) {
            console.log('Chart sending results:', data.results);
          }
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
        
        // Clear success message after 5 seconds
        if (sendAllSuccess) {
          setTimeout(() => setSendAllSuccess(false), 5000);
        }
      });
  };

  const renderTabContent = () => {
    switch (activeTab) {
      case 'activity':
        return <ActivityTable />;
      case 'charts':
        return (
          <div>
            <div className="mb-6 flex justify-between items-center">
              <h3 className="text-xl font-semibold text-gray-700">Activity Charts</h3>
              <button 
                onClick={sendAllChartsToDiscord}
                disabled={sendingAllCharts}
                className="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition-colors flex items-center space-x-2 disabled:opacity-50"
              >
                {sendingAllCharts ? 
                  <span className="flex items-center">
                    <FaDiscord className="mr-2" />
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
                All charts have been scheduled to be sent to Discord
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
        );
      default:
        return <div>Select a tab to view content</div>;
    }
  };

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="mb-8 text-center">
        <h1 className="text-3xl font-bold text-gray-800 mb-2">Map Tools Dashboard</h1>
        <p className="text-gray-600">
          View and manage EVE Online map-related analytics and tools
        </p>
      </div>

      {/* Tabs */}
      <div className="mb-6 border-b border-gray-200">
        <ul className="flex flex-wrap -mb-px">
          <li className="mr-2">
            <button
              className={`inline-flex items-center py-4 px-4 text-sm font-medium text-center border-b-2 ${
                activeTab === 'activity'
                  ? 'text-blue-600 border-blue-600'
                  : 'text-gray-500 border-transparent hover:text-gray-600 hover:border-gray-300'
              }`}
              onClick={() => setActiveTab('activity')}
            >
              <FaUserFriends className="mr-2" />
              Activity Table
            </button>
          </li>
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
              Activity Charts
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

export default MapToolsDashboard; 