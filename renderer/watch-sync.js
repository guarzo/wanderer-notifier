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
const staticDir = path.resolve(__dirname, '../priv/static/app');

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

// Set up a timer to periodically sync the directories
const syncInterval = 1000; // 1 second
let lastRun = Date.now();

function syncDirectories() {
  const now = Date.now();
  
  // Don't run more often than the interval
  if (now - lastRun < syncInterval) return;
  lastRun = now;
  
  // Use rsync for more efficient directory syncing
  const syncProcess = spawn('cp', ['-r', 'dist/', '../priv/static/app/'], {
    stdio: 'inherit',
    shell: true
  });
  
  syncProcess.on('error', (err) => {
    console.error('Error syncing directories:', err);
  });
}

// Ensure initial build happens before watching
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