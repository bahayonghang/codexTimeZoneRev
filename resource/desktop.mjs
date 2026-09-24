import { spawn } from 'node:child_process';
import { copyFile, lstat, mkdir, rename, rm } from 'node:fs/promises';
import { delimiter, dirname, join, resolve } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

const resource = dirname(fileURLToPath(import.meta.url));
const repository = dirname(resource);
const environment = join(repository, 'environment');
const [action, platform, configured] = process.argv.slice(2);

function run(command, args, env = process.env) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: resource, env, stdio: 'inherit' });
    child.once('error', reject);
    child.once('exit', (code, signal) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} 执行失败：${signal || code}`));
    });
  });
}

function locked(error) {
  if (error && ['EPERM', 'EBUSY', 'EACCES'].includes(error.code)) {
    return new Error('请先退出正在运行的 Codex 时区启动器，再重新安装。');
  }
  return error;
}

async function replaceFile(dest, incoming) {
  const previous = `${dest}.old`;
  await rm(previous, { force: true });
  let moved = false;
  try {
    await rename(dest, previous);
    moved = true;
  } catch (error) {
    if (error.code !== 'ENOENT') {
      await rm(incoming, { force: true });
      throw locked(error);
    }
  }
  try {
    await rename(incoming, dest);
  } catch (error) {
    if (moved) await rename(previous, dest);
    throw locked(error);
  }
  await rm(previous, { force: true });
}

async function createWindowsShortcut(shortcut, target, workdir, env) {
  const staged = join(dirname(shortcut), '.CodexTimeZoneLauncher-install.lnk');
  const childEnv = {
    ...env,
    CODEX_TZ_SHORTCUT: staged,
    CODEX_TZ_INSTALL_EXE: target,
    CODEX_TZ_INSTALL_DIR: workdir,
  };
  const command = [
    "$ErrorActionPreference = 'Stop'",
    "$shell = New-Object -ComObject WScript.Shell",
    "$link = $shell.CreateShortcut($env:CODEX_TZ_SHORTCUT)",
    "$link.TargetPath = $env:CODEX_TZ_INSTALL_EXE",
    "$link.WorkingDirectory = $env:CODEX_TZ_INSTALL_DIR",
    "$link.Description = '选择时区并启动 Codex'",
    "$link.IconLocation = \"$env:CODEX_TZ_INSTALL_EXE,0\"",
    "$link.Save()",
  ].join('; ');
  await run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    command,
  ], childEnv);
  await replaceFile(shortcut, staged);
}

export async function installWindows(artifact, env = process.env) {
  if (!env.LOCALAPPDATA) throw new Error('无法确定 LocalAppData。');
  if (!env.APPDATA) throw new Error('无法确定 AppData。');
  const destDir = join(env.LOCALAPPDATA, 'Programs', 'CodexTimeZoneLauncher');
  const dest = join(destDir, 'CodexTimeZoneLauncher.exe');
  const incoming = `${dest}.new`;
  const shortcut = join(env.APPDATA, 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Codex 时区启动器.lnk');
  await mkdir(destDir, { recursive: true });
  await rm(incoming, { force: true });
  await copyFile(artifact, incoming);
  await replaceFile(dest, incoming);
  await mkdir(dirname(shortcut), { recursive: true });
  try {
    await createWindowsShortcut(shortcut, dest, destDir, env);
  } catch (error) {
    throw new Error(`程序已复制到 ${dest}，但开始菜单快捷方式创建失败：${error.message}`);
  }
  console.log(`已安装：${dest}`);
  console.log(`开始菜单：${shortcut}`);
}

export async function installMac(artifact) {
  const home = homedir();
  if (!home) throw new Error('无法确定用户主目录。');
  const root = join(home, 'Applications');
  const dest = join(root, 'Codex 时区启动器.app');
  const staging = join(root, '.CodexTimeZoneLauncher-install');
  const next = join(staging, 'next.app');
  const previous = join(staging, 'previous.app');
  await mkdir(staging, { recursive: true });
  await rm(next, { recursive: true, force: true });
  await run('/usr/bin/ditto', [artifact, next]);
  await run('/usr/bin/codesign', ['--verify', '--deep', '--strict', next]);
  await rm(previous, { recursive: true, force: true });
  let moved = false;
  try {
    await rename(dest, previous);
    moved = true;
  } catch (error) {
    if (error.code !== 'ENOENT') {
      await rm(staging, { recursive: true, force: true });
      throw locked(error);
    }
  }
  try {
    await rename(next, dest);
  } catch (error) {
    if (moved) await rename(previous, dest);
    throw locked(error);
  }
  await rm(previous, { recursive: true, force: true });
  await rm(staging, { recursive: true, force: true });
  console.log(`已安装：${dest}`);
}

async function main() {
  if (!['build', 'dev', 'start', 'install'].includes(action) || !['mac', 'win'].includes(platform)) {
    throw new Error('请使用 npm run build:mac / build:win、dev:mac / dev:win、start:mac / start:win 或 install:mac / install:win。');
  }
  const expected = platform === 'mac' ? 'darwin' : 'win32';
  if (process.platform !== expected) {
    throw new Error(`${platform} 命令需要在 ${platform === 'mac' ? 'macOS' : 'Windows'} 上执行；当前系统为 ${process.platform}。`);
  }
  const artifact = join(repository, platform === 'mac' ? 'Codex 时区启动器.app' : 'CodexTimeZoneLauncher.exe');
  if (action === 'start' || action === 'install') {
    await lstat(artifact).catch(() => { throw new Error(`请先执行 npm run build:${platform}。`); });
    if (action === 'start') {
      if (platform === 'mac') await run('/usr/bin/open', [artifact]);
      else {
        const child = spawn(artifact, [], { cwd: repository, detached: true, stdio: 'ignore' });
        await new Promise((resolve, reject) => { child.once('spawn', resolve); child.once('error', reject); });
        child.unref();
      }
      return;
    }
    if (platform === 'mac') await installMac(artifact);
    else await installWindows(artifact);
    return;
  }
  if (platform === 'win' && configured !== '--configured') {
    await run('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', join(resource, 'backend/win/desktop.ps1'), action]);
    return;
  }
  const env = { ...process.env };
  env.npm_config_cache = join(environment, 'npm-cache');
  env.CARGO_HOME = join(environment, platform === 'mac' ? 'macos/cargo' : 'cargo');
  env.CARGO_TARGET_DIR = join(environment, platform === 'mac' ? 'macos/cargo-target' : 'cargo-target');
  if (platform === 'mac') {
    env.PATH = ['/opt/homebrew/bin', '/usr/local/bin', dirname(process.execPath), env.PATH].filter(Boolean).join(delimiter);
  }
  if (env.CODEX_TZ_PROXY) env.HTTP_PROXY = env.HTTPS_PROXY = env.CODEX_TZ_PROXY;
  if (env.CARGO_BUILD_TARGET) throw new Error('平台构建使用本机目标，请先取消 CARGO_BUILD_TARGET。');
  const cli = join(resource, 'node_modules/@tauri-apps/cli/tauri.js');
  await lstat(cli).catch(() => { throw new Error('缺少依赖，请在 resource 目录先执行 npm ci。'); });
  const icons = platform === 'mac'
    ? ['icons/32x32.png', 'icons/128x128.png', 'icons/128x128@2x.png', 'icons/icon.icns']
    : ['icons/icon.ico'];
  const args = [cli, action, '--config', JSON.stringify({ bundle: { icon: icons } })];
  if (action === 'build') args.push(...(platform === 'mac' ? ['--bundles', 'app'] : ['--no-bundle']), '--', '--locked');
  if (action === 'dev') args.push('--additional-watch-folders', join(resource, 'backend', platform), '--additional-watch-folders', join(resource, 'backend', 'common.rs'), '--additional-watch-folders', join(resource, 'backend', 'zones.json'));
  await run(process.execPath, args, env);
  if (action === 'build') {
    const release = join(env.CARGO_TARGET_DIR, 'release');
    if (platform === 'mac') {
      // Replace the app as a whole so stale resources cannot survive a rebuild.
      const staging = join(resource, 'src-tauri/target/publish');
      const backup = join(staging, 'previous.app');
      const next = join(staging, 'next.app');
      await mkdir(staging, { recursive: true });
      await rm(next, { recursive: true, force: true });
      await run('/usr/bin/ditto', [join(release, 'bundle/macos/Codex 时区启动器.app'), next]);
      // The linker signs the executable; sign the complete local app bundle too.
      if (!env.APPLE_SIGNING_IDENTITY) await run('/usr/bin/codesign', ['--force', '--sign', '-', next]);
      await run('/usr/bin/codesign', ['--verify', '--deep', '--strict', next]);
      await rm(backup, { recursive: true, force: true });
      let moved = false;
      try { await rename(artifact, backup); moved = true; }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
      try { await rename(next, artifact); }
      catch (error) { if (moved) await rename(backup, artifact); throw error; }
      await rm(backup, { recursive: true, force: true });
    } else {
      await copyFile(join(release, 'codextimezonerev.exe'), artifact);
    }
    console.log(`已生成：${artifact}`);
  }
}

function invokedDirectly() {
  const entry = process.argv[1];
  if (!entry) return false;
  return import.meta.url === pathToFileURL(resolve(entry)).href;
}

if (invokedDirectly()) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
