import { truncateLabel, getColor, getCommonOptions, validateChartDataArray } from './utils';

const killToLossRatioChartConfig = {
    type: 'bar',
    options: getCommonOptions('Kill-to-Loss Ratio and ISK Efficiency', {
        plugins: {
            legend: {
                display: true,
                position: 'top',
            },
            tooltip: {
                callbacks: {
                    label: function (context) {
                        const index = context.dataIndex;
                        const datasetLabel = context.dataset.label || '';
                        const value = context.parsed.y !== undefined ? context.parsed.y.toFixed(2) : '0.00';

                        // Pull the kills/losses from additionalData
                        const kills = context.chart.config.data.additionalData.kills[index] || 0;
                        const losses = context.chart.config.data.additionalData.losses[index] || 0;

                        if (datasetLabel === 'Kill-to-Loss Ratio') {
                            // Show ratio along with Kills, Losses
                            return `${datasetLabel}: ${value} (Kills: ${kills}, Losses: ${losses})`;
                        } else if (datasetLabel === 'ISK Efficiency (%)') {
                            // Show ISK Efficiency plus Kills, Losses
                            return `${datasetLabel}: ${value}% (Kills: ${kills}, Losses: ${losses})`;
                        } else {
                            // Fallback for any other datasets
                            return `${datasetLabel}: ${value}`;
                        }
                    },
                },
            },
        },
        scales: {
            x: {
                type: 'category',
                ticks: {
                    color: '#ffffff',
                    maxRotation: 45,
                    minRotation: 45,
                    autoSkip: false,
                },
                grid: { display: false },
                title: {
                    display: true,
                    text: 'Characters',
                    color: '#ffffff',
                    font: {
                        size: 14,
                        family: 'Montserrat, sans-serif',
                        weight: 'bold',
                    },
                },
            },
            y: {
                beginAtZero: true,
                position: 'left',
                title: {
                    display: true,
                    text: 'Kill-to-Loss Ratio',
                    color: '#ffffff',
                    font: {
                        size: 14,
                        family: 'Montserrat, sans-serif',
                        weight: 'bold',
                    },
                },
                ticks: {
                    color: '#ffffff',
                },
                grid: { color: '#444' },
            },
            y1: {
                beginAtZero: true,
                position: 'right',
                suggestedMin: 0,   // Start at 0%
                suggestedMax: 100, // Helps visualize typical 0-100% range
                title: {
                    display: true,
                    text: 'ISK Efficiency (%)',
                    color: '#ffffff',
                    font: {
                        size: 14,
                        family: 'Montserrat, sans-serif',
                        weight: 'bold',
                    },
                },
                ticks: {
                    color: '#ffffff',
                },
                grid: {
                    drawOnChartArea: false,
                },
            },
        },
    }),
    processData: function (data) {
        const chartName = 'Kill-to-Loss Ratio and ISK Efficiency Chart';
        if (!validateChartDataArray(data, chartName)) {
            return {
                labels: [],
                datasets: [],
                noDataMessage: 'No data available for this chart.',
            };
        }

        // Sort data once, by ratio (descending)
        const sortedData = [...data].sort((a, b) => (b.Ratio || 0) - (a.Ratio || 0));

        // Keep only top 20
        const maxDisplay = 20;
        const limitedData = sortedData.slice(0, maxDisplay);

        // Require at least 3 data points for meaningful display
        if (limitedData.length < 3) {
            console.warn(`Not enough data points (${limitedData.length}) for ${chartName}.`);
            return {
                labels: [],
                datasets: [],
                noDataMessage: 'Not enough data to display the chart.',
            };
        }

        // Prepare arrays for chart
        const labels = limitedData.map((item) => item.CharacterName || 'Unknown');
        const truncatedLabels = labels.map((label) => truncateLabel(label, 15));

        const ratios = limitedData.map((item) => item.Ratio || 0);
        const efficiencies = limitedData.map((item) => item.Efficiency || 0);
        const kills = limitedData.map((item) => item.Kills || 0);
        const losses = limitedData.map((item) => item.Losses || 0);

        const datasets = [
            {
                type: 'bar',
                label: 'Kill-to-Loss Ratio',
                data: ratios,
                backgroundColor: ratios.map((ratio, i) => getColor(i)),
                borderColor: 'rgba(75, 192, 192, 1)',
                borderWidth: 1,
                yAxisID: 'y',
            },
            {
                type: 'line',
                label: 'ISK Efficiency (%)',
                data: efficiencies,
                borderColor: 'rgba(255, 99, 132, 1)',
                backgroundColor: 'rgba(255, 99, 132, 0.2)',
                borderWidth: 2,
                fill: false,
                yAxisID: 'y1',
            },
        ];

        // Additional arrays for the tooltip
        const additionalData = {
            kills: kills,
            losses: losses,
        };

        // Return data in correct format for Chart.js
        return {
            labels: truncatedLabels,
            datasets: datasets,
            additionalData: additionalData,
        };
    },
};

export default killToLossRatioChartConfig;
