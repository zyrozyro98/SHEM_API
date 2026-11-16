$ErrorActionPreference = 'Stop'

$flutterArguments = @(
  'build',
  'web',
  '--release',
  '--dart-define=SHEM_MEDIA_API_BASE_URL=https://shem-api.onrender.com'
)

& flutter @flutterArguments
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& firebase deploy --only hosting --project she-m-8d0f5
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
