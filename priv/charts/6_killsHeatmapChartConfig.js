import { getCommonOptions, validateChartDataArray } from './utils';

const hourLabels = Array.from({ length: 24 }, (_, i) => i.toString());
const dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

const killsHeatmapChartConfig = {
    type: 'matrix',
    options: {
        ...getCommonOptions('Kills Heatmap', {}),
        plugins: {
            ...getCommonOptions('Kills Heatmap', {}).plugins,
            legend: { display: false },
            tooltip: {
                callbacks: {
                    title: () => '',
                    label: (context) => {
                        const value = context.raw.v || 0;
                        const xIndex = context.raw.x; // hour index (0-23)
                        const yIndex = context.raw.y; // day index (0-6)
                        const xLabel = hourLabels[xIndex] || xIndex;
                        const yLabel = dayLabels[yIndex] || yIndex;
                        return `Day: ${yLabel}, Hour: ${xLabel}, Kills: ${value}`;
                    },
                },
            },
            datalabels: {
                display: false,
            },
        },
        scales: {
            x: {
                type: 'linear',
                min: 0,
                max: 23,
                ticks: {
                    color: '#ffffff',
                    stepSize: 1,
                    callback: function(value) {
                        // value is the numeric hour
                        return hourLabels[value] || value;
                    }
                },
                grid: { display: false },
                title: {
                    display: false,
                    text: 'Hour of Day',
                    color: '#ffffff',
                    font: { size: 14, family: 'Montserrat, sans-serif', weight: 'bold' },
                },
            },
            y: {
                type: 'linear',
                min: 0,
                max: 6,
                reverse: false,
                ticks: {
                    color: '#ffffff',
                    stepSize: 1,
                    callback: function(value) {
                        // value is the numeric day index
                        return dayLabels[value] || value;
                    }
                },
                grid: { display: false },
                title: {
                    display: false,
                    text: 'Day of Week',
                    color: '#ffffff',
                    font: { size: 14, family: 'Montserrat, sans-serif', weight: 'bold' },
                },
            },
        },
        elements: {
            rectangle: {
                borderWidth: 0,
            },
        },
        responsive: true,
        maintainAspectRatio: false,
    },
    processData: function (data) {
        const chartName = 'Kills Heatmap';

        if (!validateChartDataArray(data, chartName)) {
            return { labels: [], datasets: [], noDataMessage: 'No data available for this chart.' };
        }

        const yCount = 7;
        const xCount = 24;

        let maxKills = 0;
        const matrixData = [];

        for (let day = 0; day < yCount; day++) {
            for (let hour = 0; hour < xCount; hour++) {
                const kills = data[day][hour] || 0;
                if (kills > maxKills) maxKills = kills;
                matrixData.push({
                    x: hour,
                    y: day,
                    v: kills,
                    w: 20,
                    h: 20
                });
            }
        }

        const backgroundColors = matrixData.map(dp => {
            const kills = dp.v;
            if (kills > 0) {
                const alpha = 0.4 + (kills / maxKills) * 0.6;
                return `rgba(255,0,0,${alpha})`;
            } else {
                return 'rgba(0,0,0,0)';
            }
        });

        const dataset = {
            label: '',
            data: matrixData,
            backgroundColor: backgroundColors,
        };

        return { labels: [], datasets: [dataset] };
    },
};

export default killsHeatmapChartConfig;
