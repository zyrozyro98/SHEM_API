$ErrorActionPreference = 'Stop'

$flutterArguments = @(
  'run',
  '--dart-define=SHEM_MEDIA_API_BASE_URL=https://shem-api.onrender.com'
) + $args

& flutter @flutterArguments
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}