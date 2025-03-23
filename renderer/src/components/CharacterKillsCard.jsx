import React, { useState, useEffect } from 'react';
import { 
  FaCircleNotch, 
  FaUsers,
  FaCheckCircle,
  FaExclamationTriangle,
  FaInfoCircle
} from 'react-icons/fa';

function CharacterKillsCard({ title, description }) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(null);
  const [stats, setStats] = useState(null);
  const [trackedInfo, setTrackedInfo] = useState(null);
  const [loadingInfo, setLoadingInfo] = useState(false);

  // Fetch tracked characters and killmail counts when component mounts
  useEffect(() => {
    fetchTrackedInfo();
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

  const fetchAllCharacterKills = async () => {
    try {
      setLoading(true);
      setError(null);
      setSuccess(null);
      setStats(null);

      // Simple API call to trigger kill data loading for all tracked characters
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
        setSuccess("Successfully loaded kill data for tracked characters");
        
        // Refresh the tracked info stats after successful load
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

  return (
    <div className="bg-white rounded-lg shadow-md overflow-hidden border border-gray-200">
      <div className="p-4 border-b">
        <h3 className="text-lg font-semibold text-gray-800">{title}</h3>
        <p className="text-sm text-gray-600 mt-1">{description}</p>
      </div>
      
      {/* Tracked info display */}
      {trackedInfo && (
        <div className="px-4 py-3 bg-gray-50 border-b">
          <div className="flex items-center text-sm text-gray-700">
            <FaInfoCircle className="mr-2 text-indigo-500" />
            <div>
              <span className="font-medium">{trackedInfo.tracked_characters || 0}</span> characters tracked with 
              <span className="font-medium ml-1">{trackedInfo.total_kills || 0}</span> kills stored
            </div>
          </div>
        </div>
      )}
      
      <div className="p-4">
        {/* Main action button */}
        <button
          onClick={fetchAllCharacterKills}
          disabled={loading}
          className="w-full px-4 py-3 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition-colors disabled:opacity-50 flex items-center justify-center space-x-2 mb-4"
        >
          {loading ? (
            <FaCircleNotch className="animate-spin mr-2" />
          ) : (
            <FaUsers className="mr-2" />
          )}
          <span>Load Kill Data for All Tracked Characters</span>
        </button>

        {/* Status messages */}
        {success && (
          <div className="mb-4 p-3 bg-green-100 text-green-700 rounded flex items-center">
            <FaCheckCircle className="mr-2" />
            <span>{success}</span>
          </div>
        )}

        {error && (
          <div className="mb-4 p-3 bg-red-100 text-red-700 rounded flex items-center">
            <FaExclamationTriangle className="mr-2" />
            <span>{error}</span>
          </div>
        )}

        {/* Simple stats display if available */}
        {stats && (
          <div className="mt-4 border-t pt-4">
            <h4 className="font-medium text-gray-800 mb-2">Results</h4>
            <div className="bg-gray-50 p-3 rounded-md text-sm">
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