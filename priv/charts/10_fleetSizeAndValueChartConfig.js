// static/js/chartConfigs/10_fleetSizeAndValueKilledOverTimeChartConfig.js

import { getCommonOptions, validateChartDataArray } from './utils';

/**
 * Configuration for the Fleet Size and Total Value Killed Over Time Chart
 */
const fleetSizeAndValueKilledOverTimeChartConfig = {
    type: 'line',
    options: getCommonOptions('Fleet Size and Total Value Killed Over Time', {
        scales: {
            x: {
                title: {
                    display: true,
                    text: 'Time',
                },
                ticks: {
                    color: '#ffffff',
                    autoSkip: true,
                    maxTicksLimit: 10, // Adjust based on data density
                },
                grid: { display: false },
            },
            y: {
                type: 'linear',
                display: true,
                position: 'left',
                title: {
                    display: true,
                    text: 'Total Value Killed',
                },
                ticks: {
                    color: '#ffffff',
                    beginAtZero: true, // Ensure y-axis starts at 0
                },
                min: 0, // Move min outside of ticks to enforce minimum value
                grid: { display: true, color: '#444444' },
            },
            y1: {
                type: 'linear',
                display: true,
                position: 'right',
                title: {
                    display: true,
                    text: 'Average Fleet Size',
                },
                ticks: {
                    color: '#ffffff',
                    beginAtZero: true, // Ensure y1-axis starts at 0
                },
                min: 0, // Move min outside of ticks to enforce minimum value
                grid: { drawOnChartArea: false }, // Prevent duplicate grid lines
            },
        },
        plugins: {
            legend: {
                display: true,
                position: 'top',
                labels: {
                    color: '#ffffff',
                },
            },
            tooltip: {
                callbacks: {
                    label: function(context) {
                        const label = context.dataset.label || '';
                        const value = context.parsed.y !== null ? context.parsed.y.toLocaleString() : '0';
                        return `${label}: ${value}`;
                    },
                },
            },
        },
        responsive: true,
        maintainAspectRatio: false,
    }),
    processData: function(data) {
        const chartName = 'Fleet Size and Total Value Killed Over Time';
        if (!validateChartDataArray(data, chartName)) {
            // Return empty data to trigger the noDataPlugin
            return { labels: [], datasets: [], noDataMessage: 'No data available for this chart.' };
        }

        // Map the correct fields
        const labels = data.map(item => {
            if (item.time) {
                // Format the time for better readability (e.g., '2024-03-01T00:00:00Z' to 'Mar 1')
                const date = new Date(item.time);
                const options = { month: 'short', day: 'numeric' };
                return date.toLocaleDateString(undefined, options);
            }
            return 'Unknown';
        });
        const fleetSizes = data.map(item => item.avg_fleet_size || 0);
        const totalValues = data.map(item => item.total_value || 0);

        // Check for 'Unknown' labels
        const allUnknown = labels.every(label => label === 'Unknown');
        if (allUnknown) {
            console.warn(`All labels for ${chartName} are 'Unknown'. Check data source.`);
        }

        return {
            labels: labels,
            datasets: [
                {
                    label: 'Total Value Killed',
                    data: totalValues,
                    borderColor: 'rgba(153, 102, 255, 1)',
                    backgroundColor: 'rgba(153, 102, 255, 0.2)',
                    fill: true, // Fill the area under the line
                    tension: 0.1, // Smoothness of the line
                    yAxisID: 'y', // Assign to left y-axis
                },
                {
                    label: 'Average Fleet Size',
                    data: fleetSizes,
                    borderColor: 'rgba(75, 192, 192, 1)',
                    backgroundColor: 'rgba(75, 192, 192, 0.2)',
                    fill: false, // No fill for the line
                    tension: 0.1,
                    yAxisID: 'y1', // Assign to right y-axis
                },
            ],
        };
    },
};

export default fleetSizeAndValueKilledOverTimeChartConfig;
