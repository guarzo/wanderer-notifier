import { truncateLabel, getShipColor, getCommonOptions, validateOurShipsUsedData } from './utils';

const ourShipsUsedChartConfig = {
    type: 'bar',
    options: {
        // Start with base options
        ...getCommonOptions('Our Ships Used', {}),
        // Override indexAxis and stacking here
        indexAxis: 'y',
        scales: {
            x: {
                stacked: true,
                ticks: { color: '#ffffff' },
                grid: { display: false },
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
            y: {
                stacked: true,
                ticks: {
                    color: '#ffffff',
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
        },
        plugins: {
            legend: { display: false }, // No legend for this chart
            tooltip: {
                mode: 'nearest',
                intersect: true,
                callbacks: {
                    label: function (context) {
                        const value = context.parsed.x !== undefined ? context.parsed.x : context.parsed.y;
                        const shipName = context.dataset.label || '';
                        return `${shipName}: ${value} Kills`;
                    },
                },
            },
            datalabels: {
                color: '#ffffff',
                anchor: 'end',
                align: 'right',
                formatter: (value) => `${value}`,
                font: {
                    size: 10,
                    weight: 'bold',
                },
            },
        },
        responsive: true,
        maintainAspectRatio: false,
    },
    processData: function (data) {
        const chartName = 'Our Ships Used Chart';
        if (!validateOurShipsUsedData(data, chartName)) {
            return { labels: [], datasets: [] };
        }

        const characters = data.Characters || [];
        const shipNames = data.ShipNames || [];
        const seriesData = data.SeriesData || {};

        const MAX_SHIPS = 10;
        const MAX_CHARACTERS = 15;

        const shipUsage = shipNames.map(shipName => {
            const total = seriesData[shipName]?.reduce((a, b) => a + b, 0) || 0;
            return { shipName, total };
        });

        const topShips = shipUsage
            .sort((a, b) => b.total - a.total)
            .slice(0, MAX_SHIPS)
            .map(ship => ship.shipName);

        const characterUsage = characters.map((char, index) => {
            let total = 0;
            topShips.forEach(ship => {
                total += seriesData[ship]?.[index] || 0;
            });
            return { character: char, total };
        });

        const topCharacters = characterUsage
            .sort((a, b) => b.total - a.total)
            .slice(0, MAX_CHARACTERS)
            .map(item => item.character);

        const topCharacterIndices = topCharacters.map(char => characters.indexOf(char)).filter(index => index !== -1);
        const labels = topCharacters.map(label => truncateLabel(label, 10));

        const datasets = topShips.map(shipName => ({
            label: shipName,
            data: topCharacterIndices.map(index => seriesData[shipName]?.[index] || 0),
            backgroundColor: getShipColor(shipName),
            borderColor: '#ffffff',
            borderWidth: 1,
        }));

        return { labels, datasets };
    },
};

export default ourShipsUsedChartConfig;
