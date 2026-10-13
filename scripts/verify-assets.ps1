[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$assetRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$assetRootPrefix = $assetRepoRoot.TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
$manifestPath = Join-Path $assetRepoRoot 'docs/asset-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$assetErrors = [System.Collections.Generic.List[string]]::new()
$listedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

if ($manifest.schemaVersion -ne 1 -or @($manifest.assets).Count -eq 0) {
    throw 'Unsupported or empty asset manifest.'
}

foreach ($asset in $manifest.assets) {
    $relativePath = [string]$asset.path
    if ([string]::IsNullOrWhiteSpace($relativePath) -or [System.IO.Path]::IsPathRooted($relativePath)) {
        $assetErrors.Add("Invalid relative path: $relativePath")
        continue
    }
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $assetRepoRoot $relativePath))
    if (-not $fullPath.StartsWith($assetRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $assetErrors.Add("Path outside project: $relativePath")
        continue
    }
    if (-not $listedPaths.Add($fullPath)) {
        $assetErrors.Add("Duplicate entry: $relativePath")
        continue
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $assetErrors.Add("Missing: $relativePath")
        continue
    }
    if ((Get-Item -LiteralPath $fullPath).Length -ne $asset.bytes) {
        $assetErrors.Add("Size changed: $relativePath")
    }
    if ((Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash -ne $asset.sha256) {
        $assetErrors.Add("Content changed: $relativePath")
    }
}

foreach ($assetDirectory in @('Windows/F2L.Windows/Assets', 'docs/companion-concepts', 'docs/previews')) {
    Get-ChildItem -LiteralPath (Join-Path $assetRepoRoot $assetDirectory) -File -Recurse -Force | ForEach-Object {
        if (-not $listedPaths.Contains($_.FullName)) {
            $assetErrors.Add("Unlisted asset: $($_.FullName.Substring($assetRootPrefix.Length))")
        }
    }
}

if ($assetErrors.Count -gt 0) {
    throw ($assetErrors -join [Environment]::NewLine)
}
Write-Output "Verified $($manifest.assets.Count) assets: all files present, hashes match, no unlisted assets."
