// static/js/chartConfigs/combinedLossesChartConfig.js
import { truncateLabel, getCommonOptions, validateChartDataArray } from './utils';

/**
 * Configuration for the Combined Losses Chart
 */
const combinedLossesChartConfig = {
    type: 'bar', // Base type for mixed charts
    options: getCommonOptions('Combined Losses', {
        plugins: {
            legend: {
                display: true,
                position: 'top',
                labels: { color: '#ffffff', font: { size: 12 } }
            },
            tooltip: {
                callbacks: {
                    label: function (context) {
                        const label = context.dataset.label || '';
                        const value = context.raw;
                        return `${label}: ${value.toLocaleString()}`;
                    },
                },
                mode: 'index', // Allows showing values for both bar and line charts in a single tooltip
                intersect: false, // Displays values for both datasets at the hovered index
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
                    font: {
                        size: 10, // Reduced font size for better fit
                    },
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
                stacked: false,
            },
            y: { // Primary y-axis for Losses Value
                beginAtZero: true,
                ticks: { color: '#ffffff' },
                grid: { color: '#444' },
                title: {
                    display: true,
                    text: 'Losses Value',
                    color: '#ffffff',
                    font: {
                        size: 14,
                        family: 'Montserrat, sans-serif',
                        weight: 'bold',
                    },
                },
                position: 'left',
                stacked: false,
            },
            y1: { // Secondary y-axis for Losses Count
                beginAtZero: true,
                ticks: { color: '#ffffff' },
                grid: { display: false }, // Hide grid lines for secondary y-axis
                title: {
                    display: true,
                    text: 'Losses Count',
                    color: '#ffffff',
                    font: {
                        size: 14,
                        family: 'Montserrat, sans-serif',
                        weight: 'bold',
                    },
                },
                position: 'right',
                stacked: false,
            },
        },
        responsive: true,
        maintainAspectRatio: false,
        layout: {
            padding: {
                left: 10,
                right: 10,
                top: 10,
                bottom: 10,
            },
        },
        interaction: {
            mode: 'index',
            intersect: false,
        },
        datasets: {
            bar: {
                barPercentage: 0.6, // Adjusted for better visibility
                categoryPercentage: 0.7,
            },
        },
    }),
    processData: function (data) {
        const chartName = 'Combined Losses Chart';
        if (!validateChartDataArray(data, chartName)) {
            // Return empty labels and datasets to trigger the noDataPlugin
            return { labels: [], datasets: [] };
        }
        // Sort data by LossesValue descending
        const sortedData = [...data].sort((a, b) => (b.LossesValue || 0) - (a.LossesValue || 0));

        // Limit to top 10 characters
        const topN = 10;
        const limitedData = sortedData.slice(0, topN);

        const labels = limitedData.map(item => item.CharacterName || 'Unknown');
        const truncatedLabels = labels.map(label => truncateLabel(label, 15)); // Truncate labels to 15 characters

        const lossesValue = limitedData.map(item => item.LossesValue || 0);
        const lossesCount = limitedData.map(item => item.LossesCount || 0);

        const datasets = [
            {
                label: 'Losses Value',
                type: 'bar', // Explicitly set type as bar
                data: lossesValue,
                backgroundColor: 'rgba(255, 99, 132, 0.7)',
                borderColor: 'rgba(255, 99, 132, 1)',
                borderWidth: 1,
                yAxisID: 'y', // Assign to primary y-axis
            },
            {
                label: 'Losses Count',
                type: 'line', // Set type as line
                data: lossesCount,
                backgroundColor: 'rgba(54, 162, 235, 0.7)',
                borderColor: 'rgba(54, 162, 235, 1)',
                borderWidth: 2,
                fill: false,
                yAxisID: 'y1', // Assign to secondary y-axis
                tension: 0.1, // Smoothness of the line
                pointRadius: 4, // Size of points on the line
            },
        ];

        return { labels: truncatedLabels, datasets, fullLabels: labels };
    },
};

export default combinedLossesChartConfig;
