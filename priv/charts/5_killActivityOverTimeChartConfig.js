import { getCommonOptions, validateChartDataArray } from './utils';
import { parseISO } from 'date-fns';

const killActivityChartConfig = {
    type: 'line',
    options: {
        ...getCommonOptions('Kill Activity Over Time', {}),
        plugins: {
            ...getCommonOptions('Kill Activity Over Time', {}).plugins,
            legend: { display: false }, // Override legend here
            tooltip: {
                callbacks: {
                    label: function (context) {
                        const label = context.dataset.label || '';
                        const value = context.parsed.y !== undefined ? context.parsed.y : context.parsed.x;
                        return `${label}: ${value}`;
                    },
                },
            },
            datalabels: {
                color: '#ffffff',
                align: 'top',
                formatter: (value) => `${value.y}`,
                font: {
                    size: 10,
                    weight: 'bold',
                },
            },
        },
        scales: {
            x: {
                type: 'time',
                time: {
                    parser: (val) => parseISO(val),
                    unit: 'day',
                    tooltipFormat: 'MM/dd',
                    displayFormats: {
                        day: 'MM/dd',
                    },
                },
                ticks: { color: '#ffffff' },
                grid: { color: '#444' },
                title: {
                    display: true,
                    text: 'Time',
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
                ticks: { color: '#ffffff' },
                grid: { color: '#444' },
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
            },
        },
        responsive: true,
        maintainAspectRatio: false,
    },
    processData: function (data) {
        const chartName = 'Kill Activity Over Time Chart';

        data = data.filter(item => {
            const t = new Date(item.Time).getTime();
            // e.g. ignore if date < year 2000 or something
            return t > Date.parse('2000-01-01T00:00:00Z');
        });


        if (!validateChartDataArray(data, chartName)) {
            return { labels: [], datasets: [], noDataMessage: 'No data available for this chart.' };
        }

        const dataPoints = data.map(item => ({ x: item.Time, y: item.Kills || 0 }));

        if (dataPoints.length < 3) {
            console.warn(`Not enough data points (${dataPoints.length}) for ${chartName}.`);
            return { labels: [], datasets: [], noDataMessage: 'Not enough data to display the chart.' };
        }

        const datasets = [{
            label: 'Kills Over Time',
            data: dataPoints,
            borderColor: 'rgba(255, 77, 77, 1)',
            backgroundColor: 'rgba(255, 77, 77, 0.5)',
            fill: true,
            tension: 0.4,
            pointBackgroundColor: 'rgba(255, 77, 77, 1)',
            pointBorderColor: '#fff',
            pointHoverBackgroundColor: '#fff',
            pointHoverBorderColor: 'rgba(255, 77, 77, 1)',
        }];

        return { labels: [], datasets };
    },
};

export default killActivityChartConfig;
