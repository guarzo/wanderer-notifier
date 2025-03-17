import { getCommonOptions, validateChartDataArray } from './utils';

const damageFinalBlowsChartConfig = {
    type: 'bar',
    options: getCommonOptions('Top Damage Done and Final Blows'),
    processData: function (data) {
        const chartName = 'Damage Done and Final Blows';
        if (!validateChartDataArray(data, chartName)) {
            return { labels: [], datasets: [] };
        }

        const sortedData = [...data].sort((a, b) => (b.DamageDone || 0) - (a.DamageDone || 0));
        const topN = 20;
        const limitedData = sortedData.slice(0, topN);
        const labels = limitedData.map(item => item.Name || 'Unknown');

        const damageData = limitedData.map(item => item.DamageDone || 0);
        const finalBlowsData = limitedData.map(item => item.FinalBlows || 0);

        const datasets = [
            {
                label: 'Damage Done',
                type: 'bar',
                data: damageData,
                backgroundColor: 'rgba(255, 77, 77, 0.7)',
                borderColor: 'rgba(255, 77, 77, 1)',
                borderWidth: 1,
                yAxisID: 'y',
            },
            {
                label: 'Final Blows',
                type: 'line',
                data: finalBlowsData,
                backgroundColor: 'rgba(54, 162, 235, 0.7)',
                borderColor: 'rgba(54, 162, 235, 1)',
                borderWidth: 2,
                fill: false,
                yAxisID: 'y1',
                tension: 0.1,
                pointRadius: 4,
            },
        ];

        return { labels, datasets };
    },
};

export default damageFinalBlowsChartConfig;
