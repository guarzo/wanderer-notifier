import React, { useState } from 'react';
import { Box, Button, Card, CardContent, FormControl, Grid, InputLabel, MenuItem, Select, TextField, Typography } from '@mui/material';
import { DatePicker } from '@mui/x-date-pickers/DatePicker';
import { format } from 'date-fns';
import { useQuery, useMutation } from '@tanstack/react-query';
import { fetchApi } from '../utils/api';

interface ComparisonResults {
  our_kills: number;
  zkill_kills: number;
  missing_kills: number[];
  extra_kills: number[];
  comparison: {
    total_difference: number;
    percentage_match: number;
    analysis: string;
  };
}

interface AnalysisResult {
  reason: string;
  count: number;
  examples: number[];
}

interface Character {
  character_id: number;
  character_name: string;
  corporation_id?: number;
  corporation_name?: string;
  alliance_id?: number;
  alliance_name?: string;
}

const KillComparison: React.FC = () => {
  const [selectedCharacter, setSelectedCharacter] = useState<string>('');
  const [startDate, setStartDate] = useState<Date | null>(new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)); // 7 days ago
  const [endDate, setEndDate] = useState<Date | null>(new Date());
  const [comparisonResults, setComparisonResults] = useState<ComparisonResults | null>(null);
  const [analysisResults, setAnalysisResults] = useState<AnalysisResult[] | null>(null);

  // Fetch tracked characters
  const { data: charactersResponse, isError: isCharactersError } = useQuery({
    queryKey: ['characters'],
    queryFn: () => fetchApi<Character[]>('/api/characters')
  });

  const characters = charactersResponse?.data || [];

  // Compare kills mutation
  const compareKillsMutation = useMutation({
    mutationFn: async () => {
      if (!selectedCharacter || !startDate || !endDate) return null;

      // Format dates to YYYYMMDDHHmm format
      const formatDateForZKill = (date: Date) => {
        // Convert to UTC first
        const utcDate = new Date(date.getTime() - (date.getTimezoneOffset() * 60000));
        const year = utcDate.getUTCFullYear();
        const month = String(utcDate.getUTCMonth() + 1).padStart(2, '0');
        const day = String(utcDate.getUTCDate()).padStart(2, '0');
        const hours = String(utcDate.getUTCHours()).padStart(2, '0');
        const minutes = String(utcDate.getUTCMinutes()).padStart(2, '0');
        const formatted = `${year}${month}${day}${hours}${minutes}`;
        console.log('Formatting date:', {
          original: date.toISOString(),
          utc: utcDate.toISOString(),
          formatted,
          components: { year, month, day, hours, minutes }
        });
        return formatted;
      };

      const start_date = formatDateForZKill(startDate);
      const end_date = formatDateForZKill(endDate);

      console.log('Sending request with dates:', { start_date, end_date });

      const params = new URLSearchParams({
        character_id: selectedCharacter,
        start_date,
        end_date
      });

      const response = await fetchApi(`/api/kills/compare?${params}`);
      return response.data;
    },
    onSuccess: (data) => {
      if (data) {
        setComparisonResults(data);
        setAnalysisResults(null); // Reset analysis when new comparison is made
      }
    }
  });

  // Analyze missing kills mutation
  const analyzeMissingKillsMutation = useMutation({
    mutationFn: async (killIds: number[]) => {
      if (!selectedCharacter) return null;

      const response = await fetchApi('/api/kills/analyze-missing', {
        method: 'POST',
        body: JSON.stringify({
          character_id: selectedCharacter,
          kill_ids: killIds
        })
      });
      return response.data;
    },
    onSuccess: (data) => {
      if (data) {
        setAnalysisResults(data);
      }
    }
  });

  const handleCompare = () => {
    compareKillsMutation.mutate();
  };

  const handleAnalyzeMissing = () => {
    if (comparisonResults?.missing_kills) {
      analyzeMissingKillsMutation.mutate(comparisonResults.missing_kills);
    }
  };

  return (
    <Box sx={{ p: 3 }}>
      <Typography variant="h4" gutterBottom>
        Kill Comparison Tool
      </Typography>

      {/* Input Form */}
      <Card sx={{ mb: 3 }}>
        <CardContent>
          <Grid container spacing={3}>
            <Grid item xs={12} md={4}>
              <FormControl fullWidth>
                <InputLabel>Character</InputLabel>
                <Select
                  value={selectedCharacter}
                  label="Character"
                  onChange={(e) => setSelectedCharacter(e.target.value)}
                >
                  {characters.map((char) => (
                    <MenuItem key={char.character_id} value={char.character_id}>
                      {char.character_name}
                    </MenuItem>
                  ))}
                </Select>
              </FormControl>
            </Grid>
            <Grid item xs={12} md={3}>
              <DatePicker
                label="Start Date"
                value={startDate}
                onChange={setStartDate}
                slotProps={{ textField: { fullWidth: true } }}
              />
            </Grid>
            <Grid item xs={12} md={3}>
              <DatePicker
                label="End Date"
                value={endDate}
                onChange={setEndDate}
                slotProps={{ textField: { fullWidth: true } }}
              />
            </Grid>
            <Grid item xs={12} md={2}>
              <Button
                variant="contained"
                onClick={handleCompare}
                disabled={!selectedCharacter || !startDate || !endDate || compareKillsMutation.isPending}
                loading={compareKillsMutation.isPending}
                fullWidth
                sx={{ height: '56px' }}
              >
                Compare
              </Button>
            </Grid>
          </Grid>
        </CardContent>
      </Card>

      {/* Results */}
      {comparisonResults && (
        <Card sx={{ mb: 3 }}>
          <CardContent>
            <Typography variant="h6" gutterBottom>
              Comparison Results
            </Typography>
            <Grid container spacing={2}>
              <Grid item xs={12} md={6}>
                <Typography>Our Database Kills: {comparisonResults.our_kills}</Typography>
                <Typography>zKillboard Kills: {comparisonResults.zkill_kills}</Typography>
                <Typography>Missing Kills: {comparisonResults.missing_kills.length}</Typography>
                <Typography>Extra Kills: {comparisonResults.extra_kills.length}</Typography>
              </Grid>
              <Grid item xs={12} md={6}>
                <Typography>Match Percentage: {comparisonResults.comparison.percentage_match}%</Typography>
                <Typography>Analysis: {comparisonResults.comparison.analysis}</Typography>
              </Grid>
              {comparisonResults.missing_kills.length > 0 && (
                <Grid item xs={12}>
                  <Button
                    variant="outlined"
                    onClick={handleAnalyzeMissing}
                    disabled={analyzeMissingKillsMutation.isPending}
                    loading={analyzeMissingKillsMutation.isPending}
                  >
                    Analyze Missing Kills
                  </Button>
                </Grid>
              )}
            </Grid>
          </CardContent>
        </Card>
      )}

      {/* Analysis Results */}
      {analysisResults && (
        <Card>
          <CardContent>
            <Typography variant="h6" gutterBottom>
              Missing Kills Analysis
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