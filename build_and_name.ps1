# build_and_name.ps1 - Automated build and obfuscation script for split-ABI APKs
param(
    [string]$ReleaseName = '',
    [switch]$SplitPerAbi = $false
)

# Portable Windows build script.
# Flutter AOT cannot reliably build from non-ASCII paths on Windows, so this
# script stages the required source files in a temporary ASCII-only directory.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if ($null -eq $flutter) {
    throw 'Flutter was not found. Install Flutter and add flutter/bin to PATH.'
}

$stageName = 'zybapp_open_build_' + [Guid]::NewGuid().ToString('N')
$stageRoot = $env:ZYB_BUILD_ROOT
if ([String]::IsNullOrWhiteSpace($stageRoot)) {
    $stageRoot = [Environment]::GetFolderPath('CommonDocuments')
}
if ([String]::IsNullOrWhiteSpace($stageRoot) -or $stageRoot -match '[^\x00-\x7F]') {
    throw 'Set ZYB_BUILD_ROOT to a writable ASCII-only directory.'
}
$stage = Join-Path $stageRoot $stageName

$releaseDir = Join-Path $root 'release\zyb-open'
if (-not (Test-Path -LiteralPath $releaseDir)) {
    New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
}

$defaultPrefix = 'zyb-open-v7.0'

$appPrefix = if (-not [String]::IsNullOrWhiteSpace($ReleaseName)) {
    $ReleaseName
} else {
    $defaultPrefix
}

try {
    New-Item -ItemType Directory -Path $stage | Out-Null

    foreach ($directory in @('lib', 'android', 'assets', 'test')) {
        Copy-Item -LiteralPath (Join-Path $root $directory) -Destination $stage -Recurse
    }
    foreach ($file in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.metadata')) {
        Copy-Item -LiteralPath (Join-Path $root $file) -Destination $stage
    }

    $localProperties = Join-Path $stage 'android\local.properties'
    if (Test-Path -LiteralPath $localProperties) {
        Remove-Item -LiteralPath $localProperties -Force
    }

    Push-Location $stage
    try {
        & $flutter.Source pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

        & $flutter.Source test --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }

        if ($SplitPerAbi) {
            Write-Host ">>> Building APKs with --split-per-abi..."
            & $flutter.Source build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
            if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

            $abis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
            foreach ($abi in $abis) {
                $src = Join-Path $stage ("build\app\outputs\flutter-apk\app-" + $abi + "-release.apk")
                if (-not (Test-Path -LiteralPath $src)) {
                    $matched = Get-ChildItem -LiteralPath (Join-Path $stage 'build\app\outputs\flutter-apk') -Filter "*$abi*.apk" | Select-Object -First 1
                    if ($null -ne $matched) {
                        $src = $matched.FullName
                    } else {
                        throw ("Could not find built APK for " + $abi)
                    }
                }

                $dstName = $appPrefix + '-' + $abi + '.apk'
                $target = Join-Path $releaseDir $dstName
                [System.IO.File]::Copy($src, $target, $true)

                $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
                $size = (Get-Item -LiteralPath $target).Length
                Write-Host (">>> Build succeeded (" + $abi + "): " + $target + " (" + $size + " bytes)")
                Write-Host ("    SHA256: " + $hash)
            }
        } else {
            Write-Host ">>> Building single APK for arm64-v8a..."
            & $flutter.Source build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/symbols
            if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

            $src = Join-Path $stage 'build\app\outputs\flutter-apk\app-release.apk'
            $dstName = $appPrefix + '-arm64-v8a.apk'
            $target = Join-Path $releaseDir $dstName
            [System.IO.File]::Copy($src, $target, $true)

            $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            $size = (Get-Item -LiteralPath $target).Length
            Write-Host (">>> Build succeeded: " + $target + " (" + $size + " bytes)")
            Write-Host ("    SHA256: " + $hash)
        }
    }
    finally {
        Pop-Location
    }

    if (Test-Path -LiteralPath (Join-Path $stage 'build\symbols')) {
        Copy-Item -LiteralPath (Join-Path $stage 'build\symbols') `
            -Destination (Join-Path $releaseDir 'symbols') -Recurse -Force
    }
}
finally {
    $tempRoot = [IO.Path]::GetFullPath($stageRoot)
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    if ($resolvedStage.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedStage).StartsWith('zybapp_open_build_')) {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
