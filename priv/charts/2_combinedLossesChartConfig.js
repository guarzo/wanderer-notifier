// static/js/chartConfigs/combinedLossesChartConfig.js
import { truncateLabel, getCommonOptions, validateChartDataArray } from './utils';

// Define common constants
const FONT_FAMILY = 'Montserrat, sans-serif';

/**
 * Configuration for the Combined Losses Chart
 */
const combinedLossesChartConfig = {
    type: 'bar',
    options: getCommonOptions('Combined Losses'),
    processData: function (data) {
        if (!validateChartDataArray(data, 'Combined Losses')) {
            return { labels: [], datasets: [] };
        }

        // Sort by total losses in descending order
        data.sort((a, b) => b.total_losses - a.total_losses);

        // Limit to top 10 characters
        const topData = data.slice(0, 10);

        // Extract labels and data
        const labels = topData.map(item => truncateLabel(item.character_name, 15));
        const shipLossesData = topData.map(item => item.ship_losses);
        const podLossesData = topData.map(item => item.pod_losses);

        return {
            labels: labels,
            datasets: [
                {
                    label: 'Ship Losses',
                    data: shipLossesData,
                    backgroundColor: 'rgba(255, 99, 132, 0.7)',
                    borderColor: 'rgba(255, 99, 132, 1)',
                    borderWidth: 1,
                },
                {
                    label: 'Pod Losses',
                    data: podLossesData,
                    backgroundColor: 'rgba(54, 162, 235, 0.7)',
                    borderColor: 'rgba(54, 162, 235, 1)',
                    borderWidth: 1,
                }
            ]
        };
    },
};

export default combinedLossesChartConfig;
