// src/components/Dashboard.jsx
import React, { useEffect, useState } from "react";
import {
  FaSync,
  FaCheckCircle,
  FaCloud,
  FaHeart,
  FaTimes,
  FaCircleNotch,
  FaExclamationTriangle,
  FaBell,
  FaInfo,
  FaServer,
  FaCog,
  FaClock,
  FaUserAlt,
  FaGlobe,
  FaChartLine,
  FaNetworkWired,
  FaChartBar
} from "react-icons/fa";
import { DataCard } from "../components/ui/Card";
import { GridLayout, TwoColumnGrid } from "../components/ui/GridLayout";
import { StatusCard } from "../components/ui/StatusCard";

export default function Dashboard() {
  const [status, setStatus] = useState({
    services: { backend: "Unknown", notifications: "Unknown", api: "Unknown" },
    license: { status: "Unknown", expires_in: null },
    features: {},
    limits: { tracked_systems: 0, tracked_characters: 0, notification_history: 0 },
    stats: {
      characters_count: 0,
      systems_count: 0,
      uptime: "0s",
      notifications: { total: 0, characters: 0, kills: 0, systems: 0 },
      processing: { kills_processed: 0, kills_notified: 0 },
      websocket: { connected: false, connecting: false, last_message: null }
    }
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [testMessage, setTestMessage] = useState(null);
  const [features, setFeatures] = useState({});
  const [retryCount, setRetryCount] = useState(0);

  // On mount, fetch dashboard status
  useEffect(() => {
    fetchStatus();
    
    // Set up automatic refresh every 30 seconds
    const intervalId = setInterval(() => {
      fetchStatus();
    }, 30000);
    
    // Clean up interval on unmount
    return () => clearInterval(intervalId);
  }, []);

  // Fetch the status data
  async function fetchStatus() {
    try {
      setLoading(true);
      console.log("Fetching status data from API...");
      const response = await fetch("/api/debug/status");
      
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      
      // Try to parse the response as JSON
      const text = await response.text();
      let data;
      
      try {
        data = JSON.parse(text);
      } catch (jsonError) {
        console.error("Failed to parse JSON:", text);
        throw new Error("Invalid response from server. Backend may be misconfigured.");
      }
      
      console.log("Status data received:", data);
      
      // The data is directly in the response, not nested under "data"
      // Just extract what we need directly from the root object
      const statusData = {
        services: data.services || { backend: "Unknown", notifications: "Unknown", api: "Unknown" },
        license: data.license || { status: "Unknown", expires_in: null },
        features: data.features || {},
        limits: data.limits || { tracked_systems: 0, tracked_characters: 0, notification_history: 0 },
        stats: data.stats || {
          characters_count: 0,
          systems_count: 0,
          uptime: "0s",
          notifications: { total: 0, characters: 0, kills: 0, systems: 0 },
          processing: { kills_processed: 0, kills_notified: 0 }
        },
        websocket: data.stats?.websocket || { connected: false, connecting: false, last_message: null }
      };
      
      // Set the state with the data from the API
      setStatus(statusData);
      setFeatures(statusData.features || {});
      setError(null);
      setRetryCount(0);
    } catch (err) {
      console.error("Error fetching status:", err);
      
      // Implement retry logic with exponential backoff
      if (retryCount < 3) {
        const delay = Math.pow(2, retryCount) * 1000;
        console.log(`Retrying in ${delay}ms... (attempt ${retryCount + 1})`);
        
        setTimeout(() => {
          setRetryCount(prev => prev + 1);
          fetchStatus();
        }, delay);
        
        return;
      }
      
      setError("Failed to load dashboard data. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  // Toolbar actions
  async function handleRefreshPage() {
    setRetryCount(0);
    await fetchStatus();
    setTestMessage("Dashboard refreshed!");
    // Clear the message after 3 seconds
    setTimeout(() => setTestMessage(null), 3000);
  }

  async function handleRevalidateLicense() {
    try {
      const response = await fetch("/api/revalidate-license");
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      
      // Check if the validation was actually successful by examining the success field
      if (data.success) {
        setTestMessage(data.message || "License successfully validated!");
      } else {
        // Handle unsuccessful validation with the error message
        console.error("License validation failed:", data.details);
        setTestMessage(data.message || "License validation failed");
      }
      
      // Refresh the status display
      fetchStatus();
      
      // Clear the message after 3 seconds
      setTimeout(() => setTestMessage(null), 3000);
    } catch (err) {
      console.error("Error revalidating license:", err);
      setTestMessage("Error revalidating license");
      // Clear the message after 3 seconds
      setTimeout(() => setTestMessage(null), 3000);
    }
  }

  /* -------------------------
   * Loading & Error States
   * ------------------------*/
  if (loading && !status) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        {/* Animated spinner */}
        <FaCircleNotch className="h-10 w-10 text-indigo-600 animate-spin" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex items-center justify-center min-h-screen px-4">
        <div className="flex flex-col space-y-4 items-center max-w-md">
          <div className="flex items-center space-x-3 bg-red-50 border border-red-200 text-red-600 p-4 rounded-md w-full">
            <FaExclamationTriangle className="text-red-600 flex-shrink-0" />
            <span>{error}</span>
          </div>
          <button
            onClick={handleRefreshPage}
            className="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition-colors"
          >
            <FaSync className="mr-2 inline" />
            Retry
          </button>
        </div>
      </div>
    );
  }

  /* -------------------------
   * Main Dashboard UI
   * ------------------------*/
  return (
    <div className="min-h-screen bg-gradient-to-br from-indigo-100 via-blue-50 to-white page-transition">
      {/* Outer container with spacing */}
      <div className="max-w-7xl mx-auto px-4 py-8 sm:px-6 lg:px-8 space-y-8">
        {/* Title & Toolbar */}
        <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between mb-6">
          <h1 className="flex items-center text-2xl font-bold text-indigo-800 space-x-2 mb-4 sm:mb-0">
            <FaBell className="text-indigo-700" />
            <span>Wanderer Notifier Dashboard</span>
          </h1>
          <div className="flex space-x-2">
            {/* System Uptime Display */}
            <div className="bg-white px-3 py-2 border border-indigo-100 rounded-lg shadow-sm flex items-center mr-4 card-hover-effect">
              <FaClock className="text-indigo-500 mr-2" />
              <span className="text-gray-700 font-medium">Uptime: {status?.stats?.uptime || "Unknown"}</span>
            </div>
            
            {/* Button: Refresh */}
            <div className="relative group">
              <button
                className="p-2 bg-white text-gray-700 border border-gray-200 rounded-md hover:bg-gray-100 transition-colors shadow-sm card-hover-effect"
                onClick={handleRefreshPage}
              >
                <FaSync className={retryCount > 0 ? "animate-spin" : ""} />
              </button>
              {/* Tooltip */}
              <div className="absolute hidden group-hover:block bg-black text-white text-xs rounded py-1 px-2 -top-8 left-1/2 transform -translate-x-1/2 whitespace-nowrap">
                Refresh
              </div>
            </div>

            {/* Button: Revalidate License */}
            <div className="relative group">
              <button
                className="p-2 bg-white text-gray-700 border border-gray-200 rounded-md hover:bg-gray-100 transition-colors shadow-sm card-hover-effect"
                onClick={handleRevalidateLicense}
              >
                <FaCheckCircle />
              </button>
              {/* Tooltip */}
              <div className="absolute hidden group-hover:block bg-black text-white text-xs rounded py-1 px-2 -top-8 left-1/2 transform -translate-x-1/2 whitespace-nowrap">
                Revalidate License
              </div>
            </div>
          </div>
        </div>

        {/* Test Message Banner */}
        {testMessage && (
          <div className={`${testMessage.toLowerCase().includes('failed') || testMessage.toLowerCase().includes('error') 
                          ? 'bg-red-50 border border-red-200' 
                          : 'bg-green-50 border border-green-200'} 
                          p-3 rounded-md flex items-center justify-between shadow-sm mb-6 page-transition`}>
            <div className={`${testMessage.toLowerCase().includes('failed') || testMessage.toLowerCase().includes('error')
                          ? 'text-red-700' 
                          : 'text-green-700'} flex items-center space-x-2`}>
              {testMessage.toLowerCase().includes('failed') || testMessage.toLowerCase().includes('error') 
                ? <FaExclamationTriangle /> 
                : <FaCheckCircle />}
              <span>{testMessage}</span>
            </div>
            <button 
              onClick={() => setTestMessage(null)} 
              className="text-gray-400 hover:text-gray-600"
            >
              <FaTimes />
            </button>
          </div>
        )}
        
        {/* Key Metrics Summary - Top Row Cards */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
          <div className="bg-gradient-to-br from-indigo-600 to-blue-700 text-white rounded-xl shadow-md p-4 card-hover-effect">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-indigo-100 text-sm font-medium">Tracked Characters</p>
                <p className="text-3xl font-bold">{status?.stats?.characters_count || 0}</p>
              </div>
              <div className="bg-indigo-500 bg-opacity-40 p-3 rounded-lg">
                <FaUserAlt className="h-6 w-6" />
              </div>
            </div>
          </div>
          
          <div className="bg-gradient-to-br from-blue-600 to-indigo-700 text-white rounded-xl shadow-md p-4 card-hover-effect">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-blue-100 text-sm font-medium">Tracked Systems</p>
                <p className="text-3xl font-bold">{status?.stats?.systems_count || 0}</p>
              </div>
              <div className="bg-blue-500 bg-opacity-40 p-3 rounded-lg">
                <FaGlobe className="h-6 w-6" />
              </div>
            </div>
          </div>
          
          <div className="bg-gradient-to-br from-purple-600 to-indigo-700 text-white rounded-xl shadow-md p-4 card-hover-effect">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-purple-100 text-sm font-medium">Total Notifications</p>
                <p className="text-3xl font-bold">{status?.stats?.notifications?.total || 0}</p>
              </div>
              <div className="bg-purple-500 bg-opacity-40 p-3 rounded-lg">
                <FaBell className="h-6 w-6" />
              </div>
            </div>
          </div>
          
          <div className="bg-gradient-to-br from-indigo-700 to-purple-600 text-white rounded-xl shadow-md p-4 card-hover-effect">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-indigo-100 text-sm font-medium">Killmail Stats</p>
                <p className="text-3xl font-bold">{status?.stats?.processing?.kills_notified || 0}</p>
                <p className="text-xs mt-1 text-indigo-200">Processed: {status?.stats?.processing?.kills_processed || 0}</p>
              </div>
              <div className="bg-indigo-500 bg-opacity-40 p-3 rounded-lg">
                <FaChartLine className="h-6 w-6" />
              </div>
            </div>
          </div>
        </div>
        
        {/* Status Summary */}
        <DataCard title="System Status" className="border border-indigo-100 shadow-md rounded-xl card-hover-effect">
          <TwoColumnGrid>
            <StatusCard 
              title="Backend Service" 
              status={status?.services?.backend || "Unknown"} 
              icon={<FaServer className="h-5 w-5" />}
              description="Main notification processing service" 
              className="border border-gray-100 shadow-sm"
            />
            <StatusCard 
              title="License Status" 
              status={status?.license?.status || "Unknown"} 
              icon={<FaHeart className="h-5 w-5" />}
              description={status?.license?.valid 
                ? `License is valid` 
                : "License information"} 
              className="border border-gray-100 shadow-sm"
            />
            <StatusCard 
              title="Notification Service" 
              status={status?.services?.notifications || "Unknown"} 
              icon={<FaBell className="h-5 w-5" />}
              description="Responsible for sending notifications" 
              className="border border-gray-100 shadow-sm"
            />
            <StatusCard 
              title="API Connection" 
              status={status?.services?.api || "Unknown"} 
              icon={<FaCloud className="h-5 w-5" />}
              description="Connection to EVE Online API" 
              className="border border-gray-100 shadow-sm"
            />
          </TwoColumnGrid>
        </DataCard>

        {/* Notification Stats */}
        <DataCard title="Notification Statistics" className="border border-indigo-100 shadow-md rounded-xl card-hover-effect">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
            <div className="bg-blue-50 rounded-lg p-4 border border-blue-100 flex flex-col items-center card-hover-effect">
              <div className="rounded-full bg-blue-100 p-3 mb-2">
                <FaUserAlt className="text-blue-600" />
              </div>
              <p className="text-lg font-bold text-blue-700">{status?.stats?.notifications?.characters || 0}</p>
              <p className="text-sm text-blue-600">Character Notifications</p>
            </div>
            
            <div className="bg-purple-50 rounded-lg p-4 border border-purple-100 flex flex-col items-center card-hover-effect">
              <div className="rounded-full bg-purple-100 p-3 mb-2">
                <FaChartBar className="text-purple-600" />
              </div>
              <p className="text-lg font-bold text-purple-700">{status?.stats?.notifications?.kills || 0}</p>
              <p className="text-sm text-purple-600">Kill Notifications</p>
            </div>
            
            <div className="bg-indigo-50 rounded-lg p-4 border border-indigo-100 flex flex-col items-center card-hover-effect">
              <div className="rounded-full bg-indigo-100 p-3 mb-2">
                <FaGlobe className="text-indigo-600" />
              </div>
              <p className="text-lg font-bold text-indigo-700">{status?.stats?.notifications?.systems || 0}</p>
              <p className="text-sm text-indigo-600">System Notifications</p>
            </div>
          </div>
        </DataCard>

        {/* WebSocket Status */}
        <DataCard title="WebSocket Connection" className="border border-indigo-100 shadow-md rounded-xl card-hover-effect">
          <div className="flex items-center justify-between bg-gray-50 p-4 rounded-lg border border-gray-100">
            <div className="flex items-center space-x-3">
              <div className={`h-3 w-3 rounded-full ${status?.websocket?.connected ? 'bg-green-500 status-indicator online' : 'bg-red-500 status-indicator offline'}`}></div>
              <div>
                <p className="font-medium">
                  {status?.websocket?.connected 
                    ? "Connected to Killstream" 
                    : status?.websocket?.connecting 
                      ? "Connecting..." 
                      : "Disconnected"}
                </p>
                <p className="text-sm text-gray-600">
                  {status?.websocket?.connected 
                    ? `Last message: ${new Date(status?.websocket?.last_message || Date.now()).toLocaleTimeString()}` 
                    : "No recent messages"}
                </p>
              </div>
            </div>
            <div className="bg-white p-2 rounded-lg shadow-sm border border-gray-100">
              <FaNetworkWired className="text-indigo-500 h-5 w-5" />
            </div>
          </div>
        </DataCard>

        {/* Features Configuration */}
        <DataCard title="Configuration" className="border border-indigo-100 shadow-md rounded-xl card-hover-effect">
          <div className="grid gap-4 grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
            {Object.entries(features).map(([key, value]) => {
              // Format the key for display
              const displayName = key
                .replace(/_/g, ' ')
                .replace(/\b\w/g, l => l.toUpperCase())
                .replace('Status Messages', 'Status Messages')
                .replace('Track Kspace', 'Track K-Space');

              return (
                <div key={key} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg border border-gray-100 shadow-sm card-hover-effect">
                  <div className="flex items-center">
                    <FaCog className="text-indigo-500 mr-3" />
                    <span className="text-gray-700">{displayName}</span>
                  </div>
                  <span className={`px-2 py-1 rounded-full text-xs ${
                    value ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'
                  }`}>
                    {value ? 'Enabled' : 'Disabled'}
                  </span>
                </div>
              );
            })}
          </div>
        </DataCard>
      </div>
    </div>
  );
}
