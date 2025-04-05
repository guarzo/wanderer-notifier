import React, { useState, useEffect } from 'react';
import { 
  FaCircleNotch, 
  FaUsers,
  FaCheckCircle,
  FaExclamationTriangle,
  FaInfoCircle,
  FaChartBar,
  FaCalendarAlt,
  FaRegCalendar,
  FaBug,
  FaHammer,
  FaSync
} from 'react-icons/fa';

function CharacterKillsCard({ title = "Character Kill Data", description = "Load and aggregate kill data for tracked characters" }) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(null);
  const [stats, setStats] = useState(null);
  const [trackedInfo, setTrackedInfo] = useState(null);
  const [loadingInfo, setLoadingInfo] = useState(false);
  const [aggregating, setAggregating] = useState(false);
  const [aggregationInfo, setAggregationInfo] = useState(null);
  const [aggregationStats, setAggregationStats] = useState(null);
  const [debugData, setDebugData] = useState(null);
  const [debugInfo, setDebugInfo] = useState(null);
  const [forceSyncing, setForceSyncing] = useState(false);

  useEffect(() => {
    fetchTrackedInfo();
    fetchAggregationStats();
  }, []);

  const fetchTrackedInfo = async () => {
    try {
      setLoadingInfo(true);
      const response = await fetch(`/api/character-kills/stats`);
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      setTrackedInfo(data);
      console.log("Tracked info loaded:", data);
    } catch (error) {
      console.error('Error fetching tracked info:', error);
    } finally {
      setLoadingInfo(false);
    }
  };

  const fetchAggregationStats = async () => {
    try {
      const response = await fetch(`/api/charts/killmail/debug`);
      if (!response.ok) {
        console.log(`Aggregation stats not available: ${response.status}`);
        return;
      }
      const data = await response.json();
      if (data.status === 'ok') {
        setAggregationStats({
          aggregated_characters: data.data.counts.tracked_characters_db || 0,
          total_stats: data.data.counts.statistics || 0,
          periods: data.data.counts.by_period || {}
        });
        console.log("Aggregation stats loaded:", data);
      }
    } catch (error) {
      console.error('Error fetching aggregation stats:', error);
    }
  };

  const fetchAllCharacterKills = async () => {
    try {
      setLoading(true);
      setError(null);
      setSuccess(null);
      setStats(null);

      const url = `/api/character-kills?all=true`;
      console.log(`Triggering kill data loading: ${url}`);
      
      const response = await fetch(url, {
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        }
      });
      console.log(`Response status: ${response.status}`);
      
      if (!response.ok) {
        let errorMessage;
        try {
          const errorData = await response.json();
          console.error("Error response:", errorData);
          errorMessage = errorData.message || errorData.details || `HTTP error! Status: ${response.status}`;
        } catch (parseError) {
          errorMessage = `HTTP error! Status: ${response.status}`;
        }
        throw new Error(errorMessage);
      }
      
      const data = await response.json();
      console.log("Response received:", data);
      
      if (data.status === 'ok') {
        setStats(data.data);
        setSuccess(data.data.message);
        setTimeout(() => {
          fetchTrackedInfo();
        }, 1000);
        setTimeout(() => {
          setSuccess(null);
        }, 5000);
      } else {
        throw new Error(data.message || 'Failed to load kill data');
      }
    } catch (error) {
      console.error('Error:', error);
      setError(error.message || 'An unknown error occurred');
    } finally {
      setLoading(false);
    }
  };

  const triggerAggregation = async (periodType = 'weekly') => {
    try {
      setAggregating(true);
      setError(null);
      setSuccess(null);
      setAggregationInfo(null);

      console.log(`Triggering ${periodType} aggregation...`);
      
      const response = await fetch(`/api/charts/killmail/aggregate?type=${periodType}`);
      
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      
      const data = await response.json();
      console.log("Aggregation response:", data);
      
      if (data.status === 'ok') {
        setAggregationInfo(data);
        setSuccess(`Aggregation completed for ${data.target_date}`);
        setTimeout(() => {
          fetchAggregationStats();
        }, 1000);
        setTimeout(() => {
          setSuccess(null);
        }, 5000);
      } else {
        throw new Error(data.message || 'Failed to run aggregation');
      }
    } catch (error) {
      console.error('Aggregation error:', error);
      setError(`Aggregation error: ${error.message}`);
    } finally {
      setAggregating(false);
    }
  };

  const fetchDebugData = async () => {
    setDebugData(null);
    setDebugInfo("Loading debug information...");
    
    try {
      const response = await fetch(`/api/charts/killmail/debug`);
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      console.log('Debug data:', data);
      setDebugData(data);
      setDebugInfo(JSON.stringify(data, null, 2));
    } catch (error) {
      console.error('Error fetching debug data:', error);
      setDebugInfo(`Error fetching debug data: ${error.message}`);
    }
  };

  const forceSync = async () => {
    if (!window.confirm('This will DELETE all characters from the database and resync from cache. Continue?')) {
      return;
    }
    
    setForceSyncing(true);
    setSuccess(null);
    setError(null);
    setDebugInfo(null);
    
    console.log('Force syncing characters from cache to database...');
    
    try {
      const response = await fetch(`/api/charts/killmail/force-sync-characters`);
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      
      const data = await response.json();
      console.log('Force sync result:', data);
      if (data.status === 'ok') {
        setSuccess(`Force sync completed successfully! Database now contains ${data.details.db_count || 0} characters.`);
        setTimeout(() => {
          setSuccess(null);
        }, 5000);
      } else {
        throw new Error(data.message || 'Failed to force sync characters');
      }
    } catch (error) {
      console.error('Error during force sync:', error);
      setError(`Force sync error: ${error.message}`);
    } finally {
      setForceSyncing(false);
    }
  };

  return (
    <div className="bg-white rounded-lg shadow-md overflow-hidden border border-gray-200">
      <div className="p-4 border-b">
        <h3 className="text-lg font-semibold text-gray-800">{title}</h3>
        <p className="text-sm text-gray-600 mt-1">{description}</p>
      </div>
      
      {trackedInfo && (
        <div className="px-4 py-3 bg-gray-50 border-b">
          <div className="flex items-center text-sm text-gray-700">
            <FaInfoCircle className="mr-2 text-indigo-500" />
            <div>
              <span className="font-medium">{trackedInfo.tracked_characters || 0}</span> tracked, 
              <span className="font-medium ml-1">{trackedInfo.total_kills || 0}</span> kills
            </div>
          </div>
        </div>
      )}
      
      {aggregationStats && (
        <div className="px-4 py-3 bg-gray-100 border-b">
          <div className="flex items-center text-sm text-gray-700">
            <FaChartBar className="mr-2 text-purple-500" />
            <div>
              <span className="font-medium">{aggregationStats.aggregated_characters || 0}</span> characters, 
              <span className="font-medium ml-1">{aggregationStats.total_stats || 0}</span> stats
            </div>
          </div>
          {aggregationStats.last_aggregation && (
            <div className="mt-1 flex items-center text-sm text-gray-700">
              <FaCalendarAlt className="mr-2 text-purple-500" />
              <div>
                Last: <span className="font-medium">{aggregationStats.last_aggregation}</span>
              </div>
            </div>
          )}
        </div>
      )}

      {error && (
        <div className="p-4 bg-red-50 border-b">
          <div className="flex items-center text-sm text-red-700">
            <FaExclamationTriangle className="mr-2" />
            {error}
          </div>
        </div>
      )}

      {success && (
        <div className="p-4 bg-green-50 border-b">
          <div className="flex items-center text-sm text-green-700">
            <FaCheckCircle className="mr-2" />
            {success}
          </div>
        </div>
      )}

      {debugInfo && (
        <div className="p-4 bg-gray-50 border-b">
          <pre className="text-xs text-gray-700 whitespace-pre-wrap">{debugInfo}</pre>
        </div>
      )}
      
      <div className="p-4">
        <div className="grid grid-cols-2 gap-3 mb-4">
          <button
            onClick={fetchAllCharacterKills}
            disabled={loading}
            title="Load Kill Data"
            className="p-3 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition flex items-center justify-center disabled:opacity-50"
          >
            {loading ? <FaCircleNotch className="animate-spin" /> : <FaUsers className="mr-2" />}
            <span>Load Kill Data</span>
          </button>

          <button
            onClick={() => triggerAggregation('weekly')}
            disabled={aggregating}
            title="Run Aggregation"
            className="p-3 bg-purple-600 text-white rounded-lg hover:bg-purple-700 transition flex items-center justify-center disabled:opacity-50"
          >
            {aggregating ? <FaCircleNotch className="animate-spin" /> : <FaSync className="mr-2" />}
            <span>Run Aggregation</span>
          </button>

          <button
            onClick={fetchDebugData}
            disabled={loading}
            title="View Database Status"
            className="p-3 bg-gray-600 text-white rounded-lg hover:bg-gray-700 transition flex items-center justify-center disabled:opacity-50"
          >
            <FaBug className="mr-2" />
            <span>View Database Status</span>
          </button>

          <button
            onClick={forceSync}
            disabled={forceSyncing}
            title="Force Sync Characters"
            className="p-3 bg-red-600 text-white rounded-lg hover:bg-red-700 transition flex items-center justify-center disabled:opacity-50"
          >
            {forceSyncing ? <FaCircleNotch className="animate-spin" /> : <FaHammer className="mr-2" />}
            <span>Force Sync Characters</span>
          </button>
        </div>
      </div>
    </div>
  );
}

export default CharacterKillsCard;
