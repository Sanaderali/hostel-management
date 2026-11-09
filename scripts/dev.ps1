<#
  Daily dev start: local API server (own window) + the app on an emulator/phone.
    scripts\dev.ps1                      -> picks the Android emulator
    scripts\dev.ps1 -Device <id>         -> a specific device (see: flutter devices)
    scripts\dev.ps1 -HostIp 192.168.1.5  -> real phone on the same Wi-Fi (use your PC's IP)
#>
param([string]$Device = '', [string]$HostIp = '', [string]$Root = 'D:\dev', [string]$Gpu = 'host')
$ErrorActionPreference = 'Stop'

# Works even in a terminal opened before setup (stale PATH): point at the D:\dev tools directly.
$Sdk = "$Root\Android\Sdk"
$env:JAVA_HOME = "$Root\jdk17"
$env:ANDROID_HOME = $Sdk
$env:ANDROID_SDK_ROOT = $Sdk
$env:ANDROID_AVD_HOME = "$Root\avd"
$env:PUB_CACHE = "$Root\pub-cache"
$env:GRADLE_USER_HOME = "$Root\gradle"
$env:Path = "$Root\flutter\bin;$Root\node;$Root\jdk17\bin;$Sdk\cmdline-tools\latest\bin;" +
            "$Sdk\platform-tools;$Sdk\emulator;$Root\Git\cmd;$env:Path"
$Repo = Split-Path $PSScriptRoot -Parent

# 1) API server: start it only if it is not already answering.
$serverUp = $false
try { Invoke-RestMethod 'http://localhost:8080/health' -TimeoutSec 2 | Out-Null; $serverUp = $true } catch {}
if ($serverUp) { Write-Host 'API server already running on :8080' }
else { Start-Process powershell -ArgumentList '-NoExit', '-Command', "Set-Location '$Repo\server'; npm start" }

# 2) Device: use the given one, a running Android device, or boot the emulator and WAIT for it.
function Get-AndroidDevice {
  $ErrorActionPreference = 'Continue'
  (& adb devices) | Select-String '^(\S+)\s+device$' |
    ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1
}

if (-not $Device) {
  $Device = Get-AndroidDevice
  if (-not $Device) {
    Write-Host 'Starting emulator hostel_pixel (first boot can take 2-4 minutes) ...'
    # Launch directly so we can pass speed flags (-gpu host = use the real graphics chip).
    # If the emulator window is black/crashes, retry with:  scripts\dev.ps1 -Gpu angle_indirect
    Start-Process -FilePath "$Sdk\emulator\emulator.exe" -ArgumentList @(
      '-avd', 'hostel_pixel', '-gpu', $Gpu, '-memory', '3072', '-no-snapshot-load', '-no-metrics')
    for ($i = 0; $i -lt 100 -and -not $Device; $i++) { Start-Sleep -Seconds 3; $Device = Get-AndroidDevice }
    if (-not $Device) { throw 'Emulator did not start. Run: emulator -avd hostel_pixel   and read the message.' }
    Write-Host "Waiting for $Device to finish booting ..."
    for ($i = 0; $i -lt 100; $i++) {
      $ErrorActionPreference = 'Continue'
      if ((& adb -s $Device shell getprop sys.boot_completed) -match '1') { break }
      Start-Sleep -Seconds 3
    }
    $ErrorActionPreference = 'Stop'
  }
}

$runArgs = @('run', '-d', $Device)
if ($HostIp) { $runArgs += "--dart-define=API_BASE_URL=http://${HostIp}:8080/api/v1" }
Set-Location $Repo
& flutter @runArgs
