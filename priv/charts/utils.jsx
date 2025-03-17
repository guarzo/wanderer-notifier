import { format, parseISO } from 'date-fns';


export function validateChartDataArray(data, chartName) {
    if (!Array.isArray(data) || data.length === 0) {
        console.warn(`No data for chart "${chartName}".`);
        return false;
    }
    return true;
}

export function getCommonOptions(titleText) {
    return {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            title: {
                display: false,
                text: titleText,
                font: { size: 18, weight: 'bold' },
                color: '#ffffff',
            },
            legend: {
                labels: { color: '#ffffff' }
            }
        },
        scales: {
            x: {
                ticks: { color: '#ffffff' },
                grid: { display: false },
            },
            y: {
                position: 'left',
                ticks: { color: '#ffffff' },
                grid: { display: false },
            },
            y1: {
                position: 'right',
                ticks: { color: '#ffffff' },
                grid: { drawOnChartArea: false },
            }
        }
    };
}



const predefinedColors = [
    '#FF6384', '#36A2EB', '#FFCE56', '#4BC0C0',
    '#9966FF', '#FF9F40', '#E7E9ED', '#76D7C4',
    '#C0392B', '#8E44AD', '#2ECC71', '#1ABC9C',
    '#3498DB', '#F1C40F', '#E67E22', '#95A5A6',
];

const shipColorMap = {};

/**
 * Assigns and retrieves a color for a given ship name.
 * @param {string} shipName - The name of the ship.
 * @returns {string} - The HEX color code.
 */
export function getShipColor(shipName) {
    if (shipColorMap[shipName]) {
        return shipColorMap[shipName];
    }
    const color = predefinedColors[Object.keys(shipColorMap).length % predefinedColors.length];
    shipColorMap[shipName] = color;
    return color;
}


/**
 * Returns a color from a predefined palette based on the index.
 * @param {number} index - The index to determine the color.
 * @returns {string} - The corresponding color in HEX format.
 */
export function getColor(index) {
    const colors = [
        '#FF6384', '#36A2EB', '#FFCE56', '#4BC0C0',
        '#9966FF', '#FF9F40', '#E7E9ED', '#76D7C4',
        '#C0392B', '#8E44AD', '#2ECC71', '#1ABC9C',
        '#3498DB', '#F1C40F', '#E67E22', '#95A5A6',
    ];
    return colors[index % colors.length];
}

export const noDataPlugin = {
    id: 'noData',
    afterDraw: function(chart) { // Changed from beforeDraw to afterDraw
        // Determine if the chart has no data
        const hasData = chart.data.datasets.some(dataset => {
            return dataset.data && dataset.data.length > 0 && dataset.data.some(value => {
                if (typeof value === 'object' && value !== null) {
                    return Object.values(value).some(val => val !== null && val !== undefined && val !== '');
                }
                return value !== null && value !== undefined && value !== '';
            });
        });

        if (!hasData) {
            // Retrieve the chart title
            const chartTitle = chart.options.plugins.title && chart.options.plugins.title.text ? chart.options.plugins.title.text : 'Unnamed Chart';

            // Log the chart title and data
            console.log(`No data for chart "${chartTitle}". Chart data:`, chart.data);

            const { ctx, width, height } = chart;
            ctx.save();
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.font = '20px Montserrat, sans-serif';
            ctx.fillStyle = '#ff4d4d'; // Customize as needed

            // Calculate position below the title
            const titleHeight = chart.options.plugins.title && chart.options.plugins.title.display ? 40 : 0; // Approximate title height
            const messageY = height / 2 + titleHeight / 2;

            // Determine the message to display
            let message = 'No data available for this chart.';
            if (chart.config.options.plugins.noData && chart.config.options.plugins.noData.message) {
                message = chart.config.options.plugins.noData.message;
            }


            ctx.fillText(message, width / 2, messageY);
            ctx.restore();
        }
    }
};

/**
 * Truncates a label to a specified maximum length, adding ellipsis if necessary.
 * @param {string} label - The original label.
 * @param {number} maxLength - The maximum allowed length.
 * @returns {string} - The truncated label.
 */
export function truncateLabel(label, maxLength) {
    if (label.length > maxLength) {
        return label.substring(0, maxLength - 3) + '...';
    }
    return label;
}


export function validateOurShipsUsedData(data, chartName) {
    if (typeof data !== 'object' || data === null) {
        console.warn(`Invalid data format for chart "${chartName}". Expected an object.`);
        return false;
    }

    const requiredKeys = ['Characters', 'ShipNames', 'SeriesData'];
    const hasAllKeys = requiredKeys.every(key => key in data);
    if (!hasAllKeys) {
        console.warn(`Incomplete data for chart "${chartName}". Missing keys: ${requiredKeys.filter(key => !(key in data)).join(', ')}`);
        return false;
    }

    if (!Array.isArray(data.Characters) || data.Characters.length === 0) {
        console.warn(`No characters data available for chart "${chartName}".`);
        return false;
    }
    if (!Array.isArray(data.ShipNames) || data.ShipNames.length === 0) {
        console.warn(`No ship names data available for chart "${chartName}".`);
        return false;
    }
    if (typeof data.SeriesData !== 'object' || Object.keys(data.SeriesData).length === 0) {
        console.warn(`No series data available for chart "${chartName}".`);
        return false;
    }

    return true;
}





