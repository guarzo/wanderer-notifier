#!/usr/bin/env node

/**
 * This script builds the Vite project and watches for rebuilt files,
 * copying them to the Elixir static directory automatically.
 */

import { spawn } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// Get directory paths in ES module format
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Paths
const distDir = path.resolve(__dirname, 'dist');
const staticDir = path.resolve(__dirname, '../priv/static/app');

// Flag to track last modification times
let lastSyncTime = 0;
let initialSyncDone = false;

// Make sure the target directory exists
console.log(`Ensuring target directory exists: ${staticDir}`);
if (!fs.existsSync(staticDir)) {
  fs.mkdirSync(staticDir, { recursive: true });
}

// Build and watch command - using shell directly for simpler implementation
console.log('Starting Vite build with watch...');

// Run Vite in watch mode
const cmd = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const vite = spawn(cmd, ['run', 'watch'], { 
  stdio: 'inherit', 
  shell: true
});

// Add a file watcher on dist directory
console.log('Setting up watcher for changes...');

// Set up a timer to periodically check for changes
const syncInterval = 2000; // 2 seconds
let lastRun = Date.now();

function getNewestFileTime(dir) {
  if (!fs.existsSync(dir)) return 0;

  try {
    const files = fs.readdirSync(dir, { withFileTypes: true });
    let latestTime = 0;

    for (const file of files) {
      const fullPath = path.join(dir, file.name);

      if (file.isDirectory()) {
        const newestInDir = getNewestFileTime(fullPath);
        if (newestInDir > latestTime) latestTime = newestInDir;
      } else {
        const stats = fs.statSync(fullPath);
        if (stats.mtimeMs > latestTime) latestTime = stats.mtimeMs;
      }
    }

    return latestTime;
  } catch (err) {
    console.error('Error checking file times:', err);
    return 0;
  }
}

function syncDirectories() {
  const now = Date.now();
  
  // Don't run more often than the interval
  if (now - lastRun < syncInterval) return;
  lastRun = now;
  
  // Check if dist directory exists before attempting to copy
  if (!fs.existsSync(distDir)) {
    if (!initialSyncDone) {
      console.log(`Waiting for dist directory to be created...`);
    }
    return;
  }

  // Check if files have been modified since last sync
  const newestTime = getNewestFileTime(distDir);
  if (newestTime <= lastSyncTime && initialSyncDone) {
    return; // No changes since last sync
  }

  // Use cp -r for directory copying
  const syncCommand = process.platform === 'win32'
    ? `xcopy /E /Y /I "${distDir}\\*" "${staticDir}"`
    : `cp -r ${distDir}/* ${staticDir}/`;

  const syncProcess = spawn(syncCommand, {
    stdio: 'inherit',
    shell: true
  });
  
  syncProcess.on('error', (err) => {
    console.error('Error syncing directories:', err);
  });

  syncProcess.on('close', (code) => {
    if (code === 0) {
      if (!initialSyncDone) {
        console.log(`✅ Initial sync completed`);
        initialSyncDone = true;
      } else {
        console.log(`✓ Files synced to backend`);
      }

      // Update the last sync time
      lastSyncTime = now;
    } else {
      console.error(`❌ Sync failed with code ${code}`);
    }
  });
}

// Initial delay to allow first build to complete
console.log('Waiting for initial build...');
setTimeout(() => {
  // Initial sync
  syncDirectories();
  
  // Set up interval for checking for changes
  setInterval(syncDirectories, syncInterval);
  
  console.log('Watch and sync process active. Press Ctrl+C to stop.');
}, 5000);

// Handle process termination
process.on('SIGINT', () => {
  console.log('Stopping watch process...');
  vite.kill();
  process.exit(0);
});

process.on('exit', () => {
  vite.kill();
}); 