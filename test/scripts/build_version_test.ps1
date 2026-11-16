$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$script = Join-Path $project 'lib\scripts\build.ps1'
$engine = (Get-Process -Id $PID).Path
$root = Join-Path ([IO.Path]::GetTempPath()) ('piliplus-version-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
function Assert-Version([string]$Checkout, [string]$ExpectedHash) {
    $pubspec = Join-Path $Checkout 'pubspec.yaml'
    $before = (Get-FileHash -LiteralPath $pubspec -Algorithm SHA256).Hash
    & $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Checkout 'lib\scripts\build.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Version generation failed.' }
    $metadata = Get-Content -LiteralPath (Join-Path $Checkout 'pili_release.json') -Raw | ConvertFrom-Json
    if ($metadata.'pili.name' -ne '2.1.6' -or $metadata.'pili.code' -ne 10 -or
        $metadata.'pili.hash' -ne $ExpectedHash) { throw 'Declared version or provenance was not preserved.' }
    if ((Get-FileHash -LiteralPath $pubspec -Algorithm SHA256).Hash -ne $before) {
        throw 'Version generation changed pubspec.yaml.'
    }
}
try {
    $repo = Join-Path $root 'source'
    New-Item -ItemType Directory -Path (Join-Path $repo 'lib\scripts') -Force | Out-Null
    Copy-Item -LiteralPath $script -Destination (Join-Path $repo 'lib\scripts\build.ps1')
    'version: 2.1.6+10' | Set-Content -LiteralPath (Join-Path $repo 'pubspec.yaml') -Encoding UTF8
    Assert-Version $repo 'local'

    & git -C $repo init -q
    if ($LASTEXITCODE -ne 0) { throw 'Temporary Git initialization failed.' }
    & git -C $repo add -- pubspec.yaml lib/scripts/build.ps1
    if ($LASTEXITCODE -ne 0) { throw 'Temporary Git staging failed.' }
    & git -C $repo -c user.name=Test -c user.email=test@example.invalid commit -q -m "test fixture`n`nCo-Authored-By: Claude Code <noreply@anthropic.com>"
    if ($LASTEXITCODE -ne 0) { throw 'Temporary Git commit failed.' }
    $hash = (& git -C $repo rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Temporary Git revision lookup failed.' }
    Assert-Version $repo $hash

    $shallow = Join-Path $root 'shallow'
    & git clone -q --depth 1 ('file:///' + $repo.Replace('\', '/')) $shallow
    if ($LASTEXITCODE -ne 0) { throw 'Temporary shallow clone failed.' }
    if ((& git -C $shallow rev-parse --is-shallow-repository).Trim() -ne 'true') {
        throw 'Test clone was not shallow.'
    }
    Assert-Version $shallow $hash
    Write-Output 'Version metadata regressions passed: source ZIP, Git checkout, shallow clone.'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
