param(
    [ValidateSet('windows')]
    [string]$platform = 'windows',
    [string]$FlutterRoot = $env:FLUTTER_ROOT,
    [string]$ProjectRoot = (Resolve-Path "$PSScriptRoot/../..").Path,
    [string]$BackupRoot = "$env:TEMP/piliplus-windows-patches"
)

$ErrorActionPreference = 'Stop'
if (-not $FlutterRoot) {
    throw 'Set FLUTTER_ROOT to the Flutter 3.47.8 SDK first.'
}

$ModalBarrierPatch = "lib/scripts/modal_barrier.patch"
$TextSelectionPatch = "lib/scripts/text_selection.patch"
$MouseCursorPatch = "lib/scripts/mouse_cursor.patch"
$ImageAnimPatch = "lib/scripts/image_anim.patch"
$LayoutBuilderPatch = "lib/scripts/layout_builder.patch"
$NavigationDrawerPatch = "lib/scripts/navigation_drawer.patch"
$PopupMenuPatch = "lib/scripts/popup_menu.patch"
$FABPatch = "lib/scripts/fab.patch"
$NullSafetySelectableRegionPatch = "lib/scripts/null_safety_for_selectable_region.patch"
$SelectableRegionPatch = "lib/scripts/selectable_region.patch"
$EditableTextPatch = "lib/scripts/editable_text.patch"
$TextFieldPatch = "lib/scripts/text_field.patch"
$ScrollPositionPatch = "lib/scripts/scroll_position.patch"
$ScrollablePatch = "lib/scripts/scrollable.patch"
$ScrollableGesturePatch = "lib/scripts/scrollable_gesture.patch"
$DraggableScrollableSheetPatch = "lib/scripts/draggable_scrollable_sheet.patch"
$ScaffoldPatch = "lib/scripts/scaffold.patch"
$TextPatch = "lib/scripts/text.patch"
$TextPainterPatch = "lib/scripts/text_painter.patch"
$SliverPatch = "lib/scripts/sliver.patch"
$RefreshIndicatorPatch = "lib/scripts/refresh_indicator.patch"
$DoubleTapGesturePatch = "lib/scripts/double_tap_gesture.patch"

$patches = @($ModalBarrierPatch, $TextSelectionPatch, $MouseCursorPatch,
            $ImageAnimPatch, $LayoutBuilderPatch, $NavigationDrawerPatch,
            $PopupMenuPatch, $FABPatch, $NullSafetySelectableRegionPatch,
            $SelectableRegionPatch, $EditableTextPatch, $TextFieldPatch,
            $ScrollPositionPatch, $ScrollablePatch, $ScrollableGesturePatch,
            $DraggableScrollableSheetPatch, $ScaffoldPatch, $TextPatch,
            $TextPainterPatch, $SliverPatch, $RefreshIndicatorPatch,
            $DoubleTapGesturePatch)

$ModalBarrierPatchMaterial = "lib/scripts/material/modal_barrier_material.patch"
$NavigationDrawerPatchMaterial = "lib/scripts/material/navigation_drawer.patch"
$PopupMenuPatchMaterial = "lib/scripts/material/popup_menu.patch"
$FABPatchMaterial = "lib/scripts/material/fab.patch"
$TextFieldPatchMaterial = "lib/scripts/material/text_field.patch"
$ScaffoldPatchMaterial = "lib/scripts/material/scaffold.patch"
$RefreshIndicatorPatchMaterial = "lib/scripts/material/refresh_indicator.patch"
$TabsPatchMaterial = "lib/scripts/material/tabs.patch"

$patches_material = @($ModalBarrierPatchMaterial, $NavigationDrawerPatchMaterial,
                    $PopupMenuPatchMaterial, $FABPatchMaterial,
                    $TextFieldPatchMaterial, $ScaffoldPatchMaterial,
                    $RefreshIndicatorPatchMaterial, $TabsPatchMaterial)

function Apply-PatchSet {
    param([string]$Target, [string[]]$Patches, [string]$Name)

    $paths = @($Patches | ForEach-Object { Join-Path $ProjectRoot $_ })
    $ErrorActionPreference = 'Continue'
    $checkOutput = & git -C $Target apply --check @paths 2>&1
    $checkStatus = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($checkStatus -ne 0) {
        $reversePaths = @($paths)
        [Array]::Reverse($reversePaths)
        $ErrorActionPreference = 'Continue'
        $reverseOutput = & git -C $Target apply --reverse --check @reversePaths 2>&1
        $reverseStatus = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($reverseStatus -eq 0) {
            Write-Host "$Name patches already applied."
            return
        }
        throw "$Name patch set does not match this version or is partially applied.`n$checkOutput`n$reverseOutput"
    }

    $backup = Join-Path $BackupRoot "$Name-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')"
    New-Item -ItemType Directory -Path $backup | Out-Null
    foreach ($patch in $paths) {
        foreach ($line in Get-Content -LiteralPath $patch) {
            if ($line -match '^\+\+\+ b/(.+)$') {
                $relative = $matches[1]
                if ($relative -match '(^|/)\.\.(/|$)' -or [IO.Path]::IsPathRooted($relative)) {
                    throw "Invalid patch path: $relative"
                }
                $original = Join-Path $Target $relative
                $destination = Join-Path $backup $relative
                if ((Test-Path -LiteralPath $original) -and -not (Test-Path -LiteralPath $destination)) {
                    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
                    Copy-Item -LiteralPath $original -Destination $destination
                }
            }
        }
    }
    & git -C $Target apply @paths
    if ($LASTEXITCODE -ne 0) { throw "$Name patch application failed." }
    Write-Host "$Name patches applied. Originals saved to $backup"
}

# Resolve the exact package selected by pub, including a custom PUB_CACHE.
$configPath = Join-Path $ProjectRoot '.dart_tool/package_config.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    throw 'Run flutter pub get before applying patches.'
}
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$material = $config.packages | Where-Object { $_.name -eq 'material_ui' }
if (-not $material) { throw 'material_ui is missing from package_config.json.' }
$configUri = [Uri]::new([IO.Path]::GetFullPath($configPath))
$materialRoot = [Uri]::new($configUri, [string]$material.rootUri).LocalPath

Apply-PatchSet -Target $FlutterRoot -Patches $patches -Name 'flutter'
Apply-PatchSet -Target $materialRoot -Patches $patches_material -Name 'material_ui'
Write-Host 'Windows SDK and material_ui patches complete.'
