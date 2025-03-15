import React, { useEffect, useState } from "react";
import {
  FaSync,
  FaCheckCircle,
  FaBell,
  FaPowerOff,
  FaCloud,
  FaHeart
} from "react-icons/fa";

/**
 * Dashboard component for the Wanderer Notifier application
 */
export default function Dashboard() {
  const [status, setStatus] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [testMessage, setTestMessage] = useState(null);

  // On load, fetch the status from /api/status
  useEffect(() => {
    fetchStatus();
  }, []);

  async function fetchStatus() {
    try {
      setLoading(true);
      const response = await fetch("/api/status");
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      console.log("API response:", data); // For debugging
      setStatus(data);
      setError(null);
    } catch (err) {
      console.error("Error fetching status:", err);
      setError("Failed to load dashboard data. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  async function handleRefreshPage() {
    await fetchStatus();
    setTestMessage("Dashboard refreshed");
  }

  async function handleRevalidateLicense() {
    try {
      const response = await fetch("/api/revalidate-license");
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      setTestMessage(data.message || "License revalidated");
      fetchStatus();
    } catch (err) {
      console.error("Error revalidating license:", err);
      setTestMessage("Error revalidating license");
    }
  }

  async function testKillNotification() {
    try {
      const response = await fetch("/api/test-notification");
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      setTestMessage(data.message || "Kill notification sent");
    } catch (err) {
      console.error("Error testing kill notification:", err);
      setTestMessage("Error sending kill notification");
    }
  }

  async function testSystemNotification() {
    try {
      const response = await fetch("/api/test-system-notification");
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      setTestMessage(data.message || "System notification sent");
    } catch (err) {
      console.error("Error testing system notification:", err);
      setTestMessage("Error sending system notification");
    }
  }

  async function testCharacterNotification() {
    try {
      const response = await fetch("/api/test-character-notification");
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      setTestMessage(data.message || "Character notification sent");
    } catch (err) {
      console.error("Error testing character notification:", err);
      setTestMessage("Error sending character notification");
    }
  }

  if (loading && !status) {
    return <div className="flex items-center justify-center h-screen text-gray-700">Loading dashboard...</div>;
  }

  if (error) {
    return <div className="flex items-center justify-center h-screen text-red-600 bg-red-50 p-4 border border-red-200 rounded-md">{error}</div>;
  }

  return (
    <div className="max-w-6xl mx-auto p-4 space-y-6 text-gray-800">
      <h1 className="text-2xl font-bold">Wanderer Notifier Dashboard</h1>
      
      {/* Top Bar / Toolbar */}
      <div className="flex justify-end space-x-2">
        <button 
          className="p-2 text-gray-600 hover:bg-gray-100 rounded-md transition-colors" 
          title="Refresh Data" 
          onClick={handleRefreshPage}
        >
          <FaSync />
        </button>
        <button 
          className="p-2 text-gray-600 hover:bg-gray-100 rounded-md transition-colors" 
          title="Revalidate License" 
          onClick={handleRevalidateLicense}
        >
          <FaCheckCircle />
        </button>
      </div>

      {testMessage && (
        <div className="bg-amber-50 border border-amber-200 p-3 rounded-md flex items-center justify-between">
          <strong className="mr-2">Test Result:</strong>
          {testMessage}
          <button 
            onClick={() => setTestMessage(null)} 
            className="ml-4 text-gray-500 hover:text-gray-700"
          >
            ✕
          </button>
        </div>
      )}

      {/* Notification Statistics */}
      <section className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-white p-4 rounded-md shadow-sm border border-gray-200">
          <h4 className="text-sm font-semibold text-gray-600 mb-1">Total Notifications</h4>
          <p className="text-lg font-medium">{status?.stats?.notifications?.total || 0}</p>
        </div>
        <div className="bg-white p-4 rounded-md shadow-sm border border-gray-200">
          <h4 className="text-sm font-semibold text-gray-600 mb-1">Kill Notifications</h4>
          <p className="text-lg font-medium">{status?.stats?.notifications?.kills || 0}</p>
        </div>
        <div className="bg-white p-4 rounded-md shadow-sm border border-gray-200">
          <h4 className="text-sm font-semibold text-gray-600 mb-1">Character Notifications</h4>
          <p className="text-lg font-medium">{status?.stats?.notifications?.characters || 0}</p>
        </div>
        <div className="bg-white p-4 rounded-md shadow-sm border border-gray-200">
          <h4 className="text-sm font-semibold text-gray-600 mb-1">System Notifications</h4>
          <p className="text-lg font-medium">{status?.stats?.notifications?.systems || 0}</p>
        </div>
      </section>

      {/* License Status */}
      <section className="bg-white p-5 rounded-md shadow-sm border border-gray-200">
        <h3 className="text-lg font-semibold mb-3">License Status</h3>
        <div className="bg-gray-50 p-4 rounded-md border border-gray-200 space-y-2">
          <div>
            <strong>Valid: </strong>
            {status?.license?.valid ? "Yes" : "No"}
          </div>
          {status?.license?.bot_assigned && (
            <div>
              <strong>Bot Assigned: </strong>
              Yes
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
        </div>
      </section>

      {/* Feature Status */}
      <section className="bg-white p-5 rounded-md shadow-sm border border-gray-200">
        <h3 className="text-lg font-semibold mb-3">Feature Status</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="bg-gray-50 p-4 rounded-md border border-gray-200 flex items-center justify-between">
            <span className="font-medium">Kill Notifications</span>
            <div className="flex items-center">
              <span className={status?.features?.enabled?.basic_notifications ? "text-green-600 font-medium" : "text-red-600 font-medium"}>
                {status?.features?.enabled?.basic_notifications ? "Enabled" : "Disabled"}
              </span>
              <button 
                className="ml-2 p-2 text-gray-600 hover:bg-gray-200 rounded-md transition-colors" 
                title="Test Kill Notification" 
                onClick={testKillNotification}
              >
                <FaPowerOff />
              </button>
            </div>
          </div>

          <div className="bg-gray-50 p-4 rounded-md border border-gray-200 flex items-center justify-between">
            <span className="font-medium">System Notifications</span>
            <div className="flex items-center">
              <span className={status?.features?.enabled?.tracked_systems_notifications ? "text-green-600 font-medium" : "text-red-600 font-medium"}>
                {status?.features?.enabled?.tracked_systems_notifications ? "Enabled" : "Disabled"}
              </span>
              <button 
                className="ml-2 p-2 text-gray-600 hover:bg-gray-200 rounded-md transition-colors" 
                title="Test System Notification" 
                onClick={testSystemNotification}
              >
                <FaCloud />
              </button>
            </div>
          </div>

          <div className="bg-gray-50 p-4 rounded-md border border-gray-200 flex items-center justify-between">
            <span className="font-medium">Character Notifications</span>
            <div className="flex items-center">
              <span className={status?.features?.enabled?.tracked_characters_notifications ? "text-green-600 font-medium" : "text-red-600 font-medium"}>
                {status?.features?.enabled?.tracked_characters_notifications ? "Enabled" : "Disabled"}
              </span>
              <button 
                className="ml-2 p-2 text-gray-600 hover:bg-gray-200 rounded-md transition-colors" 
                title="Test Character Notification" 
                onClick={testCharacterNotification}
              >
                <FaHeart />
              </button>
            </div>
          </div>
        </div>
      </section>

      {/* Usage Statistics */}
      {status?.features?.usage && (
        <section className="bg-white p-5 rounded-md shadow-sm border border-gray-200">
          <h3 className="text-lg font-semibold mb-3">Usage Statistics</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="bg-gray-50 p-4 rounded-md border border-gray-200">
              <h4 className="text-sm font-semibold text-gray-600 mb-2">Tracked Systems</h4>
              <p className="mb-2">
                {status.features.usage.tracked_systems.current}
                {status.features.usage.tracked_systems.limit && 
                  ` / ${status.features.usage.tracked_systems.limit}`
                }
              </p>
              {status.features.usage.tracked_systems.percentage && (
                <div className="w-full bg-gray-200 rounded-full h-2 overflow-hidden">
                  <div 
                    className="bg-green-500 h-full rounded-full" 
                    style={{width: `${status.features.usage.tracked_systems.percentage}%`}}
                  ></div>
                </div>
              )}
            </div>
            <div className="bg-gray-50 p-4 rounded-md border border-gray-200">
              <h4 className="text-sm font-semibold text-gray-600 mb-2">Tracked Characters</h4>
              <p className="mb-2">
                {status.features.usage.tracked_characters.current}
                {status.features.usage.tracked_characters.limit && 
                  ` / ${status.features.usage.tracked_characters.limit}`
                }
              </p>
              {status.features.usage.tracked_characters.percentage && (
                <div className="w-full bg-gray-200 rounded-full h-2 overflow-hidden">
                  <div 
                    className="bg-green-500 h-full rounded-full" 
                    style={{width: `${status.features.usage.tracked_characters.percentage}%`}}
                  ></div>
                </div>
              )}
            </div>
          </div>
        </section>
      )}

      {/* System Status */}
      <section className="bg-white p-5 rounded-md shadow-sm border border-gray-200">
        <h3 className="text-lg font-semibold mb-3">System Status</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="bg-gray-50 p-4 rounded-md border border-gray-200">
            <h4 className="text-sm font-semibold text-gray-600 mb-1">Uptime</h4>
            <p>{status?.stats?.uptime || "Unknown"}</p>
          </div>
          <div className="bg-gray-50 p-4 rounded-md border border-gray-200">
            <h4 className="text-sm font-semibold text-gray-600 mb-1">WebSocket</h4>
            <p>
              {status?.stats?.websocket?.connected ? 
                <span className="text-green-600 font-medium">Connected</span> : 
                <span className="text-red-600 font-medium">Disconnected</span>
              }
            </p>
          </div>
          <div className="bg-gray-50 p-4 rounded-md border border-gray-200">
            <h4 className="text-sm font-semibold text-gray-600 mb-1">Last Message</h4>
            <p>{status?.stats?.websocket?.last_message ? 
              new Date(status.stats.websocket.last_message).toLocaleTimeString() : 
              "Never"
            }</p>
          </div>
          <div className="bg-gray-50 p-4 rounded-md border border-gray-200">
            <h4 className="text-sm font-semibold text-gray-600 mb-1">Reconnects</h4>
            <p>{status?.stats?.websocket?.reconnects || 0}</p>
          </div>
        </div>
      </section>
    </div>
  );
}
