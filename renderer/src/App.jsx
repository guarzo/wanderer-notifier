// src/App.jsx
import React, { useState, useEffect } from "react";
import { BrowserRouter as Router, Routes, Route, Link, Navigate } from "react-router-dom";
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { LocalizationProvider } from '@mui/x-date-pickers';
import { AdapterDateFns } from '@mui/x-date-pickers/AdapterDateFns';
import { enUS } from 'date-fns/locale';
import Dashboard from "./components/Dashboard";
import { FaHome, FaCalendarAlt, FaExclamationTriangle, FaBell } from "react-icons/fa";

// Create a client
const queryClient = new QueryClient();

function App() {
  const [debugEnabled, setDebugEnabled] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    // Fetch status when component mounts
    fetchStatus();

    // Add retry logic with exponential backoff
    const retryInterval = 3000; // Start with 3 seconds
    let retryCount = 0;
    let maxRetries = 5;

    const retryFetch = () => {
      if (retryCount >= maxRetries) {
        setLoading(false);
        setError("Unable to connect to backend after multiple attempts. Please check if the backend server is running.");
        return;
      }

      retryCount++;
      console.log(`Retry attempt ${retryCount} in ${retryInterval}ms...`);
      setTimeout(() => fetchStatus(), retryInterval);
    };

    function fetchStatus() {
      console.log("Attempting to fetch status from API...");
      fetch('/api/debug/status')
        .then(response => {
          if (!response.ok) {
            throw new Error(`HTTP error! Status: ${response.status}`);
          }
          return response.json();
        })
        .then(response => {
          // Handle missing data gracefully with default values
          const data = response.data || {};
          const features = data.features || {};
          setDebugEnabled(features.debug || false);
          setLoading(false);
          setError(null);
        })
        .catch(error => {
          console.error('Error fetching status:', error);
          retryFetch();
        });
    }
  }, []);

  if (loading) {
    return <div className="min-h-screen bg-gradient-to-br from-indigo-100 via-blue-50 to-blue-100 flex items-center justify-center">
      <div className="bg-white p-6 rounded-xl shadow-md flex flex-col items-center">
        <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-indigo-500 mb-4"></div>
        <p className="text-lg text-gray-700">Loading application...</p>
      </div>
    </div>;
  }

  if (error) {
    return <div className="min-h-screen bg-gradient-to-br from-indigo-100 via-blue-50 to-blue-100 flex flex-col items-center justify-center p-4">
      <div className="bg-white border border-red-200 text-red-700 p-6 rounded-xl shadow-md max-w-md">
        <div className="flex items-center mb-4">
          <FaExclamationTriangle className="text-red-500 mr-3 h-6 w-6" />
          <h2 className="text-xl font-semibold text-red-700">Connection Error</h2>
        </div>
        <p className="mb-4 text-gray-700">{error}</p>
        <p className="text-sm text-gray-600 mb-4">
          If you're using the development environment, please ensure:
        </p>
        <ul className="list-disc ml-5 mt-2 text-gray-600 space-y-1">
          <li>Backend server is running with 'make backend'</li>
          <li>Frontend is running with 'make ui.dev'</li>
        </ul>
      </div>
    </div>;
  }

  return (
    <QueryClientProvider client={queryClient}>
      <LocalizationProvider 
        dateAdapter={AdapterDateFns}
        adapterLocale={enUS}
        localeText={{ start: 'Start', end: 'End' }}
      >
        <Router>
          <div className="min-h-screen bg-gradient-to-br from-indigo-100 via-blue-50 to-white">
            <nav className="bg-gradient-to-r from-indigo-800 to-indigo-700 text-white p-4 shadow-md">
              <div className="max-w-7xl mx-auto flex justify-between items-center">
                <div className="flex items-center space-x-2">
                  <FaBell className="text-2xl text-indigo-300" />
                  <div className="text-xl font-bold">Wanderer Notifier</div>
                </div>
              </div>
            </nav>
            
            <Routes>
              <Route path="/" element={<Dashboard />} />
            </Routes>
          </div>
        </Router>
      </LocalizationProvider>
    </QueryClientProvider>
  );
}

export default App;
