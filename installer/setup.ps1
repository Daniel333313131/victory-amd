# VIctory AMD installer for AMD RDNA2 / RDNA3 / RDNA4: sets up the emulator next to a title you own.
# Copies the emulator and AMD FidelityFX DLLs into the game folder and writes launchers
# tuned for the detected GPU. Never modifies or deletes game files.
param(
    [string]$PackDir = (Split-Path -Parent $PSScriptRoot),
    [string]$TargetDir = ""
)
$ErrorActionPreference = 'Stop'

function Ok([string]$t)   { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Info([string]$t) { Write-Host "  [INFO] $t" -ForegroundColor Gray }
function Warn([string]$t) { Write-Host "  [WARN] $t" -ForegroundColor Yellow }
function Fail([string]$t) { Write-Host "  [ERR]  $t" -ForegroundColor Red }
function Step([string]$t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
function YesNo([string]$q, [bool]$def = $true) {
    $hint = if ($def) { "[Y/n]" } else { "[y/N]" }
    $a = Read-Host "  $q $hint"
    if ([string]::IsNullOrWhiteSpace($a)) { return $def }
    return $a.Trim().ToLower().StartsWith('y')
}

$Payload = Join-Path $PackDir "payload"
$Exe = Join-Path $Payload "victory\victory.exe"
$Ffx = Join-Path $Payload "fidelityfx-sdk"
foreach ($req in @($Exe, (Join-Path $Ffx "amd_fidelityfx_loader_dx12.dll"), (Join-Path $Ffx "amd_fidelityfx_upscaler_dx12.dll"))) {
    if (-not (Test-Path $req)) { Fail "Installer files missing: $req. Extract the WHOLE zip first."; exit 1 }
}

# ---------------------------------------------------------------- game folder
Step "1/4 Finding the title folder (the one with game_scarlett_master.exe)"
$GameDir = $null
if ($TargetDir) { $GameDir = $TargetDir.TrimEnd('\') }
else {
    foreach ($c in @($PackDir, (Split-Path -Parent $PackDir))) {
        if ($c -and (Test-Path (Join-Path $c "game_scarlett_master.exe"))) { $GameDir = $c.TrimEnd('\'); break }
    }
}
if (-not $GameDir) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select your title folder (contains game_scarlett_master.exe)"
    if ($dlg.ShowDialog() -eq 'OK') { $GameDir = $dlg.SelectedPath.TrimEnd('\') }
}
if (-not $GameDir -or -not (Test-Path (Join-Path $GameDir "game_scarlett_master.exe"))) {
    Fail "game_scarlett_master.exe not found. Put this installer folder inside your title folder and run it again."
    exit 2
}
Ok "Game folder: $GameDir"
foreach ($f in @("shaders.rpf", "levels.rpf", "textures.rpf")) {
    if (-not (Test-Path (Join-Path $GameDir $f))) { Warn "Missing $f - the game dump looks incomplete." }
}

# ---------------------------------------------------------------- hardware
Step "2/4 Checking your PC"
$Arch = "unknown"; $GpuName = ""
try {
    $gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'Radeon|NVIDIA|Intel' -and $_.Name -notmatch 'Basic|Virtual|Parsec' })
    foreach ($g in $gpus) {
        Info "GPU: $($g.Name) (driver $($g.DriverVersion))"
        $n = $g.Name
        if ($n -match 'RX\s*9\d{3}') { $Arch = "rdna4"; $GpuName = $n; break }
        elseif ($n -match 'RX\s*7\d{3}') { $Arch = "rdna3"; $GpuName = $n }
        elseif ($n -match 'RX\s*6\d{3}' -and $Arch -ne "rdna3") { $Arch = "rdna2"; $GpuName = $n }
        elseif ($n -match 'NVIDIA|Intel' -and $Arch -eq "unknown") { $Arch = "other"; $GpuName = $n }
    }
} catch { Warn "Could not read the GPU list." }
switch ($Arch) {
    "rdna4" { Ok "RDNA4 ($GpuName): FSR 4 ML upscaling + FSR 4 ML frame generation available." }
    "rdna3" { Ok "RDNA3 ($GpuName): FSR 3.1 upscaling + frame generation 3 (FSR 4 only if your driver exposes it)." }
    "rdna2" { Ok "RDNA2 ($GpuName): FSR 3.1 upscaling + frame generation 3." }
    "other" { Warn "Non-AMD GPU ($GpuName). This build is tuned and tested on AMD only; it may not run." }
    default { Warn "Could not identify an AMD RX 6000/7000/9000 GPU. Launchers will use the RDNA2/3 settings." ; $Arch = "rdna2" }
}
if ($Arch -eq "other") { $Arch = "rdna2" }
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $ram = [math]::Round($os.TotalVisibleMemorySize / 1MB)
    $commit = [math]::Round($os.TotalVirtualMemorySize / 1MB)
    Info "RAM: $ram GB, commit limit $commit GB"
    if ($ram -lt 30) { Warn "Less than 32 GB RAM: expect more stutter. 32 GB is recommended." }
    if ($commit -lt 48) { Warn "Commit limit under 48 GB: set the Windows pagefile to 'System managed' on an SSD with 30+ GB free." }
} catch {}
if (-not (Test-Path (Join-Path $env:SystemRoot "System32\vcruntime140.dll"))) {
    Warn "Microsoft Visual C++ 2015-2022 x64 runtime is missing: install https://aka.ms/vs/17/release/vc_redist.x64.exe"
}

# ---------------------------------------------------------------- copy files
Step "3/4 Installing VIctory into the game folder"
$VicDir = Join-Path $GameDir "victory-amd"
$FfxDir = Join-Path $GameDir "fidelityfx-sdk"
$Work = Join-Path $GameDir "_victory-logs"
foreach ($d in @($VicDir, $FfxDir, $Work)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
Copy-Item $Exe (Join-Path $VicDir "victory.exe") -Force
Get-ChildItem $Ffx -Filter *.dll | Copy-Item -Destination $FfxDir -Force
Ok "Installed victory-amd\victory.exe and fidelityfx-sdk\ (AMD FidelityFX SDK 2.x DLLs)"
$Seed = Join-Path $Payload "cache-seed\early-pipelines.txt"
if (Test-Path $Seed) {
    $pipes = Join-Path $env:LOCALAPPDATA "victory\cache\pipelines"
    New-Item -ItemType Directory -Force -Path $pipes | Out-Null
    $dst = Join-Path $pipes "early-pipelines.txt"
    if (-not (Test-Path $dst)) { Copy-Item $Seed $dst; Ok "Seeded the pipeline list (faster first loading)" }
}

# ---------------------------------------------------------------- launchers
Step "4/4 Writing launchers"
$Common = @'
@echo off
set "GAME_DIR=%~dp0"
if "%GAME_DIR:~-1%"=="\" set "GAME_DIR=%GAME_DIR:~0,-1%"
cd /d "%GAME_DIR%\_victory-logs"
set VICTORY_LOG=info
set VICTORY_TEXTURE_NO_WAIT=1
set VICTORY_RELAY=2
set VICTORY_WIDE_BACK=1
set VICTORY_CARD_REHASH_RUNS=1
set VICTORY_JOIN_COPIES=1
set VICTORY_INDIRECT_WINDOW=1
set VICTORY_RELAY_COPY=1
set VICTORY_CARD_STEPS=2
set VICTORY_INDIRECT_BATCH=2
set VICTORY_MAP_THREADS=1
set VICTORY_TITLE_PRIORITIES=0
set VICTORY_CARD_AWAKE=1
set VICTORY_SHOW_AFTER=1
set VICTORY_AMBIENT=0.8
set VICTORY_AMBIENT_REFLECT=1.5,0.35
set VICTORY_D3D12_DRED=light
set VICTORY_SKIP_PIPELINES=none
set VICTORY_THIN=1
set VICTORY_LATE_WAIT_LISTS=256
set VICTORY_JOIN_PARTS=8
set VICTORY_UPLOAD_AHEAD=1
set VICTORY_PORT_CONSTANTS=1
set VICTORY_PORT_ALL=1
set VICTORY_WINDOW_KB=512
set VICTORY_CARD_BUFFERS_MIN_MB=1
set VICTORY_PORT_GUARD=1
set VICTORY_PORT_JOURNAL=1
set "VICTORY_FIDELITYFX_DIR=%GAME_DIR%\fidelityfx-sdk"
set VICTORY_FRAME_INTERVAL_MS=33.333
set VICTORY_FPS_CAP=30
set VICTORY_PIPELINE_WAIT_MS=50
set VICTORY_PC_CONTROLS=1
'@

function Launcher([string]$title, [string]$extra, [string]$log) {
    $run = @"
echo Starting VIctory ($title). Keep this window open. In game: F3 = FPS/VRAM overlay.
"%GAME_DIR%\victory-amd\victory.exe" run "%GAME_DIR%\game_scarlett_master.exe" --execute > "%GAME_DIR%\_victory-logs\$log" 2>&1
if "%ERRORLEVEL%"=="0" goto :eof
echo.
echo [ERROR] VIctory stopped with code %ERRORLEVEL%. Last lines of the log:
powershell -NoProfile -Command "Get-Content -LiteralPath '%GAME_DIR%\_victory-logs\$log' -Tail 25"
echo Full log: %GAME_DIR%\_victory-logs\$log
pause
"@
    return "$Common`r`nrem $title`r`n$extra`r`n$run"
}

$files = [ordered]@{}
if ($Arch -eq "rdna4") {
    $files["Play (BEST - FSR4).cmd"] = Launcher "BEST - FSR 4 Performance" "set VICTORY_FSR_4K=performance" "run-best.log"
    $files["Play (FSR4 + Frame Gen 4).cmd"] = Launcher "FSR 4 + ML Frame Gen 4" "set VICTORY_FSR_4K=performance`r`nset VICTORY_FIDELITYFX_FRAMEGEN=4" "run-fg4.log"
    $files["Play (MAX GRAPHICS - FSR4 Quality).cmd"] = Launcher "MAX GRAPHICS - FSR 4 Quality" "set VICTORY_FSR_4K=quality`r`nset VICTORY_AMBIENT_AIR=1.5" "run-maxgfx.log"
} else {
    $files["Play (BEST - FSR).cmd"] = Launcher "BEST - FSR Performance" "set VICTORY_FSR_4K=performance" "run-best.log"
    $files["Play (FSR + Frame Gen 3).cmd"] = Launcher "FSR + Frame Gen 3" "set VICTORY_FSR_4K=performance`r`nset VICTORY_FIDELITYFX_FRAMEGEN=1" "run-fg3.log"
    $files["Play (MAX GRAPHICS - FSR Quality).cmd"] = Launcher "MAX GRAPHICS - FSR Quality" "set VICTORY_FSR_4K=quality`r`nset VICTORY_AMBIENT_AIR=1.5" "run-maxgfx.log"
}
$files["Pre-Compile Shaders (run once).cmd"] = @'
@echo off
set "GAME_DIR=%~dp0"
if "%GAME_DIR:~-1%"=="\" set "GAME_DIR=%GAME_DIR:~0,-1%"
echo Translating all shaders once (a few minutes, uses every CPU core)...
"%GAME_DIR%\victory-amd\victory.exe" shaders "%GAME_DIR%\shaders.rpf" "%GAME_DIR%\game_scarlett_master.exe"
echo Done. Now start a "Play" launcher.
pause
'@
$files["UNINSTALL VIctory.cmd"] = @'
@echo off
set "GAME_DIR=%~dp0"
if "%GAME_DIR:~-1%"=="\" set "GAME_DIR=%GAME_DIR:~0,-1%"
echo Removes ONLY the VIctory files (victory-amd, fidelityfx-sdk, _victory-logs, Play launchers).
echo Your game files are not touched.
set /p OK="Type YES to remove: "
if /i not "%OK%"=="YES" exit /b 0
rmdir /s /q "%GAME_DIR%\victory-amd" 2>nul
rmdir /s /q "%GAME_DIR%\fidelityfx-sdk" 2>nul
rmdir /s /q "%GAME_DIR%\_victory-logs" 2>nul
__DELS__echo Removed. The shader cache stays in %LOCALAPPDATA%\victory (delete it by hand to free space).
pause
del "%~f0"
'@
$dels = ($files.Keys | Where-Object { $_ -ne "UNINSTALL VIctory.cmd" } | ForEach-Object { "del /q `"%GAME_DIR%\$_`" 2>nul" }) -join "`r`n"
$files["UNINSTALL VIctory.cmd"] = $files["UNINSTALL VIctory.cmd"].Replace("__DELS__", $dels + "`r`n")
foreach ($k in $files.Keys) {
    $body = ($files[$k] -replace "`r?`n", "`r`n")
    [IO.File]::WriteAllText((Join-Path $GameDir $k), $body, (New-Object Text.UTF8Encoding($false)))
    Ok "Created: $k"
}

Write-Host ""
if (YesNo "Pre-compile the title's shaders now? (recommended, a few minutes, only once)" $true) {
    & (Join-Path $VicDir "victory.exe") shaders (Join-Path $GameDir "shaders.rpf") (Join-Path $GameDir "game_scarlett_master.exe")
}
Write-Host ""
Ok "All done. Start the game with the 'Play (BEST ...)' launcher in: $GameDir"
Info "First start: press Enter (or A) once at the profile screen. F3 shows FPS. F5 = drive/walk keys, F6 = mouse lock."
