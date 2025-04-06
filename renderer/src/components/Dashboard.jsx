// src/components/Dashboard.jsx
import React, { useEffect, useState } from "react";
import {
  FaSync,
  FaCheckCircle,
  FaPowerOff,
  FaCloud,
  FaHeart,
  FaTimes,
  FaCircleNotch,
  FaExclamationTriangle,
  FaBell,
  FaSkullCrossbones,
  FaChartBar
} from "react-icons/fa";
import { Link } from "react-router-dom";

export default function Dashboard() {
  const [status, setStatus] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [testMessage, setTestMessage] = useState(null);
  const [dbStats, setDbStats] = useState(null);

  // On mount, fetch dashboard status
  useEffect(() => {
    fetchStatus();
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
      const data = await response.json();
      console.log("Status data received:", data);
      setStatus(data.data);
      setError(null);

      // Always fetch database stats
      await fetchDbStats();
    } catch (err) {
      console.error("Error fetching status:", err);
      setError("Failed to load dashboard data. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  // Fetch database statistics
  async function fetchDbStats() {
    try {
      console.log("Fetching database statistics...");
      const response = await fetch("/api/debug/db-stats");
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      console.log("Database stats received:", data);
      if (data.status === "ok") {
        setDbStats(data.data);
      } else {
        console.warn("Failed to get database stats:", data.message);
      }
    } catch (err) {
      console.error("Error fetching database stats:", err);
      // We don't set the main error state here to avoid blocking the entire dashboard
    }
  }

  // Toolbar actions
  async function handleRefreshPage() {
    await fetchStatus();
    setTestMessage("Dashboard refreshed!");
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
    } catch (err) {
      console.error("Error revalidating license:", err);
      setTestMessage("Error revalidating license");
    }
  }

  // Test notification actions
  async function testKillNotification() {
    try {
      console.log("Sending test kill notification request...");
      const response = await fetch("/api/notifications/test", {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ type: 'kill' })
      });
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      console.log("Kill notification response:", data);
      setTestMessage(data.message || "Kill notification sent!");
    } catch (err) {
      console.error("Error sending kill notification:", err);
      setTestMessage("Error sending kill notification");
    }
  }

  async function testSystemNotification() {
    try {
      console.log("Sending test system notification request...");
      const response = await fetch("/api/notifications/test", {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ type: 'system' })
      });
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      console.log("System notification response:", data);
      setTestMessage(data.message || "System notification sent!");
    } catch (err) {
      console.error("Error sending system notification:", err);
      setTestMessage("Error sending system notification");
    }
  }

  async function testCharacterNotification() {
    try {
      console.log("Sending test character notification request...");
      const response = await fetch("/api/notifications/test", {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ type: 'character' })
      });
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      console.log("Character notification response:", data);
      setTestMessage(data.message || "Character notification sent!");
    } catch (err) {
      console.error("Error sending character notification:", err);
      setTestMessage("Error sending character notification");
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
        <div className="flex items-center space-x-3 bg-red-50 border border-red-200 text-red-600 p-4 rounded-md">
          <FaExclamationTriangle className="text-red-600" />
          <span>{error}</span>
        </div>
      </div>
    );
  }

  /* -------------------------
   * Main Dashboard UI
   * ------------------------*/
  return (
    <div className="min-h-screen bg-gradient-to-b from-indigo-50 to-white">
      {/* Outer container with spacing */}
      <div className="max-w-7xl mx-auto px-4 py-8 sm:px-6 lg:px-8 space-y-8">
        {/* Title & Toolbar */}
        <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between">
          <h1 className="flex items-center text-2xl font-bold text-indigo-800 space-x-2 mb-4 sm:mb-0">
            <FaBell />
            <span>Wanderer Notifier Dashboard</span>
          </h1>
          <div className="flex space-x-2">
            {/* Button: Refresh */}
            <div className="relative group">
              <button
                className="p-2 bg-white text-gray-700 border border-gray-200 rounded-md hover:bg-gray-100 transition-colors"
                onClick={handleRefreshPage}
              >
                <FaSync />
              </button>
              {/* Tooltip */}
              <div className="absolute hidden group-hover:block bg-black text-white text-xs rounded py-1 px-2 -top-8 left-1/2 transform -translate-x-1/2 whitespace-nowrap">
                Refresh
              </div>
            </div>

            {/* Button: Revalidate License */}
            <div className="relative group">
              <button
                className="p-2 bg-white text-gray-700 border border-gray-200 rounded-md hover:bg-gray-100 transition-colors"
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
                          p-3 rounded-md flex items-center justify-between`}>
            <div className={`${testMessage.toLowerCase().includes('failed') || testMessage.toLowerCase().includes('error')
                           ? 'text-red-700' 
                           : 'text-green-700'} flex items-center space-x-2`}>
              {testMessage.toLowerCase().includes('failed') || testMessage.toLowerCase().includes('error') 
               ? <FaExclamationTriangle /> 
               : <FaCheckCircle />}
              <span className="font-medium">{testMessage}</span>
            </div>
            <button
              onClick={() => setTestMessage(null)}
              className="ml-4 text-gray-500 hover:text-gray-700"
            >
              <FaTimes />
            </button>
          </div>
        )}

        {/* Notification Statistics */}
        <section>
          <h2 className="text-lg font-semibold text-gray-800 mb-4 flex items-center space-x-2">
            <FaSkullCrossbones className="text-sky-600" />
            <span>Notification Statistics</span>
          </h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            {/* Total Notifications */}
            <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100">
              <h4 className="text-sm font-semibold text-gray-600 mb-1">
                Total Notifications
              </h4>
              <p className="text-2xl font-bold text-gray-700">
                {status?.stats?.notifications?.total || 0}
              </p>
            </div>

            {/* Kill Notifications */}
            <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100">
              <h4 className="text-sm font-semibold text-gray-600 mb-1">
                Kill Notifications
              </h4>
              <p className="text-2xl font-bold text-gray-700">
                {status?.stats?.notifications?.kills || 0}
              </p>
            </div>

            {/* Character Notifications */}
            <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100">
              <h4 className="text-sm font-semibold text-gray-600 mb-1">
                Character Notifications
              </h4>
              <p className="text-2xl font-bold text-gray-700">
                {status?.stats?.notifications?.characters || 0}
              </p>
            </div>

            {/* System Notifications */}
            <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100">
              <h4 className="text-sm font-semibold text-gray-600 mb-1">
                System Notifications
              </h4>
              <p className="text-2xl font-bold text-gray-700">
                {status?.stats?.notifications?.systems || 0}
              </p>
            </div>
          </div>
        </section>

        {/* Database Statistics */}
        {dbStats && (
          <section>
            <h2 className="text-lg font-semibold text-gray-800 mb-4 flex items-center space-x-2">
              <FaChartBar className="text-purple-600" />
              <span>Database Statistics</span>
            </h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {/* Total Tracked Characters */}
              <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100">
                <h4 className="text-sm font-semibold text-gray-600 mb-1">
                  Tracked Characters in Database
                </h4>
                <p className="text-2xl font-bold text-gray-700">
                  {dbStats?.killmail?.tracked_characters || 0}
                </p>
              </div>

              {/* Total Killmails */}
              <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100">
                <h4 className="text-sm font-semibold text-gray-600 mb-1">
                  Total Killmails Stored
                </h4>
                <p className="text-2xl font-bold text-gray-700">
                  {dbStats?.killmail?.total_kills || 0}
                </p>
              </div>

              {/* Database Health */}
              <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100">
                <h4 className="text-sm font-semibold text-gray-600 mb-1">
                  Database Connection
                </h4>
                {dbStats?.db_health ? (
                  <div>
                    <p className="flex items-center mt-1">
                      {dbStats.db_health.status === "connected" ? (
                        <>
                          <FaCheckCircle className="text-green-500 mr-2" />
                          <span className="bg-green-100 text-green-800 text-sm px-2 py-1 rounded">
                            Connected
                          </span>
                        </>
                      ) : (
                        <>
                          <FaTimes className="text-red-500 mr-2" />
                          <span className="bg-red-100 text-red-800 text-sm px-2 py-1 rounded">
                            Error
                          </span>
                        </>
                      )}
                    </p>
                    {dbStats.db_health.ping_ms && (
                      <p className="text-sm text-gray-500 mt-1">
                        Ping: {dbStats.db_health.ping_ms}ms
                      </p>
                    )}
                  </div>
                ) : (
                  <p className="flex items-center mt-1">
                    <FaCircleNotch className="text-gray-400 mr-2 animate-spin" />
                    <span className="text-gray-500">Checking...</span>
                  </p>
                )}
              </div>
            </div>
          </section>
        )}

        {/* License Status */}
        <section>
          <h2 className="text-lg font-semibold text-gray-800 mb-4 flex items-center space-x-2">
            <FaCheckCircle className="text-green-600" />
            <span>License Status</span>
          </h2>
          <div className="bg-white p-5 rounded-md shadow-sm border border-gray-100">
            <div className="bg-gray-50 p-4 rounded-md border border-gray-200 space-y-2">
              <div>
                <strong>Valid: </strong>
                {status?.license?.valid ? "Yes" : "No"}
              </div>
              {status?.license?.bot_assigned && (
                <div>
                  <strong>Bot Assigned: </strong>Yes
                </div>
              )}
              {status?.license?.details && (
                <div>
                  <strong>License Name: </strong>
                  {status.license.details.license_name}
                </div>
              )}
              {status?.license?.error_message && (
                <div className="text-red-600">
                  <strong>Error: </strong>
                  {status.license.error_message}
                </div>
              )}
              <div className="mt-3 text-sm text-gray-500">
                <p>
                  {status?.license?.valid 
                    ? "Your license is active and valid."
                    : "Your license is not valid. Please check your license key in the configuration."}
                </p>
                {!status?.license?.valid && (
                  <p className="mt-1">
                    Try clicking the "Revalidate License" button in the top-right corner to retry validation.
                  </p>
                )}
              </div>
            </div>
          </div>
        </section>

        {/* Feature Status */}
        <section>
          <h2 className="text-lg font-semibold text-gray-800 mb-4 flex items-center space-x-2">
            <FaBell className="text-pink-500" />
            <span>Feature Status</span>
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {/* Kill Notifications */}
            <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100 flex items-center justify-between">
              <span className="font-medium text-gray-700">Kill Notifications</span>
              <div className="flex items-center space-x-2">
                <span
                  className={
                    status?.features?.kill_notifications_enabled
                      ? "bg-green-100 text-green-800 text-sm px-2 py-1 rounded"
                      : "bg-red-100 text-red-800 text-sm px-2 py-1 rounded"
                  }
                >
                  {status?.features?.kill_notifications_enabled
                    ? "Enabled"
                    : "Disabled"}
                </span>
                {/* Icon button */}
                <button
                  className="relative group p-2 text-gray-600 hover:bg-gray-200 rounded-md transition-colors"
                  onClick={testKillNotification}
                >
                  <FaSkullCrossbones />
                  {/* Tooltip */}
                  <div className="absolute hidden group-hover:block bg-black text-white text-xs rounded py-1 px-2 bottom-full mb-1 left-1/2 transform -translate-x-1/2 whitespace-nowrap">
                    Test Kill Notification
                  </div>
                </button>
              </div>
            </div>

            {/* System Notifications */}
            <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100 flex items-center justify-between">
              <span className="font-medium text-gray-700">System Notifications</span>
              <div className="flex items-center space-x-2">
                <span
                  className={
                    status?.features?.system_notifications_enabled
                      ? "bg-green-100 text-green-800 text-sm px-2 py-1 rounded"
                      : "bg-red-100 text-red-800 text-sm px-2 py-1 rounded"
                  }
                >
                  {status?.features?.system_notifications_enabled
                    ? "Enabled"
                    : "Disabled"}
                </span>
                <button
                  className="relative group p-2 text-gray-600 hover:bg-gray-200 rounded-md transition-colors"
                  onClick={testSystemNotification}
                >
                  <FaCloud />
                  <div className="absolute hidden group-hover:block bg-black text-white text-xs rounded py-1 px-2 bottom-full mb-1 left-1/2 transform -translate-x-1/2 whitespace-nowrap">
                    Test System Notification
                  </div>
                </button>
              </div>
            </div>

            {/* Character Notifications */}
            <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100 flex items-center justify-between">
              <span className="font-medium text-gray-700">Character Notifications</span>
              <div className="flex items-center space-x-2">
                <span
                  className={
                    status?.features?.character_notifications_enabled
                      ? "bg-green-100 text-green-800 text-sm px-2 py-1 rounded"
                      : "bg-red-100 text-red-800 text-sm px-2 py-1 rounded"
                  }
                >
                  {status?.features?.character_notifications_enabled
                    ? "Enabled"
                    : "Disabled"}
                </span>
                <button
                  className="relative group p-2 text-gray-600 hover:bg-gray-200 rounded-md transition-colors"
                  onClick={testCharacterNotification}
                >
                  <FaHeart />
                  <div className="absolute hidden group-hover:block bg-black text-white text-xs rounded py-1 px-2 bottom-full mb-1 left-1/2 transform -translate-x-1/2 whitespace-nowrap">
                    Test Character Notification
                  </div>
                </button>
              </div>
            </div>
            
            {/* Map Charts */}
            {status?.features?.map_charts && (
              <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100 flex items-center justify-between">
                <span className="font-medium text-gray-700">Map Charts</span>
                <div className="flex items-center space-x-2">
                  <span className="bg-green-100 text-green-800 text-sm px-2 py-1 rounded">
                    Enabled
                  </span>
                  <Link
                    to="/charts"
                    className="relative group p-2 text-gray-600 hover:bg-gray-200 rounded-md transition-colors"
                  >
                    <FaChartBar />
                    <div className="absolute hidden group-hover:block bg-black text-white text-xs rounded py-1 px-2 bottom-full mb-1 left-1/2 transform -translate-x-1/2 whitespace-nowrap">
                      View Map Charts
                    </div>
                  </Link>
                </div>
              </div>
            )}
            
            {/* Kill Charts */}
            {status?.features?.kill_charts && (
              <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100 flex items-center justify-between">
                <span className="font-medium text-gray-700">Kill Charts</span>
                <div className="flex items-center space-x-2">
                  <span className="bg-green-100 text-green-800 text-sm px-2 py-1 rounded">
                    Enabled
                  </span>
                  <Link
                    to="/charts"
                    className="relative group p-2 text-gray-600 hover:bg-gray-200 rounded-md transition-colors"
                  >
                    <FaChartBar />
                    <div className="absolute hidden group-hover:block bg-black text-white text-xs rounded py-1 px-2 bottom-full mb-1 left-1/2 transform -translate-x-1/2 whitespace-nowrap">
                      View Kill Charts
                    </div>
                  </Link>
                </div>
              </div>
            )}
            
            {/* Add any other features here */}
          </div>
        </section>

        {/* Usage Statistics */}
        {status?.features?.usage && (
          <section>
            <h2 className="text-lg font-semibold text-gray-800 mb-4 flex items-center space-x-2">
              <FaSync className="text-yellow-500" />
              <span>Usage Statistics</span>
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {/* Tracked Systems */}
              <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100">
                <h4 className="text-sm font-semibold text-gray-600 mb-2">
                  Tracked Systems
                </h4>
                <p className="mb-2 text-gray-800">
                  {status.features.usage.tracked_systems.current}
                </p>
              </div>

              {/* Tracked Characters */}
              <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100">
                <h4 className="text-sm font-semibold text-gray-600 mb-2">
                  Tracked Characters
                </h4>
                <p className="mb-2 text-gray-800">
                  {status.features.usage.tracked_characters.current}
                </p>
              </div>
            </div>
          </section>
        )}

        {/* System Status */}
        <section>
          <h2 className="text-lg font-semibold text-gray-800 mb-4 flex items-center space-x-2">
            <FaPowerOff className="text-purple-500" />
            <span>System Status</span>
          </h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            {/* Uptime */}
            <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100">
              <h4 className="text-sm font-semibold text-gray-600 mb-1">Uptime</h4>
              <p className="text-gray-800">{status?.stats?.uptime || "Unknown"}</p>
            </div>
            {/* WebSocket */}
            <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100">
              <h4 className="text-sm font-semibold text-gray-600 mb-1">WebSocket</h4>
              <p>
                {status?.stats?.websocket?.connected ? (
                  <span className="bg-green-100 text-green-800 text-sm px-2 py-1 rounded">
                    Connected
                  </span>
                ) : (
                  <span className="bg-red-100 text-red-800 text-sm px-2 py-1 rounded">
                    Disconnected
                  </span>
                )}
              </p>
            </div>
            {/* Last Message */}
            <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100">
              <h4 className="text-sm font-semibold text-gray-600 mb-1">Last Message</h4>
              <p className="text-gray-800">
                {status?.stats?.websocket?.last_message
                  ? new Date(status.stats.websocket.last_message).toLocaleTimeString()
                  : "Never"}
              </p>
            </div>
            {/* Reconnects */}
            <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100">
              <h4 className="text-sm font-semibold text-gray-600 mb-1">Reconnects</h4>
              <p className="text-gray-800">
                {status?.stats?.websocket?.reconnects || 0}
              </p>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}
