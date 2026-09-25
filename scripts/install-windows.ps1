param(
    [string]$Source = '',
    [string]$InstallRoot = '',
    [string]$ShortcutPath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path)
}

function Test-PathWithin([string]$Path, [string]$Root) {
    $separator = [IO.Path]::DirectorySeparatorChar
    $fullPath = (Get-FullPath $Path).TrimEnd([char[]]@($separator, [IO.Path]::AltDirectorySeparatorChar))
    $fullRoot = (Get-FullPath $Root).TrimEnd([char[]]@($separator, [IO.Path]::AltDirectorySeparatorChar))
    return $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($fullRoot + $separator, [StringComparison]::OrdinalIgnoreCase)
}

function New-Shortcut([string]$Path, [string]$Target, [string]$WorkingDirectory) {
    $shell = $null
    $shortcut = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($Path)
        $shortcut.TargetPath = $Target
        $shortcut.WorkingDirectory = $WorkingDirectory
        $shortcut.Description = '选择时区并启动 Codex'
        $shortcut.IconLocation = "$Target,0"
        $shortcut.Save()
    } finally {
        if ($null -ne $shortcut -and [Runtime.InteropServices.Marshal]::IsComObject($shortcut)) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut)
        }
        if ($null -ne $shell -and [Runtime.InteropServices.Marshal]::IsComObject($shell)) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
    }
}

if (!$Source) {
    $Source = Join-Path $projectRoot 'flutter_app\build\windows\x64\runner\Release'
}
if (!$InstallRoot) {
    if (!$env:LOCALAPPDATA) { throw '无法确定当前用户的 LocalAppData。' }
    $InstallRoot = Join-Path $env:LOCALAPPDATA 'Programs\CodexTimeZoneLauncher'
}
if (!$ShortcutPath) {
    if (!$env:APPDATA) { throw '无法确定当前用户的 AppData\Roaming。' }
    $ShortcutPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Codex 时区启动器.lnk'
}

$Source = Get-FullPath $Source
$InstallRoot = Get-FullPath $InstallRoot
$ShortcutPath = Get-FullPath $ShortcutPath
$installParent = Split-Path -Parent $InstallRoot
$shortcutParent = Split-Path -Parent $ShortcutPath
$installLeaf = Split-Path -Leaf $InstallRoot

if ([string]::IsNullOrWhiteSpace($installLeaf)) { throw '安装目录无效。' }
if (Test-PathWithin $Source $InstallRoot) { throw '安装目录不能包含构建源目录。' }
if (Test-Path -LiteralPath $InstallRoot -PathType Leaf) { throw "安装路径是文件而不是目录：$InstallRoot" }
if (!(Test-Path -LiteralPath $Source -PathType Container)) { throw "找不到 Windows Release 构建产物：$Source" }

$requiredPaths = @(
    'codex_timezone.exe',
    'codex_timezone_core.dll',
    'data\flutter_assets',
    'data\icudtl.dat'
)
foreach ($relativePath in $requiredPaths) {
    $requiredPath = Join-Path $Source $relativePath
    if (!(Test-Path -LiteralPath $requiredPath)) {
        throw "Release 构建产物不完整，缺少：$relativePath"
    }
}

New-Item -ItemType Directory -Force -Path $installParent | Out-Null
New-Item -ItemType Directory -Force -Path $shortcutParent | Out-Null

$runningPaths = @()
foreach ($process in @(Get-Process -Name 'codex_timezone' -ErrorAction SilentlyContinue)) {
    $processPath = $null
    try { $processPath = $process.Path } catch { }
    if (!$processPath) {
        throw '无法确认正在运行的 Codex 时区启动器路径，请先退出该应用后重试。'
    }
    if (Test-PathWithin $processPath $InstallRoot) { $runningPaths += $processPath }
}
if ($runningPaths.Count -gt 0) {
    throw "请先退出已安装的 Codex 时区启动器，再重新安装：$($runningPaths -join '、')"
}

$token = [Guid]::NewGuid().ToString('N')
$staging = "$InstallRoot.installing-$token"
$backup = "$InstallRoot.backup-$token"
$failedInstall = "$InstallRoot.failed-$token"
$stagedShortcut = Join-Path $shortcutParent ".CodexTimeZoneLauncher-$token.lnk"
$shortcutBackup = Join-Path $shortcutParent ".CodexTimeZoneLauncher-$token.previous.lnk"
$oldMoved = $false
$newMoved = $false
$shortcutPublished = $false
$committed = $false

try {
    Copy-Item -LiteralPath $Source -Destination $staging -Recurse -Force

    $settingsPath = Join-Path $InstallRoot 'data\settings.json'
    $stagedSettingsPath = Join-Path $staging 'data\settings.json'
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stagedSettingsPath) | Out-Null
        Copy-Item -LiteralPath $settingsPath -Destination $stagedSettingsPath -Force
    } elseif (Test-Path -LiteralPath $stagedSettingsPath -PathType Leaf) {
        Remove-Item -LiteralPath $stagedSettingsPath -Force
    }

    $installedExecutable = Join-Path $InstallRoot 'codex_timezone.exe'
    New-Shortcut $stagedShortcut $installedExecutable $InstallRoot
    if (Test-Path -LiteralPath $ShortcutPath -PathType Leaf) {
        Copy-Item -LiteralPath $ShortcutPath -Destination $shortcutBackup -Force
    }

    if (Test-Path -LiteralPath $InstallRoot -PathType Container) {
        Move-Item -LiteralPath $InstallRoot -Destination $backup
        $oldMoved = $true
    }
    Move-Item -LiteralPath $staging -Destination $InstallRoot
    $newMoved = $true

    foreach ($relativePath in $requiredPaths) {
        if (!(Test-Path -LiteralPath (Join-Path $InstallRoot $relativePath))) {
            throw "安装后校验失败，缺少：$relativePath"
        }
    }
    Copy-Item -LiteralPath $stagedShortcut -Destination $ShortcutPath -Force
    $shortcutPublished = $true
    $committed = $true

    Write-Output "已安装：$InstallRoot"
    Write-Output "开始菜单：$ShortcutPath"
} catch {
    $failure = $_
    if (!$committed) {
        try {
            if ($shortcutPublished -or (Test-Path -LiteralPath $shortcutBackup -PathType Leaf)) {
                if (Test-Path -LiteralPath $shortcutBackup -PathType Leaf) {
                    Copy-Item -LiteralPath $shortcutBackup -Destination $ShortcutPath -Force
                } elseif (Test-Path -LiteralPath $ShortcutPath -PathType Leaf) {
                    Remove-Item -LiteralPath $ShortcutPath -Force
                }
            }
            if ($newMoved -and (Test-Path -LiteralPath $InstallRoot -PathType Container)) {
                Move-Item -LiteralPath $InstallRoot -Destination $failedInstall
            }
            if ($oldMoved -and (Test-Path -LiteralPath $backup -PathType Container)) {
                Move-Item -LiteralPath $backup -Destination $InstallRoot
            }
        } catch {
            Write-Warning "安装失败后的回滚未完全完成：$($_.Exception.Message)"
        }
    }
    throw $failure
} finally {
    foreach ($temporaryPath in @($staging, $failedInstall)) {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($temporaryFile in @($stagedShortcut, $shortcutBackup)) {
        if (Test-Path -LiteralPath $temporaryFile) {
            Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue
        }
    }
    if ($committed -and (Test-Path -LiteralPath $backup)) {
        try {
            Remove-Item -LiteralPath $backup -Recurse -Force
        } catch {
            Write-Warning "应用已安装，但旧版本备份清理失败：$backup"
        }
    }
}
