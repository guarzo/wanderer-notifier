import React from 'react';
import { Box, Card, CardContent, Typography, CircularProgress } from '@mui/material';
import { LineChart, Line, XAxis, YAxis, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { format } from 'date-fns';
import { useQuery } from '@tanstack/react-query';
import { fetchApi } from '../utils/api';

interface TrendData {
  timestamp: string;
  our_kills: number;
  zkill_kills: number;
  missing_count: number;
  percentage_match: number;
}

interface KillComparisonTrendsProps {
  characterId: number;
  timeRangeType: string;
}

const KillComparisonTrends: React.FC<KillComparisonTrendsProps> = ({ characterId, timeRangeType }) => {
  const { data: trendData, isLoading, error } = useQuery<TrendData[]>(
    ['killTrends', characterId, timeRangeType],
    async () => {
      const response = await fetchApi(`/api/kills/trends?character_id=${characterId}&time_range=${timeRangeType}`);
      return response.data;
    },
    {
      refetchInterval: 300000, // Refresh every 5 minutes
      enabled: !!characterId && !!timeRangeType
    }
  );

  if (isLoading) {
    return (
      <Box display="flex" justifyContent="center" p={2}>
        <CircularProgress />
      </Box>
    );
  }

  if (error) {
    return (
      <Box p={2}>
        <Typography color="error">Error loading trend data</Typography>
      </Box>
    );
  }

  const formatDate = (timestamp: string) => {
    return format(new Date(timestamp), 'HH:mm:ss');
  };

  return (
    <Card>
      <CardContent>
        <Typography variant="h6" gutterBottom>
          Kill Tracking Trends
        </Typography>

        <Box height={300}>
          <ResponsiveContainer width="100%" height="100%">
            <LineChart
              data={trendData}
              margin={{
                top: 5,
                right: 30,
                left: 20,
                bottom: 5,
              }}
            >
              <XAxis 
                dataKey="timestamp" 
                tickFormatter={formatDate}
              />
              <YAxis yAxisId="left" />
              <YAxis yAxisId="right" orientation="right" />
              <Tooltip
                labelFormatter={(label) => format(new Date(label), 'yyyy-MM-dd HH:mm:ss')}
              />
              <Legend />
              <Line
                yAxisId="left"
                type="monotone"
                dataKey="our_kills"
                name="Our Kills"
                stroke="#8884d8"
                dot={false}
              />
              <Line
                yAxisId="left"
                type="monotone"
                dataKey="zkill_kills"
                name="zKill Kills"
                stroke="#82ca9d"
                dot={false}
              />
              <Line
                yAxisId="right"
                type="monotone"
                dataKey="percentage_match"
                name="Match %"
                stroke="#ffc658"
                dot={false}
              />
            </LineChart>
          </ResponsiveContainer>
        </Box>

        {trendData && trendData.length > 0 && (
          <Box mt={2}>
            <Typography variant="body2" color="textSecondary">
              Last updated: {format(new Date(trendData[0].timestamp), 'yyyy-MM-dd HH:mm:ss')}
            </Typography>
          </Box>
        )}
      </CardContent>
    </Card>
  );
};

export default KillComparisonTrends; 