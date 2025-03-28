// src/App.jsx
import React, { useState, useEffect } from "react";
import { BrowserRouter as Router, Routes, Route, Link, Navigate } from "react-router-dom";
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { LocalizationProvider } from '@mui/x-date-pickers';
import { AdapterDateFns } from '@mui/x-date-pickers/AdapterDateFns';
import { enUS } from 'date-fns/locale';
import Dashboard from "./components/Dashboard";
import ChartsDashboard from "./components/ChartsDashboard";
import KillComparison from "./components/KillComparison";
import SchedulerDashboard from "./components/SchedulerDashboard";
import { FaChartBar, FaHome, FaSkullCrossbones, FaCalendarAlt } from "react-icons/fa";

// Create a client
const queryClient = new QueryClient();

function App() {
  const [corpToolsEnabled, setCorpToolsEnabled] = useState(false);
  const [mapChartsEnabled, setMapChartsEnabled] = useState(false);
  const [killChartsEnabled, setKillChartsEnabled] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Fetch configuration when component mounts
    fetch('/charts/config')
      .then(response => response.json())
      .then(data => {
        setCorpToolsEnabled(data.corp_tools_enabled);
        setMapChartsEnabled(data.map_tools_enabled);
        setKillChartsEnabled(data.kill_charts_enabled);
        setLoading(false);
      })
      .catch(error => {
        console.error('Error fetching chart config:', error);
        setCorpToolsEnabled(false);
        setMapChartsEnabled(false);
        setKillChartsEnabled(false);
        setLoading(false);
      });
  }, []);

  if (loading) {
    return <div className="min-h-screen bg-gradient-to-b from-blue-50 to-blue-100 flex items-center justify-center">
      <p className="text-lg">Loading application...</p>
    </div>;
  }

  // Determine whether to show charts link (if either map charts or kill charts is enabled)
  const showChartsLink = mapChartsEnabled || killChartsEnabled;

  return (
    <QueryClientProvider client={queryClient}>
      <LocalizationProvider 
        dateAdapter={AdapterDateFns}
        adapterLocale={enUS}
        localeText={{ start: 'Start', end: 'End' }}
      >
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
                  {showChartsLink && (
                    <Link to="/charts" className="flex items-center space-x-1 hover:text-indigo-300 transition-colors">
                      <FaChartBar />
                      <span>Charts</span>
                    </Link>
                  )}
                  {killChartsEnabled && (
                    <Link to="/kill-comparison" className="flex items-center space-x-1 hover:text-indigo-300 transition-colors">
                      <FaSkullCrossbones />
                      <span>Kill Analysis</span>
                    </Link>
                  )}
                  
                  <Link to="/schedulers" className="flex items-center space-x-1 hover:text-indigo-300 transition-colors">
                    <FaCalendarAlt />
                    <span>Schedulers</span>
                  </Link>
                </div>
              </div>
            </nav>
            
            <Routes>
              <Route path="/" element={<Dashboard />} />
              {/* Only render charts route if at least one chart type is enabled, otherwise redirect to home */}
              <Route 
                path="/charts" 
                element={showChartsLink ? <ChartsDashboard /> : <Navigate to="/" replace />} 
              />
              {/* Kill comparison route */}
              <Route 
                path="/kill-comparison" 
                element={killChartsEnabled ? <KillComparison /> : <Navigate to="/" replace />} 
              />
              {/* Scheduler dashboard route */}
              <Route 
                path="/schedulers" 
                element={<SchedulerDashboard />} 
              />
              
              {/* Legacy routes for backward compatibility */}
              <Route path="/corp-tools" element={<Navigate to="/" replace />} />
              <Route path="/map-tools" element={<Navigate to="/" replace />} />
              <Route path="/charts-dashboard" element={<Navigate to="/charts" replace />} />
              <Route path="/debug" element={<Navigate to="/" replace />} />
            </Routes>
          </div>
        </Router>
      </LocalizationProvider>
    </QueryClientProvider>
  );
}

export default App;
