// src/App.jsx
import React, { useState, useEffect } from "react";
import { BrowserRouter as Router, Routes, Route, Link, Navigate } from "react-router-dom";
import Dashboard from "./components/Dashboard";
import ChartDashboard from "./components/ChartDashboard";
import MapToolsDashboard from "./components/MapToolsDashboard";
import DebugDashboard from "./components/DebugDashboard";
import { FaChartBar, FaHome, FaMap, FaBug } from "react-icons/fa";

function App() {
  const [corpToolsEnabled, setCorpToolsEnabled] = useState(false);
  const [mapToolsEnabled, setMapToolsEnabled] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Fetch configuration when component mounts
    fetch('/charts/config')
      .then(response => response.json())
      .then(data => {
        setCorpToolsEnabled(data.corp_tools_enabled);
        setMapToolsEnabled(data.map_tools_enabled);
        setLoading(false);
      })
      .catch(error => {
        console.error('Error fetching config:', error);
        setCorpToolsEnabled(false);
        setMapToolsEnabled(false);
        setLoading(false);
      });
  }, []);

  if (loading) {
    return <div className="min-h-screen bg-gradient-to-b from-blue-50 to-blue-100 flex items-center justify-center">
      <p className="text-lg">Loading application...</p>
    </div>;
  }

  return (
    <Router>
      <div className="min-h-screen bg-gradient-to-b from-blue-50 to-blue-100">
        <nav className="bg-gray-800 text-white p-4">
          <div className="max-w-7xl mx-auto flex justify-between items-center">
            <div className="text-xl font-bold">Wanderer Notifier</div>
            <div className="flex space-x-4">
              <Link to="/" className="flex items-center space-x-1 hover:text-indigo-300 transition-colors">
                <FaHome />
                <span>Home</span>
              </Link>
              <Link to="/debug" className="flex items-center space-x-1 hover:text-indigo-300 transition-colors">
                <FaBug />
                <span>Debug</span>
              </Link>
            </div>
          </div>
        </nav>
        
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/debug" element={<DebugDashboard />} />
          
          {/* Legacy routes for backward compatibility */}
          <Route path="/corp-tools" element={<Navigate to="/debug" replace />} />
          <Route path="/map-tools" element={<Navigate to="/debug" replace />} />
          <Route path="/charts-dashboard" element={<Navigate to="/debug" replace />} />
        </Routes>
      </div>
    </Router>
  );
}

export default App;
