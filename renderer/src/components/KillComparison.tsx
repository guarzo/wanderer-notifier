import React, { useState, useEffect } from 'react';
import { Box, Button, Card, CardContent, Grid, Typography, Table, TableBody, TableCell, TableContainer, TableHead, TableRow, Paper, Chip, IconButton, Collapse, Alert, CircularProgress } from '@mui/material';
import { DatePicker } from '@mui/x-date-pickers/DatePicker';
import { format, isWithinInterval, subHours } from 'date-fns';
import { useQuery, useMutation } from '@tanstack/react-query';
import { fetchApi } from '../utils/api';
import KeyboardArrowDownIcon from '@mui/icons-material/KeyboardArrowDown';
import KeyboardArrowUpIcon from '@mui/icons-material/KeyboardArrowUp';
import SyncIcon from '@mui/icons-material/Sync';
import RefreshIcon from '@mui/icons-material/Refresh';

// Cache constants
const CACHE_KEY = 'killComparisonCache';
const CACHE_EXPIRY_HOURS = 6; // Cache expires after 6 hours

interface CharacterComparison {
  character_id: number;
  character_name: string;
  our_kills: number;
  zkill_kills: number;
  missing_kills: number[];
  missing_percentage: number;
}

interface AnalysisResult {
  reason: string;
  count: number;
  examples: number[];
}

interface CacheItem {
  timestamp: number;
  startDate: string;
  endDate: string;
  data: CharacterComparison[];
}

// Row component for character comparison
const CharacterRow = ({ character, onAnalyze }: { 
  character: CharacterComparison, 
  onAnalyze: (characterId: number, killIds: number[]) => void 
}) => {
  const [open, setOpen] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [syncResult, setSyncResult] = useState<string | null>(null);

  const syncCharacterKills = async () => {
    setSyncing(true);
    setSyncResult(null);
    try {
      // API call to sync this specific character's kills
      await fetchApi(`/api/character-kills?character_id=${character.character_id}`);
      setSyncResult('Sync completed successfully!');
      setTimeout(() => setSyncResult(null), 3000);
    } catch (error) {
      console.error('Failed to sync character kills:', error);
      setSyncResult('Sync failed. Please try again.');
    } finally {
      setSyncing(false);
    }
  };

  return (
    <>
      <TableRow sx={{ '& > *': { borderBottom: 'unset' } }}>
        <TableCell>
          <IconButton
            aria-label="expand row"
            size="small"
            onClick={() => setOpen(!open)}
          >
            {open ? <KeyboardArrowUpIcon /> : <KeyboardArrowDownIcon />}
          </IconButton>
        </TableCell>
        <TableCell component="th" scope="row">
          {character.character_name}
        </TableCell>
        <TableCell align="right">{character.our_kills}</TableCell>
        <TableCell align="right">{character.zkill_kills}</TableCell>
        <TableCell align="right">{character.missing_kills.length}</TableCell>
        <TableCell align="right">
          <Chip 
            label={`${character.missing_percentage.toFixed(1)}%`} 
            color={character.missing_percentage > 10 ? "error" : 
                 character.missing_percentage > 5 ? "warning" : "success"} 
            variant="outlined"
          />
        </TableCell>
        <TableCell>
          <Box sx={{ display: 'flex', gap: 1 }}>
            <IconButton 
              color="primary" 
              onClick={syncCharacterKills} 
              disabled={syncing}
              title="Sync character kills"
            >
              {syncing ? <CircularProgress size={24} /> : <SyncIcon />}
            </IconButton>
            {character.missing_kills.length > 0 && (
              <Button
                variant="outlined"
                size="small"
                onClick={() => onAnalyze(character.character_id, character.missing_kills)}
              >
                Analyze
              </Button>
            )}
          </Box>
          {syncResult && (
            <Typography variant="caption" color={syncResult.includes('failed') ? 'error' : 'success'}>
              {syncResult}
            </Typography>
          )}
        </TableCell>
      </TableRow>
      <TableRow>
        <TableCell style={{ paddingBottom: 0, paddingTop: 0 }} colSpan={7}>
          <Collapse in={open} timeout="auto" unmountOnExit>
            <Box sx={{ margin: 1 }}>
              <Typography variant="h6" gutterBottom component="div">
                Missing Kill IDs
              </Typography>
              <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1 }}>
                {character.missing_kills.length > 0 ? (
                  character.missing_kills.map((killId) => (
                    <Chip 
                      key={killId} 
                      label={killId} 
                      onClick={() => window.open(`https://zkillboard.com/kill/${killId}/`, '_blank')}
                      clickable
                    />
                  ))
                ) : (
                  <Typography variant="body2" color="text.secondary">
                    No missing kills found
                  </Typography>
                )}
              </Box>
            </Box>
          </Collapse>
        </TableCell>
      </TableRow>
    </>
  );
};

const KillComparison: React.FC = () => {
  const [startDate, setStartDate] = useState<Date | null>(new Date(Date.now() - 4 * 60 * 60 * 1000));
  const [endDate, setEndDate] = useState<Date | null>(new Date());
  const [characterData, setCharacterData] = useState<CharacterComparison[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false); // New state for background refreshes
  const [error, setError] = useState<string | null>(null);
  const [syncMessage, setSyncMessage] = useState<{type: 'success' | 'error', text: string} | null>(null);
  const [analyzingCharacter, setAnalyzingCharacter] = useState<number | null>(null);
  const [analysisResults, setAnalysisResults] = useState<AnalysisResult[] | null>(null);
  const [cacheStatus, setCacheStatus] = useState<'fresh' | 'stale' | 'none'>('none');

  // Function to save data to cache
  const saveToCache = (
    data: CharacterComparison[], 
    start: Date | null, 
    end: Date | null
  ) => {
    if (!start || !end) return;
    
    const cacheItem: CacheItem = {
      timestamp: Date.now(),
      startDate: start.toISOString(),
      endDate: end.toISOString(),
      data: data
    };
    
    try {
      localStorage.setItem(CACHE_KEY, JSON.stringify(cacheItem));
      console.log('Saved comparison data to cache');
    } catch (error) {
      console.error('Failed to save to cache:', error);
    }
  };

  // Function to load data from cache
  const loadFromCache = (
    start: Date | null, 
    end: Date | null
  ): CharacterComparison[] | null => {
    try {
      const cacheJson = localStorage.getItem(CACHE_KEY);
      
      if (!cacheJson) {
        console.log('No cache found');
        return null;
      }
      
      const cache: CacheItem = JSON.parse(cacheJson);
      const cacheDate = new Date(cache.timestamp);
      const expiryDate = subHours(new Date(), CACHE_EXPIRY_HOURS);
      
      // Check if cache is fresh (less than CACHE_EXPIRY_HOURS old)
      if (cacheDate > expiryDate) {
        setCacheStatus('fresh');
        console.log('Found fresh cache from', cacheDate.toLocaleString());
      } else {
        setCacheStatus('stale');
        console.log('Found stale cache from', cacheDate.toLocaleString());
      }
      
      // Check if the date ranges match (approximate match is fine)
      if (start && end) {
        const cacheStart = new Date(cache.startDate);
        const cacheEnd = new Date(cache.endDate);
        
        // If the date ranges are too different, don't use the cache
        const startDiff = Math.abs(start.getTime() - cacheStart.getTime());
        const endDiff = Math.abs(end.getTime() - cacheEnd.getTime());
        
        // Allow for a difference of up to 15 minutes for the dates
        if (startDiff > 15 * 60 * 1000 || endDiff > 15 * 60 * 1000) {
          console.log('Cache date range does not match current selection');
          return null;
        }
      }
      
      return cache.data;
    } catch (error) {
      console.error('Failed to load from cache:', error);
      return null;
    }
  };

  // Function to load comparison data for all characters
  const loadComparisonData = async (useCache = true, isBackgroundRefresh = false) => {
    if (!startDate || !endDate) {
      setError("Please select a valid date range");
      return;
    }

    // Set loading state based on whether this is a background refresh
    if (!isBackgroundRefresh) {
      setLoading(true);
    } else {
      setRefreshing(true);
    }
    
    setError(null);
    
    if (!isBackgroundRefresh) {
      setAnalysisResults(null);
    }

    // Try loading from cache first if allowed
    if (useCache && !isBackgroundRefresh) {
      const cachedData = loadFromCache(startDate, endDate);
      
      if (cachedData && cachedData.length > 0) {
        console.log(`Loaded ${cachedData.length} characters from cache`);
        setCharacterData(cachedData);
        setLoading(false);
        
        // If we have a stale cache, refresh in the background
        if (cacheStatus === 'stale') {
          console.log('Cache is stale, refreshing in background');
          // Refresh data in background without showing loading indicator
          setTimeout(() => loadComparisonData(false, true), 100);
        }
        
        return;
      }
    }

    try {
      // Format dates to ISO-8601 format with UTC timezone
      const formatDateToISO = (date: Date) => {
        // Ensure we're working with UTC
        const utcDate = new Date(date.getTime() - (date.getTimezoneOffset() * 60000));
        // Format to ISO string and ensure it ends with Z for UTC
        return utcDate.toISOString();
      };

      const start_date = formatDateToISO(startDate);
      const end_date = formatDateToISO(endDate);

      console.log(`Fetching comparison data from ${start_date} to ${end_date}`);

      // Use the new endpoint that directly returns all character data
      const params = new URLSearchParams({
        start_date,
        end_date
      });

      // Set a longer timeout for this API call (30 seconds)
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 30000);

      try {
        const response = await fetchApi(`/api/kills/compare-all?${params}`, {
          signal: controller.signal
        });
        
        clearTimeout(timeoutId);
        
        console.log('API Response:', response);
        
        if (!response || !response.data) {
          throw new Error('No response data received');
        }
        
        if (!response.data.character_breakdown || !Array.isArray(response.data.character_breakdown)) {
          console.error('Invalid character breakdown data:', response.data);
          throw new Error('No character breakdown data received');
        }

        if (response.data.character_breakdown.length === 0) {
          console.log('Received empty character breakdown array');
          setCharacterData([]);
          
          // Save the empty result to cache too
          saveToCache([], startDate, endDate);
          return;
        }

        // Sort by missing percentage in descending order
        const sortedData = [...response.data.character_breakdown].sort(
          (a, b) => b.missing_percentage - a.missing_percentage
        );
        
        console.log(`Loaded ${sortedData.length} character records from API`);
        setCharacterData(sortedData);
        
        // Save to cache
        saveToCache(sortedData, startDate, endDate);
        
        // If this was a background refresh, show a brief success message
        if (isBackgroundRefresh) {
          setSyncMessage({ 
            type: 'success', 
            text: 'Data refreshed successfully!' 
          });
          setTimeout(() => setSyncMessage(null), 3000);
        }
      } catch (fetchError) {
        if (fetchError.name === 'AbortError') {
          throw new Error('Request timed out. The data processing may be taking too long. Try a shorter date range.');
        }
        throw fetchError;
      }
    } catch (error) {
      console.error('Failed to load comparison data:', error);
      
      // Only show the error if this wasn't a background refresh or if we don't have cached data
      if (!isBackgroundRefresh || characterData.length === 0) {
        setError(`Failed to load data: ${error instanceof Error ? error.message : String(error)}`);
      } else if (isBackgroundRefresh) {
        // Show a non-intrusive error for background refreshes
        setSyncMessage({ 
          type: 'error', 
          text: 'Failed to refresh data in background. Using cached data.' 
        });
        setTimeout(() => setSyncMessage(null), 5000);
      }
    } finally {
      if (!isBackgroundRefresh) {
        setLoading(false);
      } else {
        setRefreshing(false);
      }
    }
  };

  // Load data on initial render
  useEffect(() => {
    loadComparisonData(true);
  }, []);

  // Handle syncing all characters with missing kills
  const handleSyncAllMissing = async () => {
    if (!confirm("This will fetch and sync kills for all characters with missing data. Continue?")) {
      return;
    }
    
    const charactersWithMissing = characterData.filter(char => char.missing_percentage > 0);
    
    if (charactersWithMissing.length === 0) {
      setSyncMessage({ type: 'success', text: 'No characters with missing kills found!' });
      setTimeout(() => setSyncMessage(null), 3000);
      return;
    }
    
    try {
      setSyncMessage({ type: 'success', text: 'Starting sync of all characters...' });
      
      // Process each character in sequence
      for (const character of charactersWithMissing) {
        setSyncMessage({ 
          type: 'success', 
          text: `Syncing ${character.character_name} (${charactersWithMissing.indexOf(character) + 1}/${charactersWithMissing.length})...` 
        });
        
        await fetchApi(`/api/character-kills?character_id=${character.character_id}`);
      }
      
      setSyncMessage({ type: 'success', text: 'All characters synced successfully!' });
      
      // Reload the data to show updated stats
      await loadComparisonData();
      
      setTimeout(() => setSyncMessage(null), 5000);
    } catch (error) {
      setSyncMessage({ type: 'error', text: `Error syncing characters: ${error}` });
    }
  };

  // Handle analyzing missing kills for a specific character
  const handleAnalyzeMissing = async (characterId: number, killIds: number[]) => {
    if (killIds.length === 0) return;
    
    setAnalyzingCharacter(characterId);
    setAnalysisResults(null);
    
    try {
      const response = await fetchApi('/api/kills/analyze-missing', {
        method: 'POST',
        body: JSON.stringify({
          character_id: characterId,
          kill_ids: killIds
        })
      });
      
      if (response.data) {
        setAnalysisResults(response.data);
      }
    } catch (error) {
      console.error('Failed to analyze missing kills:', error);
      setError(`Analysis failed: ${error instanceof Error ? error.message : String(error)}`);
    } finally {
      setAnalyzingCharacter(null);
    }
  };

  // Get character name for the current analysis
  const getCharacterName = (characterId: number | null) => {
    if (!characterId) return '';
    const character = characterData.find(c => c.character_id === characterId);
    return character ? character.character_name : `Character #${characterId}`;
  };

  return (
    <Box sx={{ p: 3 }}>
      <Typography variant="h4" gutterBottom>
        Kill Comparison Tool
      </Typography>

      {/* Date Range Filter */}
      <Card sx={{ mb: 3 }}>
        <CardContent>
          <Grid container spacing={3} alignItems="center">
            <Grid item xs={12} md={4}>
              <DatePicker
                label="Start Date"
                value={startDate}
                onChange={setStartDate}
                slotProps={{ textField: { fullWidth: true } }}
              />
            </Grid>
            <Grid item xs={12} md={4}>
              <DatePicker
                label="End Date"
                value={endDate}
                onChange={setEndDate}
                slotProps={{ textField: { fullWidth: true } }}
              />
            </Grid>
            <Grid item xs={12} md={4}>
              <Button
                variant="contained"
                onClick={() => loadComparisonData(false)}
                disabled={loading || !startDate || !endDate}
                startIcon={refreshing ? <CircularProgress size={20} /> : <RefreshIcon />}
                fullWidth
                sx={{ height: '56px' }}
              >
                {loading ? 'Loading...' : refreshing ? 'Refreshing...' : 'Refresh Data'}
              </Button>
            </Grid>
          </Grid>
          
          <Box sx={{ mt: 2, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <Typography variant="caption" color="text.secondary">
              Note: For best performance, use a shorter date range (under 24 hours). Longer ranges may time out.
            </Typography>
            
            {cacheStatus !== 'none' && (
              <Typography variant="caption" color={cacheStatus === 'fresh' ? 'success.main' : 'text.secondary'}>
                {cacheStatus === 'fresh' ? 'Using fresh cached data' : 'Using stale cached data, refreshing...'}
              </Typography>
            )}
          </Box>
        </CardContent>
      </Card>

      {/* Status Messages */}
      {error && (
        <Alert severity="error" sx={{ mb: 3 }} onClose={() => setError(null)}>
          {error}
        </Alert>
      )}
      
      {syncMessage && (
        <Alert 
          severity={syncMessage.type} 
          sx={{ mb: 3 }}
          onClose={() => setSyncMessage(null)}
        >
          {syncMessage.text}
        </Alert>
      )}

      {/* Character Comparison Table */}
      {loading ? (
        <Box display="flex" justifyContent="center" alignItems="center" py={4}>
          <CircularProgress />
        </Box>
      ) : characterData.length > 0 ? (
        <Card sx={{ mb: 3 }}>
          <CardContent>
            <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
              <Typography variant="h6">
                Character Kill Comparison
                {refreshing && (
                  <CircularProgress size={16} sx={{ ml: 1, verticalAlign: 'middle' }} />
                )}
              </Typography>
              {characterData.some(char => char.missing_percentage > 0) && (
                <Button 
                  variant="contained" 
                  color="primary" 
                  onClick={handleSyncAllMissing}
                  startIcon={<SyncIcon />}
                >
                  Sync All Missing
                </Button>
              )}
            </Box>

            <TableContainer component={Paper}>
              <Table aria-label="character breakdown table">
                <TableHead>
                  <TableRow>
                    <TableCell />
                    <TableCell>Character</TableCell>
                    <TableCell align="right">Our DB Kills</TableCell>
                    <TableCell align="right">zKill Kills</TableCell>
                    <TableCell align="right">Missing</TableCell>
                    <TableCell align="right">Missing %</TableCell>
                    <TableCell>Actions</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {characterData.map((character) => (
                    <CharacterRow 
                      key={character.character_id} 
                      character={character} 
                      onAnalyze={handleAnalyzeMissing}
                    />
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
            
            {!characterData.some(char => char.missing_percentage > 0) && (
              <Alert severity="success" sx={{ mt: 2 }}>
                All tracked characters have complete kill data! No missing kills found.
              </Alert>
            )}
          </CardContent>
        </Card>
      ) : (
        <Alert severity="info" sx={{ mb: 3 }}>
          No character data available for the selected time period.
        </Alert>
      )}

      {/* Analysis Results */}
      {analysisResults && (
        <Card>
          <CardContent>
            <Typography variant="h6" gutterBottom>
              Missing Kills Analysis for {getCharacterName(analyzingCharacter)}
            </Typography>
            <Grid container spacing={2}>
              {analysisResults.map((result) => (
                <Grid item xs={12} key={result.reason}>
                  <Typography variant="subtitle1">
                    {result.reason} ({result.count} kills)
                  </Typography>
                  {result.examples.length > 0 && (
                    <Typography variant="body2" color="textSecondary">
                      Example Kill IDs: {result.examples.join(', ')}
                    </Typography>
                  )}
                </Grid>
              ))}
            </Grid>
          </CardContent>
        </Card>
      )}
    </Box>
  );
};

export default KillComparison; 