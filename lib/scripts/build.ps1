$ErrorActionPreference = 'Stop'

try {
    $projectRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    $pubspec = Join-Path $projectRoot 'pubspec.yaml'
    $content = Get-Content -LiteralPath $pubspec -Raw -Encoding UTF8
    if ($content -notmatch '(?m)^version:\s*([\d\.]+)\+(\d+)') {
        throw 'version not found'
    }
    $versionName = $matches[1]
    $versionCode = [int]$matches[2]
    $commitHash = 'local'

    # The declared version must match release tags, including in shallow clones.
    # Git supplies provenance only; commit counts must not rewrite pubspec.yaml.
    if (Test-Path -LiteralPath (Join-Path $projectRoot '.git')) {
        $commitHash = (& git -C $projectRoot rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Could not read Git revision.' }
    }

    $data = @{
        'pili.name' = $versionName
        'pili.code' = $versionCode
        'pili.hash' = $commitHash
        'pili.time' = [int]([DateTimeOffset]::Now.ToUnixTimeSeconds())
    }
    $data | ConvertTo-Json -Compress | Out-File (Join-Path $projectRoot 'pili_release.json') -Encoding UTF8
    if ($env:GITHUB_ENV) {
        Add-Content -LiteralPath $env:GITHUB_ENV -Value "version=$versionName+$versionCode"
    }
    Write-Host "Windows build version: $versionName+$versionCode ($commitHash)"
}
catch {
    Write-Error "Prebuild Error: $($_.Exception.Message)"
    exit 1
}
