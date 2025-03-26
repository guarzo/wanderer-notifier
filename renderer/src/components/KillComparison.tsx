import React, { useState, useEffect } from 'react';
import { Box, Button, Card, CardContent, Grid, Typography, Table, TableBody, TableCell, TableContainer, TableHead, TableRow, Paper, Chip, IconButton, Collapse, Alert, CircularProgress, Select, MenuItem, InputLabel, FormControl } from '@mui/material';
import { format } from 'date-fns';
import { useQuery, useMutation } from '@tanstack/react-query';
import { fetchApi } from '../utils/api';
import KeyboardArrowDownIcon from '@mui/icons-material/KeyboardArrowDown';
import KeyboardArrowUpIcon from '@mui/icons-material/KeyboardArrowUp';
import SyncIcon from '@mui/icons-material/Sync';
import RefreshIcon from '@mui/icons-material/Refresh';
import KillComparisonTrends from './KillComparisonTrends';

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
const CharacterRow = ({ character, timeRangeType, onAnalyze }: { 
  character: CharacterComparison, 
  timeRangeType: string,
  onAnalyze: (characterId: number, killIds: number[]) => void 
}) => {
  const [open, setOpen] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [syncResult, setSyncResult] = useState<string | null>(null);
  const [showTrends, setShowTrends] = useState(false);

  const syncCharacterKills = async () => {
    setSyncing(true);
    setSyncResult(null);
    try {
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
            <Button
              variant="outlined"
              size="small"
              onClick={() => setShowTrends(!showTrends)}
            >
              {showTrends ? 'Hide Trends' : 'Show Trends'}
            </Button>
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
          <Collapse in={open || showTrends} timeout="auto" unmountOnExit>
            <Box sx={{ margin: 1 }}>
              {open && (
                <>
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
                </>
              )}
              
              {showTrends && (
                <Box mt={2}>
                  <KillComparisonTrends 
                    characterId={character.character_id}
                    timeRangeType={timeRangeType}
                  />
                </Box>
              )}
            </Box>
          </Collapse>
        </TableCell>
      </TableRow>
    </>
  );
};

const KillComparison: React.FC = () => {
  const timeRangeOptions = [
    { value: "1h", label: "Last Hour" },
    { value: "4h", label: "Last 4 Hours" },
    { value: "12h", label: "Last 12 Hours" },
    { value: "24h", label: "Last 24 Hours" },
    { value: "7d", label: "Last 7 Days" }
  ];
  
  const [timeRangeType, setTimeRangeType] = useState<string>("4h");
  const [characterData, setCharacterData] = useState<CharacterComparison[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [syncMessage, setSyncMessage] = useState<{type: 'success' | 'error', text: string} | null>(null);
  const [analyzingCharacter, setAnalyzingCharacter] = useState<number | null>(null);
  const [analysisResults, setAnalysisResults] = useState<AnalysisResult[] | null>(null);
  const [cacheInfo, setCacheInfo] = useState<{cached_at?: string, cache_expires_at?: string} | null>(null);

  const loadComparisonData = async () => {
    setLoading(true);
    setError(null);
    setAnalysisResults(null);
    setCacheInfo(null);

    try {
      const response = await fetchApi(`/api/kills/compare-cache?type=${timeRangeType}`);
      
      if (!response || !response.data) {
        throw new Error('No response data received');
      }
      
      if (!response.data.character_breakdown || !Array.isArray(response.data.character_breakdown)) {
        throw new Error('No character breakdown data received');
      }

      setCacheInfo({
        cached_at: response.data.cached_at,
        cache_expires_at: response.data.cache_expires_at
      });

      const sortedData = [...response.data.character_breakdown].sort(
        (a, b) => b.missing_percentage - a.missing_percentage
      );
      
      setCharacterData(sortedData);
      
    } catch (error) {
      console.error('Failed to load comparison data:', error);
      setError(`Failed to load data: ${error instanceof Error ? error.message : String(error)}`);
      setCharacterData([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadComparisonData();
  }, [timeRangeType]);

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
      
      for (const character of charactersWithMissing) {
        setSyncMessage({ 
          type: 'success', 
          text: `Syncing ${character.character_name} (${charactersWithMissing.indexOf(character) + 1}/${charactersWithMissing.length})...` 
        });
        
        await fetchApi(`/api/character-kills?character_id=${character.character_id}`);
      }
      
      setSyncMessage({ type: 'success', text: 'All characters synced successfully!' });
      loadComparisonData();
      setTimeout(() => setSyncMessage(null), 5000);
    } catch (error) {
      setSyncMessage({ type: 'error', text: `Error syncing characters: ${error}` });
    }
  };

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

  const formatDate = (dateString?: string) => {
    if (!dateString) return "";
    try {
      const date = new Date(dateString);
      return date.toLocaleString();
    } catch (e) {
      return dateString;
    }
  };

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

      <Card sx={{ mb: 3 }}>
        <CardContent>
          <Grid container spacing={3} alignItems="center">
            <Grid item xs={12} md={6}>
              <FormControl fullWidth>
                <InputLabel id="timerange-select-label">Time Range</InputLabel>
                <Select
                  labelId="timerange-select-label"
                  value={timeRangeType}
                  label="Time Range"
                  onChange={(e) => setTimeRangeType(e.target.value)}
                >
                  {timeRangeOptions.map(option => (
                    <MenuItem key={option.value} value={option.value}>
                      {option.label}
                    </MenuItem>
                  ))}
                </Select>
              </FormControl>
            </Grid>
            
            <Grid item xs={12} md={6}>
              <Button
                variant="contained"
                onClick={loadComparisonData}
                disabled={loading}
                startIcon={loading ? <CircularProgress size={20} /> : <RefreshIcon />}
                fullWidth
                sx={{ height: '56px' }}
              >
                {loading ? 'Loading...' : 'Refresh Data'}
              </Button>
            </Grid>
          </Grid>
          
          <Box sx={{ mt: 2, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <Typography variant="caption" color="text.secondary">
              Using pre-cached data for better performance.
            </Typography>
            
            {cacheInfo && (
              <Typography variant="caption" color="text.secondary">
                Cached at: {formatDate(cacheInfo.cached_at)} 
                {cacheInfo.cache_expires_at && ` (expires: ${formatDate(cacheInfo.cache_expires_at)})`}
              </Typography>
            )}
          </Box>
        </CardContent>
      </Card>

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
                      timeRangeType={timeRangeType}
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
