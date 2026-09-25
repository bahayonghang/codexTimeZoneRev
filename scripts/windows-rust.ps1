function Resolve-RustTool([string]$Tool) {
    $rustupCommand = Get-Command rustup.exe -ErrorAction SilentlyContinue
    if ($rustupCommand) {
        try {
            $resolved = @(& $rustupCommand.Source which $Tool 2>$null)
            if ($LASTEXITCODE -eq 0) {
                $path = $resolved |
                    ForEach-Object { $_.ToString().Trim() } |
                    Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
                    Select-Object -Last 1
                if ($path) { return $path }
            }
        } catch {
            # Fall back to PATH when rustup cannot resolve the active toolchain.
        }
    }

    $command = Get-Command "$Tool.exe" -ErrorAction SilentlyContinue
    if ($command -and $command.Source) { return $command.Source }
    throw "Rust tool not found: $Tool. Install Rust stable or add it to PATH."
}
