<#
  Daily dev start: local API server (own window) + the app on an emulator/phone.
    scripts\dev.ps1                      -> picks the Android emulator
    scripts\dev.ps1 -Device <id>         -> a specific device (see: flutter devices)
    scripts\dev.ps1 -HostIp 192.168.1.5  -> real phone on the same Wi-Fi (use your PC's IP)
#>
param([string]$Device = '', [string]$HostIp = '', [string]$Root = 'D:\dev')
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

Start-Process powershell -ArgumentList '-NoExit', '-Command', "Set-Location '$Repo\server'; npm start"

if (-not $Device) {
  $running = (& flutter devices --machine | ConvertFrom-Json) | Where-Object { $_.targetPlatform -like 'android*' }
  if (-not $running) {
    Write-Host 'Starting emulator hostel_pixel ...'
    & flutter emulators --launch hostel_pixel
    Start-Sleep -Seconds 45
  }
}

$runArgs = @('run')
if ($Device) { $runArgs += @('-d', $Device) }
if ($HostIp) { $runArgs += "--dart-define=API_BASE_URL=http://${HostIp}:8080/api/v1" }
Set-Location $Repo
& flutter @runArgs
