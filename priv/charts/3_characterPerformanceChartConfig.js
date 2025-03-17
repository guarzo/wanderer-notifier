// static/js/chartConfigs/characterPerformanceChartConfig.js

import { truncateLabel, getCommonOptions, validateChartDataArray } from './utils';

/**
 * Configuration for the Character Performance Chart
 */
const characterPerformanceChartConfig = {
    type: 'bar', // Base type
    options: getCommonOptions('Character Performance', {
        scales: {
            x: {
                stacked: true,
                ticks: { color: '#ffffff' },
                grid: { display: false },
            },
            y: {
                stacked: true,
                position: 'left',
                title: {
                    display: true,
                    text: 'Kills',
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
                title: {
                    display: true,
                    text: 'Points',
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
                    drawOnChartArea: false, // Only want grid lines for one axis
                },
            },
        },
        plugins: {
            tooltip: {
                mode: 'index', // Shows values for all datasets at the hovered index
                intersect: false, // Allows the tooltip to show both bar and line data
                callbacks: {
                    label: function (context) {
                        const datasetLabel = context.dataset.label || '';
                        const value = context.raw;
                        return `${datasetLabel}: ${value.toLocaleString()}`;
                    },
                },
            },
        },
    }),
    processData: function (data) {
        const chartName = 'Character Performance Chart';
        if (!validateChartDataArray(data, chartName)) {
            // Return empty labels and datasets to trigger the noDataPlugin
            return { labels: [], datasets: [] };
        }

        // Sort data by KillCount descending
        const sortedData = [...data].sort((a, b) => (b.KillCount || 0) - (a.KillCount || 0));

        // Limit to top 10 characters
        const topN = 10;
        const limitedData = sortedData.slice(0, topN);

        const labels = limitedData.map(item => item.CharacterName || item.Name || 'Unknown');
        const truncatedLabels = labels.map(label => truncateLabel(label, 15));

        const kills = limitedData.map(item => item.KillCount || 0);
        const soloKills = limitedData.map(item => item.SoloKills || 0);
        const points = limitedData.map(item => item.Points || 0);

        const datasets = [
            {
                label: 'Kills',
                type: 'bar',
                data: kills,
                backgroundColor: 'rgba(75, 192, 192, 0.7)',
                borderColor: 'rgba(75, 192, 192, 1)',
                borderWidth: 1,
                yAxisID: 'y',
                stack: 'killsStack', // Stack name for kills
            },
            {
                label: 'Solo Kills',
                type: 'bar',
                data: soloKills,
                backgroundColor: 'rgba(153, 102, 255, 0.7)',
                borderColor: 'rgba(153, 102, 255, 1)',
                borderWidth: 1,
                yAxisID: 'y',
                stack: 'killsStack', // Same stack name as Kills
            },
            {
                label: 'Points',
                type: 'line',
                data: points,
                backgroundColor: 'rgba(255, 159, 64, 0.7)',
                borderColor: 'rgba(255, 159, 64, 1)',
                borderWidth: 2,
                fill: false,
                yAxisID: 'y1',
                tension: 0.1,
                pointRadius: 4,
            },
        ];

        return { labels: truncatedLabels, datasets, fullLabels: labels };
    },
};

export default characterPerformanceChartConfig;
