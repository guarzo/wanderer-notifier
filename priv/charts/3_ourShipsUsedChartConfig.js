import { truncateLabel, getCommonOptions, validateChartDataArray } from './utils';

// Define common constants
const FONT_FAMILY = 'Montserrat, sans-serif';

const ourShipsUsedChartConfig = {
    type: 'doughnut',
    options: getCommonOptions('Our Ships Used', {
        plugins: {
            legend: {
                position: 'right',
                labels: {
                    boxWidth: 15,
                    padding: 10,
                    font: {
                        size: 11,
                        family: FONT_FAMILY
                    }
                }
            }
        }
    }),
    processData: function (data) {
        if (!validateChartDataArray(data, 'Our Ships Used')) {
            return { labels: [], datasets: [] };
        }

        // Sort by count in descending order
        data.sort((a, b) => b.count - a.count);

        // Limit to top 10 ship types
        const topData = data.slice(0, 10);

        // Extract labels and data
        const labels = topData.map(item => truncateLabel(item.ship_type, 20));
        const counts = topData.map(item => item.count);

        // Generate colors
        const backgroundColors = [
            '#FF6384', '#36A2EB', '#FFCE56', '#4BC0C0', '#9966FF',
            '#FF9F40', '#8AC249', '#EA5F89', '#00D8B6', '#9B19F5'
        ];

        return {
            labels: labels,
            datasets: [
                {
                    data: counts,
                    backgroundColor: backgroundColors,
                    borderWidth: 1,
                    borderColor: '#ffffff'
                }
            ]
        };
    },
};

export default ourShipsUsedChartConfig; 