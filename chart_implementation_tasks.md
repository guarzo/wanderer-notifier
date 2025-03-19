# Chart Implementation Task List

## Horizontal Stacked Bar Chart Tasks

- [x] Update `ActivityChartAdapter` to use `horizontalBar` chart type
- [x] Configure proper stacking for datasets with `stack` property
- [x] Adjust chart options for Chart.js v2 compatibility (`xAxes`/`yAxes` arrays)
- [x] Remove incompatible `indexAxis` property (Chart.js v3+ only)
- [ ] Verify all three data elements display correctly in stacked format

## TPS Data Chart Adaptation

- [x] Update chart generation to use the new `/recent-tps-data` endpoint
- [x] Enhance error handling for empty API responses in chart generators
- [x] Add detailed logging with specific error messages for missing data
- [ ] Fix the 0..-2 range warnings in the `parse_value` function

## API & Routing Improvements

- [ ] Review SPA routing to prevent it from intercepting API requests
- [ ] Document the correct routing patterns for future API endpoints
- [ ] Add proper API versioning to avoid conflicts with frontend routes

## Testing & Validation

- [ ] Test all chart types with valid data
- [ ] Test all chart types with invalid/empty data
- [ ] Verify Discord notifications work properly with charts
- [ ] Create automated tests for chart generation
- [ ] Develop a test suite for API response handling

## Documentation & Standards

- [ ] Create documentation for chart configuration patterns
- [ ] Develop a chart styling guide for consistency
- [ ] Document Chart.js v2 specific requirements
- [ ] Create API endpoint documentation

## Future Enhancements

- [ ] Consider upgrading to Chart.js v3+ for better features
- [ ] Implement responsive chart designs for mobile viewing
- [ ] Add chart download/export functionality
- [ ] Create chart theme switching capability

## Known Issues

- The SPA router is intercepting API requests (see log: "Serving React app for path: /api/debug/ping")
- Chart.js v2 requires specific syntax for horizontal stacked bar charts
- Warnings in the `parse_value` function related to range syntax 