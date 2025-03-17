import React, { useState, useEffect } from 'react';
import ActivityTable from './ActivityTable';
import { FaExclamationTriangle, FaMap } from 'react-icons/fa';

function MapToolsDashboard() {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

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

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="mb-8 text-center">
        <h1 className="text-3xl font-bold text-gray-800 mb-2">Map Tools Dashboard</h1>
        <p className="text-gray-600">
          View and manage EVE Online map-related analytics and tools
        </p>
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
        <div className="grid grid-cols-1 gap-6">
          <ActivityTable />
        </div>
      )}
    </div>
  );
}

export default MapToolsDashboard; 