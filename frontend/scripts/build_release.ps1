$ErrorActionPreference = 'Stop'

$keyPropertiesPath = Join-Path $PSScriptRoot '..\android\key.properties'
if (-not (Test-Path $keyPropertiesPath)) {
  throw 'Create android/key.properties with the Play upload keystore values first. See PLAY_RELEASE_CHECKLIST.md.'
}

$buildNumber = $env:SHEM_BUILD_NUMBER
if ([string]::IsNullOrWhiteSpace($buildNumber) -or $buildNumber -notmatch '^\d+$' -or [int]$buildNumber -lt 1) {
  throw 'Set SHEM_BUILD_NUMBER to an integer greater than the latest version code in Play Console.'
}

flutter build appbundle --release `
  --build-number=$buildNumber `
  --dart-define=SHEM_MEDIA_API_BASE_URL=https://shem-api.onrender.com
