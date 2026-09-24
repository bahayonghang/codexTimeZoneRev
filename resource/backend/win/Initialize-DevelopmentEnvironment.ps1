$ErrorActionPreference = 'Stop'
$development = $env:CODEX_TZ_DEV_ROOT
if ($development) {
    $rustup = Join-Path $development 'Rust\rustup'
    $cargo = Join-Path $development 'Rust\cargo'
    if (Test-Path $rustup) { $env:RUSTUP_HOME = $rustup }
    if (Test-Path $cargo) { $env:CARGO_HOME = $cargo }
    $paths = @('NodeJS', 'Git\cmd', 'Rust\cargo\bin') |
        ForEach-Object { Join-Path $development $_ } |
        Where-Object { Test-Path $_ }
    if ($paths) { $env:PATH = ($paths -join ';') + ';' + $env:PATH }
}
if ($env:CODEX_TZ_PROXY) {
    $env:HTTP_PROXY = $env:CODEX_TZ_PROXY
    $env:HTTPS_PROXY = $env:CODEX_TZ_PROXY
    $env:CARGO_HTTP_PROXY = $env:CODEX_TZ_PROXY
}
function Find-VsDevCmd([string]$DevelopmentRoot) {
    if ($DevelopmentRoot) {
        $preferred = Join-Path $DevelopmentRoot 'VisualStudioBuildTools\Common7\Tools\VsDevCmd.bat'
        if (Test-Path -LiteralPath $preferred) { return $preferred }
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $root = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
        if ($root) {
            $candidate = Join-Path "$root".Trim() 'Common7\Tools\VsDevCmd.bat'
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    $fallback = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    return $null
}
$vsDevCmd = Find-VsDevCmd $development
if (-not $vsDevCmd) { throw '未找到带有 Desktop development with C++ 工作负载的 Visual Studio。' }
cmd /s /c "`"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "Env:$($matches[1])" -Value $matches[2] }
}
