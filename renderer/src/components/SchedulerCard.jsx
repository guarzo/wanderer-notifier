import React, { useState } from 'react';
import { 
  FaCalendarCheck, 
  FaHourglassHalf, 
  FaCalendarAlt, 
  FaCheckCircle, 
  FaExclamationTriangle, 
  FaClock, 
  FaPlayCircle,
  FaCircleNotch
} from 'react-icons/fa';

// Component for displaying individual scheduler information in a card
const SchedulerCard = ({ scheduler, onRefresh }) => {
  const [executing, setExecuting] = useState(false);

  // Handle case when scheduler isn't fully loaded
  if (!scheduler) return null;

  const {
    name,
    type,
    enabled,
    last_run,
    next_run,
    interval,
    hour,
    minute,
    stats
  } = scheduler;

  // Format interval in a human-readable format (convert from ms to seconds/minutes)
  const formatInterval = (intervalMs) => {
    if (!intervalMs) return 'N/A';
    
    if (intervalMs < 1000) return `${intervalMs}ms`;
    if (intervalMs < 60000) return `${Math.round(intervalMs / 1000)}s`;
    if (intervalMs < 3600000) return `${Math.round(intervalMs / 60000)}m`;
    return `${Math.round(intervalMs / 3600000)}h`;
  };

  // Calculate success rate percentage
  const calculateSuccessRate = () => {
    const total = (stats?.success_count || 0) + (stats?.error_count || 0);
    if (total === 0) return 0;
    return Math.round((stats?.success_count || 0) * 100 / total);
  };

  // Determine color based on success rate
  const getSuccessRateColor = (rate) => {
    if (rate >= 90) return 'text-green-600';
    if (rate >= 70) return 'text-yellow-600';
    return 'text-red-600';
  };

  // Special formatting for schedule display
  const getScheduleDisplay = () => {
    if (type === 'interval' && interval) {
      return `Every ${formatInterval(interval)}`;
    } else if (type === 'time') {
      // Safely handle potentially null hour and minute values
      const hourStr = hour !== null && hour !== undefined ? hour.toString().padStart(2, '0') : '00';
      const minuteStr = minute !== null && minute !== undefined ? minute.toString().padStart(2, '0') : '00';
      return `Daily at ${hourStr}:${minuteStr} UTC`;
    }
    return 'Unknown schedule';
  };

  // Get icon based on scheduler type
  const getTypeIcon = () => {
    if (type === 'interval') return <FaHourglassHalf className="mr-1 text-indigo-500" />;
    if (type === 'time') return <FaCalendarAlt className="mr-1 text-purple-500" />;
    return <FaClock className="mr-1 text-gray-500" />;
  };

  // Execute the scheduler
  const handleExecute = async () => {
    if (!enabled || executing) return;
    
    try {
      setExecuting(true);
      const response = await fetch(`/api/debug/schedulers/${name}/execute`, {
        method: 'POST',
      });
      
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }

      // Wait a bit before refreshing to allow the scheduler to complete
      setTimeout(() => {
        if (onRefresh) onRefresh();
        setExecuting(false);
      }, 1000);
    } catch (err) {
      console.error('Error executing scheduler:', err);
      setExecuting(false);
    }
  };

  return (
    <div className={`bg-white rounded-lg shadow-sm border ${enabled ? 'border-green-100' : 'border-gray-200'} p-4 hover:shadow-md transition-shadow`}>
      {/* Header */}
      <div className="flex justify-between items-center mb-3">
        <h3 className="font-semibold text-gray-800 text-lg flex items-center">
          {getTypeIcon()}
          <span>{name}</span>
        </h3>
        <span className={`px-2 py-1 text-xs rounded-full ${enabled ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'}`}>
          {enabled ? 'Enabled' : 'Disabled'}
        </span>
      </div>

      {/* Schedule information */}
      <div className="text-sm text-gray-600 mb-3 flex items-center">
        <FaCalendarCheck className="mr-1 text-gray-500" />
        <span>{getScheduleDisplay()}</span>
      </div>

      {/* Last run and next run information */}
      <div className="grid grid-cols-2 gap-3 mb-3">
        <div>
          <div className="text-xs text-gray-500 mb-1">Last Run</div>
          <div className="text-sm">
            {last_run ? (
              <div className="flex items-center">
                {last_run.relative}
              </div>
            ) : (
              <span className="text-gray-400">Never</span>
            )}
          </div>
        </div>
        <div>
          <div className="text-xs text-gray-500 mb-1">Next Run</div>
          <div className="text-sm">
            {next_run ? (
              <div className="flex items-center">
                {next_run.relative}
              </div>
            ) : (
              <span className="text-gray-400">Unknown</span>
            )}
          </div>
        </div>
      </div>

      {/* Statistics */}
      <div className="mt-4 pt-3 border-t border-gray-100">
        <div className="grid grid-cols-3 gap-2 text-center">
          <div>
            <div className="text-xs text-gray-500 mb-1">Success Rate</div>
            <div className={`font-semibold ${getSuccessRateColor(calculateSuccessRate())}`}>
              {calculateSuccessRate()}%
            </div>
          </div>
          <div>
            <div className="text-xs text-gray-500 mb-1">Successes</div>
            <div className="text-green-600 font-semibold flex items-center justify-center">
              <FaCheckCircle className="mr-1" />
              {stats?.success_count || 0}
            </div>
          </div>
          <div>
            <div className="text-xs text-gray-500 mb-1">Errors</div>
            <div className="text-red-600 font-semibold flex items-center justify-center">
              <FaExclamationTriangle className="mr-1" />
              {stats?.error_count || 0}
            </div>
          </div>
        </div>

        {/* Last run duration if available */}
        {stats?.last_duration_ms && (
          <div className="mt-3 text-xs text-gray-600">
            Last duration: {stats.last_duration_ms}ms
          </div>
        )}
      </div>

      {/* Run now button - disabled if scheduler is disabled or currently executing */}
      <div className="mt-3 flex justify-end">
        <button
          disabled={!enabled || executing}
          className={`text-xs px-2 py-1 rounded flex items-center ${
            enabled && !executing
              ? 'bg-indigo-50 text-indigo-700 hover:bg-indigo-100'
              : 'bg-gray-50 text-gray-400 cursor-not-allowed'
          }`}
          onClick={handleExecute}
        >
          {executing ? (
            <FaCircleNotch className="mr-1 animate-spin" />
          ) : (
            <FaPlayCircle className="mr-1" />
          )}
          {executing ? 'Running...' : 'Run Now'}
        </button>
      </div>
    </div>
  );
};

export default SchedulerCard;