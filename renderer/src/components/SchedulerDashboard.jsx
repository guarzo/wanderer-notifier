import React, { useState, useEffect } from 'react';
import SchedulerCard from './SchedulerCard';
import { 
  FaCalendarAlt, 
  FaCircleNotch, 
  FaExclamationTriangle, 
  FaSync, 
  FaPlayCircle,
  FaFilter,
  FaCheck,
  FaTimes
} from 'react-icons/fa';

// Dashboard component for displaying all scheduler information
const SchedulerDashboard = () => {
  const [schedulers, setSchedulers] = useState([]);
  const [summary, setSummary] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [refreshing, setRefreshing] = useState(false);
  const [filter, setFilter] = useState('all'); // all, enabled, disabled, interval, time

  // Fetch scheduler data on component mount and when manual refresh is triggered
  useEffect(() => {
    fetchSchedulers();
  }, []);

  // Function to fetch scheduler data from the API
  const fetchSchedulers = async () => {
    try {
      setRefreshing(true);
      console.log('Fetching scheduler data...');
      const response = await fetch('/api/debug/scheduler-stats');
      
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      
      const data = await response.json();
      console.log('Scheduler data received:', data);
      
      if (!data.schedulers || !Array.isArray(data.schedulers)) {
        console.warn('No schedulers array in response:', data);
        setSchedulers([]);
        setSummary(data.summary || {
          total: 0,
          enabled: 0,
          disabled: 0,
          by_type: { interval: 0, time: 0 }
        });
        setError("No scheduler data available");
      } else {
        setSchedulers(data.schedulers);
        setSummary(data.summary);
        setError(null);
      }
    } catch (err) {
      console.error('Error fetching scheduler data:', err);
      setError(`Failed to load scheduler data: ${err.message}`);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  // Handle manual refresh button click
  const handleRefresh = () => {
    fetchSchedulers();
  };

  // Handle run all schedulers button click
  const handleRunAll = async () => {
    try {
      setRefreshing(true);
      const response = await fetch('/api/debug/schedulers/execute', {
        method: 'POST',
      });
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      
      // After trigger execution, refresh data after a small delay to allow processing
      setTimeout(() => {
        fetchSchedulers();
      }, 1000);
    } catch (err) {
      console.error('Error executing schedulers:', err);
      setError(`Failed to execute schedulers: ${err.message}`);
      setRefreshing(false);
    }
  };

  // Filter schedulers based on selected filter
  const filteredSchedulers = () => {
    if (!schedulers || schedulers.length === 0) return [];
    
    switch (filter) {
      case 'enabled':
        return schedulers.filter(s => s.enabled);
      case 'disabled':
        return schedulers.filter(s => !s.enabled);
      case 'interval':
        return schedulers.filter(s => s.type === 'interval');
      case 'time':
        return schedulers.filter(s => s.type === 'time');
      default:
        return schedulers;
    }
  };

  // Loading state
  if (loading && !schedulers.length) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <FaCircleNotch className="h-10 w-10 text-indigo-600 animate-spin" />
      </div>
    );
  }

  // Error state
  if (error && !schedulers.length) {
    return (
      <div className="flex items-center justify-center min-h-screen px-4">
        <div className="flex items-center space-x-3 bg-red-50 border border-red-200 text-red-600 p-4 rounded-md">
          <FaExclamationTriangle className="text-red-600" />
          <span>{error}</span>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-indigo-50 to-white">
      <div className="max-w-7xl mx-auto px-4 py-8 sm:px-6 lg:px-8 space-y-6">
        {/* Header */}
        <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between mb-6">
          <h1 className="flex items-center text-2xl font-bold text-indigo-800 space-x-2 mb-4 sm:mb-0">
            <FaCalendarAlt />
            <span>Scheduler Dashboard</span>
          </h1>
          <div className="flex space-x-2">
            {/* Refresh button */}
            <button
              className="flex items-center px-3 py-2 bg-white text-gray-700 border border-gray-200 rounded-md hover:bg-gray-100 transition-colors"
              onClick={handleRefresh}
              disabled={refreshing}
            >
              {refreshing ? (
                <FaCircleNotch className="mr-2 animate-spin" />
              ) : (
                <FaSync className="mr-2" />
              )}
              <span>Refresh</span>
            </button>
            
            {/* Run all button */}
            <button
              className="flex items-center px-3 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition-colors"
              onClick={handleRunAll}
              disabled={refreshing}
            >
              <FaPlayCircle className="mr-2" />
              <span>Run All</span>
            </button>
          </div>
        </div>

        {/* Error message if present */}
        {error && (
          <div className="bg-red-50 border border-red-200 text-red-600 p-4 rounded-md flex items-center mb-6">
            <FaExclamationTriangle className="mr-2" />
            <span>{error}</span>
          </div>
        )}

        {/* Summary statistics */}
        {summary && (
          <div className="bg-white p-4 rounded-lg shadow-sm border border-gray-100 mb-6">
            <h2 className="text-lg font-semibold text-gray-800 mb-4">Scheduler Summary</h2>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div className="bg-indigo-50 p-3 rounded-md">
                <div className="text-sm text-indigo-800 mb-1">Total Schedulers</div>
                <div className="text-2xl font-bold text-indigo-700">{summary.total}</div>
              </div>
              <div className="bg-green-50 p-3 rounded-md">
                <div className="text-sm text-green-800 mb-1">Enabled</div>
                <div className="text-2xl font-bold text-green-700">{summary.enabled}</div>
              </div>
              <div className="bg-gray-50 p-3 rounded-md">
                <div className="text-sm text-gray-800 mb-1">Disabled</div>
                <div className="text-2xl font-bold text-gray-700">{summary.disabled}</div>
              </div>
              <div className="bg-purple-50 p-3 rounded-md">
                <div className="text-sm text-purple-800 mb-1">Next execution</div>
                <div className="text-lg font-bold text-purple-700">
                  {schedulers.length > 0 && schedulers.some(s => s.next_run) ? 
                    schedulers
                      .filter(s => s.enabled && s.next_run)
                      .sort((a, b) => new Date(a.next_run.timestamp) - new Date(b.next_run.timestamp))[0]?.next_run.relative || 'N/A'
                    : 'N/A'
                  }
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Filter controls */}
        <div className="flex flex-wrap items-center space-x-2 mb-4">
          <div className="flex items-center text-gray-700 mr-2">
            <FaFilter className="mr-1" />
            <span>Filter:</span>
          </div>
          
          <button
            className={`px-3 py-1 text-sm rounded-full ${
              filter === 'all' 
                ? 'bg-indigo-100 text-indigo-800 border border-indigo-200' 
                : 'bg-gray-100 text-gray-700 border border-gray-200 hover:bg-gray-200'
            }`}
            onClick={() => setFilter('all')}
          >
            All
          </button>
          
          <button
            className={`px-3 py-1 text-sm rounded-full flex items-center ${
              filter === 'enabled' 
                ? 'bg-green-100 text-green-800 border border-green-200' 
                : 'bg-gray-100 text-gray-700 border border-gray-200 hover:bg-gray-200'
            }`}
            onClick={() => setFilter('enabled')}
          >
            <FaCheck className="mr-1 text-xs" />
            Enabled
          </button>
          
          <button
            className={`px-3 py-1 text-sm rounded-full flex items-center ${
              filter === 'disabled' 
                ? 'bg-red-100 text-red-800 border border-red-200' 
                : 'bg-gray-100 text-gray-700 border border-gray-200 hover:bg-gray-200'
            }`}
            onClick={() => setFilter('disabled')}
          >
            <FaTimes className="mr-1 text-xs" />
            Disabled
          </button>
          
          <button
            className={`px-3 py-1 text-sm rounded-full ${
              filter === 'interval' 
                ? 'bg-indigo-100 text-indigo-800 border border-indigo-200' 
                : 'bg-gray-100 text-gray-700 border border-gray-200 hover:bg-gray-200'
            }`}
            onClick={() => setFilter('interval')}
          >
            Interval
          </button>
          
          <button
            className={`px-3 py-1 text-sm rounded-full ${
              filter === 'time' 
                ? 'bg-purple-100 text-purple-800 border border-purple-200' 
                : 'bg-gray-100 text-gray-700 border border-gray-200 hover:bg-gray-200'
            }`}
            onClick={() => setFilter('time')}
          >
            Time-based
          </button>
        </div>
        
        {/* Scheduler card grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {filteredSchedulers().map((scheduler) => (
            <SchedulerCard key={scheduler.id} scheduler={scheduler} />
          ))}
        </div>
        
        {/* Empty state */}
        {(!filteredSchedulers().length) && (
          <div className="text-center py-12 bg-gray-50 rounded-lg">
            <FaCalendarAlt className="mx-auto h-12 w-12 text-gray-400" />
            <h3 className="mt-2 text-sm font-medium text-gray-900">No schedulers</h3>
            <p className="mt-1 text-sm text-gray-500">
              {filter !== 'all' 
                ? 'No schedulers match the current filter.' 
                : 'No schedulers found in the system.'}
            </p>
            <div className="mt-4">
              <button
                className="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600 transition-colors"
                onClick={() => {
                  // Try fetching the raw schedulers endpoint
                  fetch('/api/debug/schedulers')
                    .then(response => response.json())
                    .then(data => {
                      console.log('Raw scheduler data:', data);
                      alert('Raw scheduler data fetched. See console for details.');
                    })
                    .catch(err => {
                      console.error('Error fetching raw scheduler data:', err);
                      alert('Error fetching raw scheduler data. See console for details.');
                    });
                }}
              >
                Check Raw Scheduler Data
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default SchedulerDashboard;