<#
  One-time dev environment setup for Windows. Everything goes on D:\ (nothing big on C:).

  Run from the repo folder (PowerShell):
    powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
  Options:  -Root D:\dev   -SkipEmulator

  Installs (portable zips, no admin needed): Flutter, Node, JDK 17, Android SDK tools.
  Only Git is needed beforehand:  winget install Git.Git --location D:\dev\Git
#>
param(
  [string]$Root = 'D:\dev',
  [switch]$SkipEmulator
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster

$FlutterVersion = '3.47.9'
$NodeVersion    = '22.23.4'
$Sdk            = Join-Path $Root 'Android\Sdk'
$Downloads      = Join-Path $Root 'downloads'
$Repo           = Split-Path $PSScriptRoot -Parent

$Urls = @{
  Flutter      = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip"
  Node         = "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-win-x64.zip"
  Jdk          = 'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse'
  AndroidTools = 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip'
}

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

function Install-Zip($name, $url, $target) {
  if (Test-Path $target) { Write-Host "$name already installed at $target"; return }
  New-Item -ItemType Directory -Force $Downloads | Out-Null
  $zip = Join-Path $Downloads "$name.zip"
  if (-not (Test-Path $zip)) {
    Write-Host "Downloading $name ..."
    $part = "$zip.part"                      # a half-finished download never looks complete
    Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing
    Move-Item $part $zip
  }
  $tmp = Join-Path $Root "_tmp_$name"
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  Write-Host "Extracting $name ..."
  New-Item -ItemType Directory -Force $tmp | Out-Null
  $tar = Join-Path $env:SystemRoot 'System32\tar.exe'   # much faster than Expand-Archive
  if (Test-Path $tar) {
    & $tar -xf $zip -C $tmp
    if ($LASTEXITCODE -ne 0) { throw "Extracting $name failed. Delete $zip and run the script again." }
  } else {
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
  }
  $inner = Get-ChildItem $tmp | Select-Object -First 1      # every zip has one top folder
  New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
  Move-Item $inner.FullName $target
  Remove-Item $tmp -Recurse -Force
}

function Set-UserEnv($name, $value) {
  [Environment]::SetEnvironmentVariable($name, $value, 'User')
  Set-Item -Path "Env:$name" -Value $value
}

# --- sanity checks -----------------------------------------------------------
if (-not (Test-Path (Split-Path $Root -Qualifier))) { throw "Drive $(Split-Path $Root -Qualifier) not found." }
New-Item -ItemType Directory -Force $Root | Out-Null
if (-not $Repo.StartsWith((Split-Path $Root -Qualifier), 'OrdinalIgnoreCase')) {
  Write-Warning "The repo is at $Repo (not on $(Split-Path $Root -Qualifier)). Move/clone it to the same drive if you want everything there."
}

$gitCmd = "$Root\Git\cmd"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  if (Test-Path "$gitCmd\git.exe") { $env:Path = "$gitCmd;$env:Path" }
  else { throw "Git not found. Run:  winget install Git.Git --location $Root\Git   then open a NEW PowerShell and re-run this script." }
}

# --- tools ---------------------------------------------------------------------
Step 'Flutter SDK';  Install-Zip 'flutter' $Urls.Flutter      "$Root\flutter"
Step 'Node.js';      Install-Zip 'node'    $Urls.Node         "$Root\node"
Step 'JDK 17';       Install-Zip 'jdk17'   $Urls.Jdk          "$Root\jdk17"
Step 'Android command-line tools'
Install-Zip 'android-cmdline-tools' $Urls.AndroidTools "$Sdk\cmdline-tools\latest"

# --- environment (user level, persists) ------------------------------------------
Step 'Environment variables (caches also kept on D:)'
Set-UserEnv 'JAVA_HOME'        "$Root\jdk17"
Set-UserEnv 'ANDROID_HOME'     $Sdk
Set-UserEnv 'ANDROID_SDK_ROOT' $Sdk
Set-UserEnv 'ANDROID_AVD_HOME' "$Root\avd"
Set-UserEnv 'PUB_CACHE'        "$Root\pub-cache"
Set-UserEnv 'GRADLE_USER_HOME' "$Root\gradle"
New-Item -ItemType Directory -Force "$Root\avd" | Out-Null

$adds = @("$Root\flutter\bin", "$Root\node", "$Root\jdk17\bin", "$Sdk\cmdline-tools\latest\bin",
          "$Sdk\platform-tools", "$Sdk\emulator", "$Root\flutter\bin\cache\dart-sdk\bin")
if (Test-Path "$gitCmd\git.exe") { $adds += $gitCmd }
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @(); if ($userPath) { $parts = $userPath -split ';' | Where-Object { $_ } }
foreach ($a in $adds) { if ($parts -notcontains $a) { $parts += $a } }
[Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
$env:Path = ($adds -join ';') + ';' + $env:Path

# --- Android SDK ------------------------------------------------------------------
Step 'Android SDK packages (accepting licenses)'
$yes = "y`n" * 60
$yes | & sdkmanager.bat "--sdk_root=$Sdk" --licenses | Out-Null
$packages = @('platform-tools', 'build-tools;28.0.3', 'build-tools;35.0.0', 'platforms;android-35', 'platforms;android-36')
if (-not $SkipEmulator) { $packages += @('emulator', 'system-images;android-35;google_apis;x86_64') }
& sdkmanager.bat "--sdk_root=$Sdk" @packages
if (-not $SkipEmulator) {
  Step 'Creating emulator "hostel_pixel"'
  "no" | & avdmanager.bat create avd -n hostel_pixel -k 'system-images;android-35;google_apis;x86_64' -d pixel_6 --force
}

# --- Flutter + project ---------------------------------------------------------------
Step 'Flutter config'
& flutter config --no-analytics --android-sdk $Sdk --jdk-dir "$Root\jdk17"
& flutter doctor -v

Step 'Project dependencies'
Push-Location $Repo
try {
  & flutter pub get
  & dart run build_runner build
} finally { Pop-Location }

Write-Host "`nDone. Open a NEW PowerShell window, then run:  scripts\dev.ps1" -ForegroundColor Green
Write-Host 'iPhone builds need a Mac with Xcode (see README).'
