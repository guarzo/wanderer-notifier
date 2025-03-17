import { getCommonOptions, validateChartDataArray } from './utils';

const victimsByCorporationChartConfig = {
    type: 'bar',
    options: {
        ...getCommonOptions('Victims by Corporation', {}),
        plugins: {
            ...getCommonOptions('Victims by Corporation', {}).plugins,
            legend: { display: false }, // Ensure no legend
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
        scales: {
            x: {
                title: { display: false, text: 'Corporation' },
                ticks: {
                    color: '#ffffff',
                    autoSkip: false,
                    maxRotation: 90,
                    minRotation: 45,
                },
                grid: { display: false },
            },
            y: {
                title: { display: false, text: 'Number of Victims' },
                ticks: {
                    color: '#ffffff',
                    beginAtZero: true,
                },
                grid: { display: true, color: '#444444' },
            },
        },
        responsive: true,
        maintainAspectRatio: false,
    },
    processData: function(data) {
        const chartName = 'Victims by Corporation';
        if (!validateChartDataArray(data, chartName)) {
            return { labels: [], datasets: [], noDataMessage: 'No data available for this chart.' };
        }

        const labels = data.map(item => item.name || 'Unknown');
        const victims = data.map(item => item.kill_count || 0);

        const count = labels.length;
        const backgroundColors = generateDistinctColors(count);
        const borderColors = backgroundColors.map(color =>
            color.replace(/rgba\((\d+),\s*(\d+),\s*(\d+),\s*[\d.]+\)/, 'rgba($1, $2, $3, 1)')
        );

        return {
            labels: labels,
            datasets: [{
                label: 'Number of Victims',
                data: victims,
                backgroundColor: backgroundColors,
                borderColor: borderColors,
                borderWidth: 1,
            }]
        };

        function generateDistinctColors(count) {
            const colors = [];
            const saturation = 70;
            const lightness = 50;

            for (let i = 0; i < count; i++) {
                const hue = Math.floor(Math.random() * 360);
                const alpha = 0.6;
                colors.push(`rgba(${hslToRgb(hue, saturation, lightness)}, ${alpha})`);
            }

            return ensureUniqueColors(colors);
        }

        function hslToRgb(h, s, l) {
            s /= 100;
            l /= 100;

            const c = (1 - Math.abs(2 * l - 1)) * s;
            const hh = h / 60;
            const x = c * (1 - Math.abs((hh % 2) - 1));

            let r = 0, g = 0, b = 0;
            if (0 <= hh && hh < 1) { r = c; g = x; b = 0; }
            else if (1 <= hh && hh < 2) { r = x; g = c; b = 0; }
            else if (2 <= hh && hh < 3) { r = 0; g = c; b = x; }
            else if (3 <= hh && hh < 4) { r = 0; g = x; b = c; }
            else if (4 <= hh && hh < 5) { r = x; g = 0; b = c; }
            else if (5 <= hh && hh < 6) { r = c; g = 0; b = x; }

            const m = l - c / 2;
            r = Math.round((r + m) * 255);
            g = Math.round((g + m) * 255);
            b = Math.round((b + m) * 255);

            return `${r}, ${g}, ${b}`;
        }

        function ensureUniqueColors(colors) {
            const uniqueColors = [];
            const colorSet = new Set();

            for (let color of colors) {
                if (!colorSet.has(color)) {
                    colorSet.add(color);
                    uniqueColors.push(color);
                } else {
                    let newColor;
                    do {
                        const hue = Math.floor(Math.random() * 360);
                        const saturation = 70;
                        const lightness = 50;
                        const alpha = 0.6;
                        newColor = `rgba(${hslToRgb(hue, saturation, lightness)}, ${alpha})`;
                    } while (colorSet.has(newColor));
                    colorSet.add(newColor);
                    uniqueColors.push(newColor);
                }
            }

            return uniqueColors;
        }
    },
};

export default victimsByCorporationChartConfig;
