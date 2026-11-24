#!/usr/bin/env node
'use strict';

const { spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const pkg = require('../package.json');

const APP_NAME = 'PulseBar';
const INSTALL_DIR = path.join(os.homedir(), 'Applications');
const APP_PATH = path.join(INSTALL_DIR, `${APP_NAME}.app`);
const APP_BINARY = path.join(APP_PATH, 'Contents', 'MacOS', APP_NAME);
const BUNDLE_ID = 'dev.pulsebar.PulseBar';
const ZIP_PATH = path.join(__dirname, '..', 'dist', `${APP_NAME}.zip`);

const HELP = `PulseBar ${pkg.version} — live network speed, CPU and memory in your menu bar

Usage: npx pulsebar [command]

Commands:
  install     Install (or update) to ~/Applications and launch   (default)
  uninstall   Quit, remove the login item and delete the app
  start       Launch the installed app
  stop        Quit the running app
  version     Print the version
  help        Show this message
`;

function run(cmd, args, options = {}) {
  return spawnSync(cmd, args, { stdio: 'ignore', ...options });
}

function fail(message) {
  console.error(`✗ ${message}`);
  process.exit(1);
}

function checkPlatform() {
  if (process.platform !== 'darwin') fail('PulseBar runs on macOS only.');
  const result = run('sw_vers', ['-productVersion'], { encoding: 'utf8', stdio: 'pipe' });
  const major = parseInt(String(result.stdout || '').split('.')[0], 10);
  if (major && major < 13) fail(`PulseBar needs macOS 13 (Ventura) or later; this Mac has ${result.stdout.trim()}.`);
}

function isInstalled() {
  return fs.existsSync(APP_BINARY);
}

function stop() {
  // SIGTERM by exact process name; avoids AppleScript, which would trigger an Automation prompt.
  run('pkill', ['-x', APP_NAME]);
}

function start() {
  if (!isInstalled()) fail(`Not installed. Run: npx ${pkg.name}`);
  const result = run('open', [APP_PATH], { stdio: 'inherit' });
  if (result.status !== 0) fail('Could not launch PulseBar.');
}

function install() {
  checkPlatform();
  if (!fs.existsSync(ZIP_PATH)) fail(`Bundled app not found at ${ZIP_PATH}. Reinstall the package.`);

  const updating = isInstalled();
  stop();
  fs.mkdirSync(INSTALL_DIR, { recursive: true });
  fs.rmSync(APP_PATH, { recursive: true, force: true });

  // ditto keeps the bundle's symlinks, permissions and code signature intact.
  const unzip = run('ditto', ['-x', '-k', ZIP_PATH, INSTALL_DIR], { stdio: 'inherit' });
  if (unzip.status !== 0 || !isInstalled()) fail('Could not unpack PulseBar.');
  run('xattr', ['-dr', 'com.apple.quarantine', APP_PATH]);

  start();
  console.log(`✓ PulseBar ${pkg.version} ${updating ? 'updated' : 'installed'} → ${APP_PATH}`);
  console.log('  Look for the gauge icon in your menu bar. It starts at login (toggle in the panel).');
  console.log(`  Remove it any time with: npx ${pkg.name} uninstall`);
}

function uninstall() {
  if (isInstalled()) run(APP_BINARY, ['--unregister-login-item']);
  stop();
  fs.rmSync(APP_PATH, { recursive: true, force: true });
  run('defaults', ['delete', BUNDLE_ID]);
  console.log('✓ PulseBar removed (app, login item and preferences).');
}

const command = process.argv[2] || 'install';
switch (command) {
  case 'install':
  case 'update':
    install();
    break;
  case 'uninstall':
  case 'remove':
    uninstall();
    break;
  case 'start':
  case 'open':
    start();
    break;
  case 'stop':
  case 'quit':
    stop();
    break;
  case 'version':
  case '--version':
  case '-v':
    console.log(pkg.version);
    break;
  case 'help':
  case '--help':
  case '-h':
    console.log(HELP);
    break;
  default:
    console.error(`Unknown command: ${command}\n`);
    console.log(HELP);
    process.exit(1);
}
