// tailwind.config.cjs
const path = require("path");

module.exports = {
  content: [
    path.join(__dirname, "index.html"),
    path.join(__dirname, "src/**/*.{js,jsx,ts,tsx}"),
  ],
  safelist: [
    'min-h-screen',
    'bg-gray-50',
    'bg-gradient-to-b',
    'from-sky-100',
    'to-violet-50',
    // Add any other classes that are used dynamically or not detected automatically
  ],
  theme: {
    extend: {},
  },
  plugins: [],
};
