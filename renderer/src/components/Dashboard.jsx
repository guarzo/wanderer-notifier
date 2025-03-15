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
  FaSkullCrossbones
} from "react-icons/fa";

export default function Dashboard() {
  const [status, setStatus] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [testMessage, setTestMessage] = useState(null);

  // On mount, fetch dashboard status
  useEffect(() => {
    fetchStatus();
  }, []);

  // Fetch the status data
  async function fetchStatus() {
    try {
      setLoading(true);
      const response = await fetch("/api/status");
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      setStatus(data);
      setError(null);
    } catch (err) {
      console.error("Error fetching status:", err);
      setError("Failed to load dashboard data. Please try again.");
    } finally {
      setLoading(false);
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
      setTestMessage(data.message || "License revalidated!");
      fetchStatus();
    } catch (err) {
      console.error("Error revalidating license:", err);
      setTestMessage("Error revalidating license");
    }
  }

  // Test notification actions
  async function testKillNotification() {
    try {
      const response = await fetch("/api/test-notification");
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      setTestMessage(data.message || "Kill notification sent!");
    } catch (err) {
      console.error("Error sending kill notification:", err);
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
      setTestMessage(data.message || "System notification sent!");
    } catch (err) {
      console.error("Error sending system notification:", err);
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
          <div className="bg-green-50 border border-green-200 p-3 rounded-md flex items-center justify-between">
            <div className="text-green-700 flex items-center space-x-2">
              <FaCheckCircle />
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
                    status?.features?.enabled?.basic_notifications
                      ? "bg-green-100 text-green-800 text-sm px-2 py-1 rounded"
                      : "bg-red-100 text-red-800 text-sm px-2 py-1 rounded"
                  }
                >
                  {status?.features?.enabled?.basic_notifications
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
                    status?.features?.enabled?.tracked_systems_notifications
                      ? "bg-green-100 text-green-800 text-sm px-2 py-1 rounded"
                      : "bg-red-100 text-red-800 text-sm px-2 py-1 rounded"
                  }
                >
                  {status?.features?.enabled?.tracked_systems_notifications
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
                    status?.features?.enabled?.tracked_characters_notifications
                      ? "bg-green-100 text-green-800 text-sm px-2 py-1 rounded"
                      : "bg-red-100 text-red-800 text-sm px-2 py-1 rounded"
                  }
                >
                  {status?.features?.enabled?.tracked_characters_notifications
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
                  {status.features.usage.tracked_systems.limit &&
                    ` / ${status.features.usage.tracked_systems.limit}`}
                </p>
                {status.features.usage.tracked_systems.percentage && (
                  <div className="w-full bg-gray-200 rounded-full h-2 overflow-hidden">
                    <div
                      className="bg-green-500 h-full rounded-full"
                      style={{
                        width: `${status.features.usage.tracked_systems.percentage}%`
                      }}
                    />
                  </div>
                )}
              </div>

              {/* Tracked Characters */}
              <div className="bg-white p-4 rounded-md shadow-sm border border-gray-100">
                <h4 className="text-sm font-semibold text-gray-600 mb-2">
                  Tracked Characters
                </h4>
                <p className="mb-2 text-gray-800">
                  {status.features.usage.tracked_characters.current}
                  {status.features.usage.tracked_characters.limit &&
                    ` / ${status.features.usage.tracked_characters.limit}`}
                </p>
                {status.features.usage.tracked_characters.percentage && (
                  <div className="w-full bg-gray-200 rounded-full h-2 overflow-hidden">
                    <div
                      className="bg-green-500 h-full rounded-full"
                      style={{
                        width: `${status.features.usage.tracked_characters.percentage}%`
                      }}
                    />
                  </div>
                )}
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
