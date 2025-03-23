import React, { useState, useEffect } from 'react';
import { 
  FaCircleNotch, 
  FaUsers,
  FaCheckCircle,
  FaExclamationTriangle,
  FaInfoCircle,
  FaChartBar,
  FaCalendarAlt,
  FaRegCalendar
} from 'react-icons/fa';

function CharacterKillsCard({ title, description }) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(null);
  const [stats, setStats] = useState(null);
  const [trackedInfo, setTrackedInfo] = useState(null);
  const [loadingInfo, setLoadingInfo] = useState(false);
  const [aggregating, setAggregating] = useState(false);
  const [aggregationInfo, setAggregationInfo] = useState(null);
  const [aggregationStats, setAggregationStats] = useState(null);

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
      const response = await fetch(`/api/killmail-aggregation-stats`);
      if (!response.ok) {
        console.log(`Aggregation stats not available: ${response.status}`);
        return;
      }
      const data = await response.json();
      if (data.success) {
        setAggregationStats(data.stats);
        console.log("Aggregation stats loaded:", data.stats);
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
      
      const response = await fetch(url);
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
      
      if (data.success) {
        setStats(data.details);
        setSuccess("Successfully loaded kill data");
        setTimeout(() => {
          fetchTrackedInfo();
        }, 1000);
        setTimeout(() => {
          setSuccess(null);
        }, 5000);
      } else {
        throw new Error(data.message || data.details || 'Failed to load kill data');
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
      
      const response = await fetch(`/charts/killmail/aggregate?type=${periodType}`);
      
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
      
      <div className="p-4">
        <div className="grid grid-cols-2 gap-3 mb-4">
          <button
            onClick={fetchAllCharacterKills}
            disabled={loading}
            title="Load Kill Data"
            className="p-3 bg-indigo-600 text-white rounded-full hover:bg-indigo-700 transition flex items-center justify-center disabled:opacity-50"
          >
            {loading ? <FaCircleNotch className="animate-spin" /> : <FaUsers />}
          </button>
          <div className="flex space-x-2">
            <button
              onClick={() => triggerAggregation('weekly')}
              disabled={aggregating}
              title="Weekly Aggregation"
              className="p-3 bg-purple-600 text-white rounded-full hover:bg-purple-700 transition flex items-center justify-center disabled:opacity-50"
            >
              {aggregating ? <FaCircleNotch className="animate-spin" /> : <FaChartBar />}
            </button>
            <button
              onClick={() => triggerAggregation('daily')}
              disabled={aggregating}
              title="Daily Aggregation"
              className="p-3 bg-purple-500 text-white rounded-full hover:bg-purple-600 transition flex items-center justify-center disabled:opacity-50"
            >
              <FaRegCalendar />
            </button>
            <button
              onClick={() => triggerAggregation('monthly')}
              disabled={aggregating}
              title="Monthly Aggregation"
              className="p-3 bg-purple-500 text-white rounded-full hover:bg-purple-600 transition flex items-center justify-center disabled:opacity-50"
            >
              <FaCalendarAlt />
            </button>
          </div>
        </div>

        {success && (
          <div className="mb-4 p-3 bg-green-100 text-green-700 rounded flex items-center">
            <FaCheckCircle className="mr-2" />
            <span className="text-sm">{success}</span>
          </div>
        )}

        {error && (
          <div className="mb-4 p-3 bg-red-100 text-red-700 rounded flex items-center">
            <FaExclamationTriangle className="mr-2" />
            <span className="text-sm">{error}</span>
          </div>
        )}

        {aggregationInfo && (
          <div className="mb-4 p-3 bg-purple-50 border border-purple-100 rounded">
            <h4 className="font-medium text-gray-800 mb-2 flex items-center">
              <FaChartBar className="mr-2 text-purple-500" />
              <span className="text-sm">Aggregation Results</span>
            </h4>
            <div className="text-xs text-gray-700">
              <p>
                Aggregated <span className="font-medium">{aggregationInfo.period_type}</span> stats for <span className="font-medium">{aggregationInfo.target_date}</span>
              </p>
            </div>
          </div>
        )}

        {stats && (
          <div className="mt-4 border-t pt-4">
            <h4 className="font-medium text-gray-800 mb-2 text-sm">Kill Load Results</h4>
            <div className="bg-gray-50 p-3 rounded-md text-xs">
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <span className="font-medium">Processed:</span> {stats.processed} kills
                </div>
                <div>
                  <span className="font-medium">Persisted:</span> {stats.persisted} kills
                </div>
                {stats.characters && (
                  <div className="col-span-2">
                    <span className="font-medium">Characters:</span> {stats.characters}
                  </div>
                )}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export default CharacterKillsCard;
