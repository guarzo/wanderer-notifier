// tps/chartConfigs/index.js

import damageFinalBlowsChartConfig from './1_damageFinalBlowsChartConfig.js';
import ourShipsUsedChartConfig from './4_ourShipsUsedChartConfig.js';
import killActivityOverTimeChartConfig from './5_killActivityOverTimeChartConfig.js';
import killsHeatmapChartConfig from './6_killsHeatmapChartConfig.js';
import ratioAndEfficiencyChartConfig from './7_ratioAndEfficiency.js';
import topShipsKilledChartConfig from './8_topShipsKilledChartConfig.js';
import victimsByCorporationChartConfig from './9_victimsByCorpChartConfig.js';
import fleetSizeAndValueKilledOverTimeChartConfig from './10_fleetSizeAndValueChartConfig.js';
import characterPerformanceChartConfig from './3_characterPerformanceChartConfig.js';
import combinedLossesChartConfig from './2_combinedLossesChartConfig.js';

const chartConfigs = {
    characterDamageAndFinalBlowsChart: damageFinalBlowsChartConfig,
    ourShipsUsedChart: ourShipsUsedChartConfig,
    killActivityOverTimeChart: killActivityOverTimeChartConfig,
    killsHeatmapChart: killsHeatmapChartConfig,
    killToLossRatioChart: ratioAndEfficiencyChartConfig,
    topShipsKilledChart: topShipsKilledChartConfig,
    victimsByCorporationChart: victimsByCorporationChartConfig,
    fleetSizeAndValueKilledOverTimeChart: fleetSizeAndValueKilledOverTimeChartConfig,
    characterPerformanceChart: characterPerformanceChartConfig,
    combinedLossesChart: combinedLossesChartConfig,
};

export default chartConfigs;
