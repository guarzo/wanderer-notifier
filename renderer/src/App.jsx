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
  const [activityChartsEnabled, setActivityChartsEnabled] = useState(false);
  const [killChartsEnabled, setKillChartsEnabled] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Fetch status when component mounts
    fetch('/api/debug/status')
      .then(response => response.json())
      .then(response => {
        const features = response.data.features;
        setActivityChartsEnabled(features.activity_charts);
        setKillChartsEnabled(features.kill_charts);
        setLoading(false);
      })
      .catch(error => {
        console.error('Error fetching status:', error);
        setActivityChartsEnabled(false);
        setKillChartsEnabled(false);
        setLoading(false);
      });
  }, []);

  if (loading) {
    return <div className="min-h-screen bg-gradient-to-b from-blue-50 to-blue-100 flex items-center justify-center">
      <p className="text-lg">Loading application...</p>
    </div>;
  }

  // Determine whether to show charts link (if either activity charts or kill charts is enabled)
  const showChartsLink = activityChartsEnabled || killChartsEnabled;

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
                  {activityChartsEnabled && (
                    <Link to="/charts" className="flex items-center space-x-1 hover:text-indigo-300 transition-colors">
                      <FaChartBar />
                      <span>Activity Charts</span>
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
              {/* Only render charts route if activity charts is enabled */}
              <Route 
                path="/charts" 
                element={activityChartsEnabled ? <ChartsDashboard /> : <Navigate to="/" replace />} 
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
            </Routes>
          </div>
        </Router>
      </LocalizationProvider>
    </QueryClientProvider>
  );
}

export default App;
