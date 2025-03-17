// src/App.jsx
import React from "react";
import { BrowserRouter as Router, Routes, Route, Link } from "react-router-dom";
import Dashboard from "./components/Dashboard";
import ChartDashboard from "./components/ChartDashboard";
import { FaChartBar, FaHome } from "react-icons/fa";

function App() {
  return (
    <Router>
      <div className="min-h-screen bg-gradient-to-b from-blue-50 to-blue-100">
        <nav className="bg-gray-800 text-white p-4">
          <div className="max-w-7xl mx-auto flex justify-between items-center">
            <div className="text-xl font-bold">Wanderer Notifier</div>
            <div className="flex space-x-4">
              <Link to="/" className="flex items-center space-x-1 hover:text-indigo-300 transition-colors">
                <FaHome />
                <span>Home</span>
              </Link>
              <Link to="/charts" className="flex items-center space-x-1 hover:text-indigo-300 transition-colors">
                <FaChartBar />
                <span>Charts</span>
              </Link>
            </div>
          </div>
        </nav>
        
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/charts" element={<ChartDashboard />} />
        </Routes>
      </div>
    </Router>
  );
}

export default App;
