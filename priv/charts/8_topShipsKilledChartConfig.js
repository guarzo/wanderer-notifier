import { truncateLabel, getShipColor, getCommonOptions, validateChartDataArray } from './utils';

const topShipsKilledChartConfig = {
    type: 'wordCloud',
    options: {
        ...getCommonOptions('Top Ships Killed', {}),
        plugins: {
            ...getCommonOptions('Top Ships Killed', {}).plugins,
            legend: { display: false },
            tooltip: {
                callbacks: {
                    label: function (context) {
                        const word = context.label || 'Unknown';
                        const count = (context.raw / context.dataset.scalingFactor) || 0;
                        return `${word}: ${count.toLocaleString()} kills`;
                    },
                },
                mode: 'nearest',
                intersect: true,
                backgroundColor: '#000000',
                titleColor: '#ffffff',
                bodyColor: '#ffffff',
            },
        },
        scales: {
            x: { display: false },
            y: { display: false },
        },
        layout: { padding: 20 },
        animation: { duration: 0 },
        font: {
            weight: 'bold',
            family: 'Arial',
            size: function(context) {
                const containerWidth = context.chart.width;
                return containerWidth / 15;
            }
        },
        elements: {
            wordCloud: {
                minFontSize: 8,
                maxFontSize: 40,
                rotation: [0, 90],
                spacing: 2,
            },
        },
    },
    processData: function (data) {
        const chartName = 'Top Ships Killed Chart';
        if (!validateChartDataArray(data, chartName)) {
            return { labels: [], datasets: [] };
        }

        const mappedData = data.map(item => {
            if (!item || !item.Name || typeof item.KillCount !== 'number') {
                console.warn(`Invalid data point in "${chartName}":`, item);
                return null;
            }
            return { text: item.Name, weight: item.KillCount };
        }).filter(item => item !== null);

        const maxWords = 10;
        const limitedData = mappedData.slice(0, maxWords);

        const maxKillCount = Math.max(...limitedData.map(d => d.weight));
        const scalingFactor = maxKillCount > 0 ? 70 / maxKillCount : 10;

        const scaledData = limitedData.map(d => ({
            text: d.text,
            weight: d.weight * scalingFactor,
            color: getShipColor(d.text)
        }));

        const labels = scaledData.map(d => d.text);
        const weights = scaledData.map(d => d.weight);
        const rotations = scaledData.map(() => (Math.random() > 0.5 ? 0 : 90));

        const datasets = [{
            data: weights,
            color: scaledData.map(d => d.color),
            rotation: rotations,
            scalingFactor: scalingFactor,
        }];

        return { labels, datasets };
    },
};

export default topShipsKilledChartConfig;
