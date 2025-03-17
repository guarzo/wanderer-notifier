import { truncateLabel, getCommonOptions, validateChartDataArray } from './utils';

// Define common constants
const FONT_FAMILY = 'Montserrat, sans-serif';

const killsByShipTypeChartConfig = {
    type: 'bar',
    options: getCommonOptions('Kills by Ship Type'),
    processData: function (data) {
        if (!validateChartDataArray(data, 'Kills by Ship Type')) {
            return { labels: [], datasets: [] };
        }

        // Sort by kills in descending order
        data.sort((a, b) => b.kills - a.kills);

        // Limit to top 10 ship types
        const topData = data.slice(0, 10);

        // Extract labels and data
        const labels = topData.map(item => truncateLabel(item.ship_type, 15));
        const killsData = topData.map(item => item.kills);
        const iskData = topData.map(item => item.isk_destroyed / 1000000); // Convert to millions

        return {
            labels: labels,
            datasets: [
                {
                    label: 'Kills',
                    data: killsData,
                    backgroundColor: 'rgba(54, 162, 235, 0.7)',
                    borderColor: 'rgba(54, 162, 235, 1)',
                    borderWidth: 1,
                    yAxisID: 'y',
                },
                {
                    label: 'ISK Destroyed (Millions)',
                    data: iskData,
                    backgroundColor: 'rgba(255, 99, 132, 0.7)',
                    borderColor: 'rgba(255, 99, 132, 1)',
                    borderWidth: 1,
                    yAxisID: 'y1',
                }
            ]
        };
    },
};

export default killsByShipTypeChartConfig; 