// src/App.jsx
import React, { useState, useEffect } from "react";
import { BrowserRouter as Router, Routes, Route, Link, Navigate } from "react-router-dom";
import Dashboard from "./components/Dashboard";
import { FaHome } from "react-icons/fa";

function App() {
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Fetch configuration when component mounts
    fetch('/charts/config')
      .then(response => response.json())
      .then(data => {
        setLoading(false);
      })
      .catch(error => {
        console.error('Error fetching config:', error);
        setLoading(false);
      });
  }, []);

  if (loading) {
    return <div className="min-h-screen bg-gradient-to-b from-blue-50 to-blue-100 flex items-center justify-center">
      <p className="text-lg">Loading application...</p>
    </div>;
  }

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
            </div>
          </div>
        </nav>
        
        <Routes>
          <Route path="/" element={<Dashboard />} />
        </Routes>
      </div>
    </Router>
  );
}

export default App;
