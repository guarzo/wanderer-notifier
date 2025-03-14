import React from "react";
import { FaSync, FaCheckCircle, FaBell, FaPowerOff, FaCloud, FaHeart } from "react-icons/fa";
import "./Dashboard.css"; // CSS file for styling

const Dashboard = () => {
  return (
    <div className="dashboard-container">
      {/* Toolbar or top bar with Refresh and Revalidate License icons */}
      <div className="dashboard-toolbar">
        <button className="icon-button" title="Refresh Page">
          <FaSync />
        </button>
        <button className="icon-button" title="Revalidate License">
          <FaCheckCircle />
        </button>
      </div>

      {/* NOTIFICATION STATISTICS */}
      <section className="notification-stats">
        <div className="notification-stat">
          <h4>Today</h4>
          <p>42 notifications</p>
        </div>
        <div className="notification-stat">
          <h4>Weekly</h4>
          <p>210 notifications</p>
        </div>
        <div className="notification-stat">
          <h4>Monthly</h4>
          <p>804 notifications</p>
        </div>
      </section>

      {/* SYSTEM STATUS */}
      <section className="system-status">
        <h3>System Status</h3>
        <div className="system-status-details">
          <div className="status-item">
            <h4>CPU Usage</h4>
            <p>65%</p>
          </div>
          <div className="status-item">
            <h4>Memory Usage</h4>
            <p>3.2 GB / 8 GB</p>
          </div>
          <div className="status-item">
            <h4>Disk Space</h4>
            <p>120 GB / 250 GB</p>
          </div>
          <div className="status-item">
            <h4>Network</h4>
            <p>1.2 Gbps</p>
          </div>
        </div>
      </section>

      {/* FEATURE STATUS */}
      <section className="feature-status">
        <h3>Feature Status</h3>
        <div className="feature-items">
          <div className="feature-item">
            <span className="feature-name">Kill Notifications</span>
            <button className="icon-button" title="Test Kill Notifications">
              <FaPowerOff />
            </button>
          </div>
          <div className="feature-item">
            <span className="feature-name">Cloud Alerts</span>
            <button className="icon-button" title="Test Cloud Alerts">
              <FaCloud />
            </button>
          </div>
          <div className="feature-item">
            <span className="feature-name">Heartbeat Check</span>
            <button className="icon-button" title="Test Heartbeat">
              <FaHeart />
            </button>
          </div>
          <div className="feature-item">
            <span className="feature-name">Push Notifications</span>
            <button className="icon-button" title="Test Push Notifications">
              <FaBell />
            </button>
          </div>
        </div>
      </section>
    </div>
  );
};

export default Dashboard;

