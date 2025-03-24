#!/usr/bin/env node

/**
 * This script watches the dist directory for changes and copies files to priv/static/app.
 * It ensures that the Vite build output is immediately available to the Elixir application.
 */

import fs from 'fs';
import path from 'path';
import { exec, spawn } from 'child_process';
import { fileURLToPath } from 'url';

// Get directory paths in ES module format
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Configuration
const distDir = path.resolve(__dirname, 'dist');
const targetDir = path.resolve(__dirname, '../priv/static/app');

// Ensure the target directory exists
if (!fs.existsSync(targetDir)) {
  console.log(`Creating target directory: ${targetDir}`);
  fs.mkdirSync(targetDir, { recursive: true });
}

// Initial copy of all files
console.log('Performing initial copy of all files...');
exec(`cp -r ${distDir}/* ${targetDir}/`, (error) => {
  if (error) {
    console.error(`Error during initial copy: ${error.message}`);
    return;
  }
  console.log('Initial copy completed successfully');
});

// Start the Vite build in watch mode
console.log('Starting Vite build in watch mode...');
const viteProcess = spawn('npm', ['run', 'watch'], { 
  stdio: 'inherit',
  shell: true
});

viteProcess.on('error', (error) => {
  console.error(`Error starting Vite: ${error.message}`);
});

// Watch for changes in the dist directory
console.log(`Watching for changes in ${distDir}`);
fs.watch(distDir, { recursive: true }, (eventType, filename) => {
  if (!filename) return;
  
  const sourcePath = path.join(distDir, filename);
  const targetPath = path.join(targetDir, filename);
  
  // Make sure the event is real and the file exists
  try {
    fs.statSync(sourcePath);
  } catch (e) {
    // File doesn't exist anymore, might be a deletion event
    return;
  }
  
  console.log(`File changed: ${filename}`);
  
  // Create directory if it doesn't exist
  const targetDirPath = path.dirname(targetPath);
  if (!fs.existsSync(targetDirPath)) {
    fs.mkdirSync(targetDirPath, { recursive: true });
  }
  
  // Copy file
  exec(`cp -r "${sourcePath}" "${targetPath}"`, (error) => {
    if (error) {
      console.error(`Error copying ${filename}: ${error.message}`);
      return;
    }
    console.log(`Copied ${filename} to ${targetPath}`);
  });
});

console.log('Watch and copy process started. Press Ctrl+C to stop.');

// Handle process termination
process.on('SIGINT', () => {
  console.log('Stopping watch and copy process...');
  viteProcess.kill();
  process.exit(0);
}); 