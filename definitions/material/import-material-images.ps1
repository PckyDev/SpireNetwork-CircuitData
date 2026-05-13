param(
    [string]$MaterialJsonPath = (Join-Path $PSScriptRoot 'material.json'),
    [string]$ImageDirectory = (Join-Path $PSScriptRoot 'image'),
    [string]$BlockJsonPath = (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'block') 'block.json'),
    [string]$PaperJarPath = '',
    [string]$LibrariesRoot = '',
    [string]$SpreadsheetId = '1QTsnLFqjG1YQ0siEPl4shL7jXKkWCYl3Hoo9YcvfL5k',
    [string]$DownloadPath = (Join-Path $env:TEMP 'spire-material-sheet.xlsx'),
    [switch]$WriteDefinitionFile,
    [switch]$WriteFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Read-ZipEntryText {
    param(
        [System.IO.Compression.ZipArchive]$Zip,
        [string]$EntryPath
    )

    $entry = $Zip.GetEntry($EntryPath)
    if (-not $entry) {
        return $null
    }

    $reader = [System.IO.StreamReader]::new($entry.Open())
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }
}

function Resolve-ZipTargetPath {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $baseUri = [System.Uri]::new("http://zip/$BasePath")
    $resolvedUri = [System.Uri]::new($baseUri, $TargetPath)
    return $resolvedUri.AbsolutePath.TrimStart('/')
}

function Get-ColumnIndexFromCellReference {
    param([string]$CellReference)

    $columnLetters = ($CellReference -replace '\d', '').ToUpperInvariant()
    $columnIndex = 0
    foreach ($letter in $columnLetters.ToCharArray()) {
        $columnIndex = ($columnIndex * 26) + ([int][char]$letter - [int][char]'A' + 1)
    }

    return $columnIndex - 1
}

function Get-SharedStrings {
    param([System.IO.Compression.ZipArchive]$Zip)

    $sharedStringsXml = Read-ZipEntryText -Zip $Zip -EntryPath 'xl/sharedStrings.xml'
    if (-not $sharedStringsXml) {
        return @()
    }

    [xml]$sharedStringsDocument = $sharedStringsXml
    $sharedStrings = [System.Collections.Generic.List[string]]::new()

    foreach ($stringNode in $sharedStringsDocument.DocumentElement.SelectNodes('*[local-name()="si"]')) {
        $textNodes = $stringNode.SelectNodes('.//*[local-name()="t"]')
        $textValue = ($textNodes | ForEach-Object { $_.InnerText }) -join ''
        $sharedStrings.Add($textValue)
    }

    return $sharedStrings
}

function Get-CellText {
    param(
        [System.Xml.XmlNode]$CellNode,
        [string[]]$SharedStrings
    )

    $cellType = $CellNode.Attributes['t']?.Value
    if ($cellType -eq 's') {
        $sharedStringIndex = $CellNode.SelectSingleNode('*[local-name()="v"]')?.InnerText
        if ([string]::IsNullOrWhiteSpace($sharedStringIndex)) {
            return ''
        }

        return $SharedStrings[[int]$sharedStringIndex]
    }

    if ($cellType -eq 'inlineStr') {
        return (($CellNode.SelectNodes('*[local-name()="is"]//*[local-name()="t"]') | ForEach-Object { $_.InnerText }) -join '')
    }

    $valueNode = $CellNode.SelectSingleNode('*[local-name()="v"]')
    if ($null -ne $valueNode) {
        return $valueNode.InnerText
    }

    return ''
}

function Get-WorksheetInfo {
    param(
        [System.IO.Compression.ZipArchive]$Zip,
        [string]$SheetPath,
        [string[]]$SharedStrings
    )

    [xml]$worksheetDocument = Read-ZipEntryText -Zip $Zip -EntryPath $SheetPath
    $rows = @{}

    foreach ($rowNode in $worksheetDocument.DocumentElement.SelectNodes('*[local-name()="sheetData"]/*[local-name()="row"]')) {
        $rowIndex = [int]$rowNode.Attributes['r'].Value
        $cells = @{}

        foreach ($cellNode in $rowNode.SelectNodes('*[local-name()="c"]')) {
            $reference = $cellNode.Attributes['r'].Value
            $columnIndex = Get-ColumnIndexFromCellReference -CellReference $reference
            $cells[$columnIndex] = (Get-CellText -CellNode $cellNode -SharedStrings $SharedStrings).Trim()
        }

        $rows[$rowIndex] = $cells
    }

    return [pscustomobject]@{
        Path = $SheetPath
        Rows = $rows
    }
}

function Get-SheetDrawingPath {
    param(
        [System.IO.Compression.ZipArchive]$Zip,
        [string]$SheetPath
    )

    $sheetFileName = [System.IO.Path]::GetFileName($SheetPath)
    $relationshipsPath = "xl/worksheets/_rels/$sheetFileName.rels"
    $relationshipsXml = Read-ZipEntryText -Zip $Zip -EntryPath $relationshipsPath
    if (-not $relationshipsXml) {
        return $null
    }

    [xml]$relationshipsDocument = $relationshipsXml
    $drawingRelationship = $relationshipsDocument.DocumentElement.SelectSingleNode('*[local-name()="Relationship"][contains(@Type, "/drawing")]')
    if (-not $drawingRelationship) {
        return $null
    }

    return Resolve-ZipTargetPath -BasePath $SheetPath -TargetPath $drawingRelationship.Attributes['Target'].Value
}

function Get-DrawingAnchors {
    param(
        [System.IO.Compression.ZipArchive]$Zip,
        [string]$DrawingPath
    )

    $drawingXml = Read-ZipEntryText -Zip $Zip -EntryPath $DrawingPath
    if (-not $drawingXml) {
        return @()
    }

    [xml]$drawingDocument = $drawingXml

    $drawingFileName = [System.IO.Path]::GetFileName($DrawingPath)
    $relationshipsPath = "xl/drawings/_rels/$drawingFileName.rels"
    $relationshipsXml = Read-ZipEntryText -Zip $Zip -EntryPath $relationshipsPath
    if (-not $relationshipsXml) {
        return @()
    }

    [xml]$relationshipsDocument = $relationshipsXml
    $imageRelationships = @{}

    foreach ($relationshipNode in $relationshipsDocument.DocumentElement.SelectNodes('*[local-name()="Relationship"][contains(@Type, "/image")]')) {
        $relationshipId = $relationshipNode.Attributes['Id'].Value
        $imageRelationships[$relationshipId] = Resolve-ZipTargetPath -BasePath $DrawingPath -TargetPath $relationshipNode.Attributes['Target'].Value
    }

    $anchors = [System.Collections.Generic.List[object]]::new()
    foreach ($anchorNode in $drawingDocument.DocumentElement.SelectNodes('*[local-name()="oneCellAnchor" or local-name()="twoCellAnchor"]')) {
        $fromNode = $anchorNode.SelectSingleNode('*[local-name()="from"]')
        $blipNode = $anchorNode.SelectSingleNode('.//*[local-name()="blip"]')
        if (-not $fromNode -or -not $blipNode) {
            continue
        }

        $rowText = $fromNode.SelectSingleNode('*[local-name()="row"]')?.InnerText
        $columnText = $fromNode.SelectSingleNode('*[local-name()="col"]')?.InnerText
        if ([string]::IsNullOrWhiteSpace($rowText) -or [string]::IsNullOrWhiteSpace($columnText)) {
            continue
        }

        $relationshipId = ($blipNode.Attributes | Where-Object { $_.LocalName -eq 'embed' } | Select-Object -First 1)?.Value
        if ([string]::IsNullOrWhiteSpace($relationshipId) -or -not $imageRelationships.ContainsKey($relationshipId)) {
            continue
        }

        $anchors.Add([pscustomobject]@{
            Row = ([int]$rowText + 1)
            Column = [int]$columnText
            MediaPath = $imageRelationships[$relationshipId]
        })
    }

    return $anchors
}

function Normalize-Label {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    return (($Value -replace '\s+', ' ').Trim())
}

function Copy-ZipEntryToFile {
    param(
        [System.IO.Compression.ZipArchive]$Zip,
        [string]$EntryPath,
        [string]$DestinationPath
    )

    $entry = $Zip.GetEntry($EntryPath)
    if (-not $entry) {
        throw "Missing media entry: $EntryPath"
    }

    $sourceStream = $entry.Open()
    $destinationStream = [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    try {
        $sourceStream.CopyTo($destinationStream)
    }
    finally {
        $destinationStream.Dispose()
        $sourceStream.Dispose()
    }
}

function Write-TransparentPng {
    param([string]$DestinationPath)

    Add-Type -AssemblyName System.Drawing

    $bitmap = [System.Drawing.Bitmap]::new(16, 16)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        $bitmap.Save($DestinationPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Invoke-WebRequestWithRetry {
    param(
        [string]$Uri,
        [string]$OutFile,
        [int]$MaxAttempts = 3
    )

    $lastError = $null
    foreach ($attempt in 1..$MaxAttempts) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
            return
        }
        catch {
            $lastError = $_
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        }
    }

    throw $lastError
}

function Get-WorkspaceRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
}

function Resolve-DefaultPaperJarPath {
    param([string]$WorkspaceRoot)

    $candidatePatterns = @(
        (Join-Path $WorkspaceRoot 'MinecraftTestServer\versions\**\paper-*.jar'),
        (Join-Path $WorkspaceRoot 'MinecraftServer\versions\**\paper-*.jar')
    )

    foreach ($pattern in $candidatePatterns) {
        $candidate = Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }

    return ''
}

function Resolve-DefaultLibrariesRoot {
    param([string]$PaperJarPath)

    if (-not $PaperJarPath) {
        return ''
    }

    $versionDirectory = Split-Path -Path $PaperJarPath -Parent
    $versionsDirectory = Split-Path -Path $versionDirectory -Parent
    $serverRoot = Split-Path -Path $versionsDirectory -Parent
    if (-not $serverRoot) {
        return ''
    }

    return Join-Path $serverRoot 'libraries'
}

function Convert-MaterialIdToDisplayName {
    param([string]$MaterialId)

    $normalizedId = Normalize-Label -Value (($MaterialId -replace '^minecraft:', '') -replace '[_/]+', ' ')
    if (-not $normalizedId) {
        return ''
    }

    $textInfo = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
    $displayName = $textInfo.ToTitleCase($normalizedId.ToLowerInvariant())
    $displayName = $displayName -replace '\bTnt\b', 'TNT'
    $displayName = $displayName -replace '\bXp\b', 'XP'
    $displayName = $displayName -replace '\bTnts\b', 'TNTs'
    return $displayName
}

function Get-MaterialImageFileName {
    param([string]$MaterialId)

    $normalizedId = (($MaterialId -replace '^minecraft:', '') -replace '[^a-z0-9._-]+', '_').ToLowerInvariant()
    if (-not $normalizedId) {
        return ''
    }

    return "$normalizedId.png"
}

function Get-MaterialIdsFromPaperJar {
    param(
        [string]$PaperJarPath,
        [string]$LibrariesRoot
    )

    if (-not (Test-Path -LiteralPath $PaperJarPath)) {
        throw "Could not find a Paper jar at $PaperJarPath"
    }

    $classPathEntries = [System.Collections.Generic.List[string]]::new()
    $classPathEntries.Add((Resolve-Path -LiteralPath $PaperJarPath).Path)

    if ($LibrariesRoot -and (Test-Path -LiteralPath $LibrariesRoot)) {
        Get-ChildItem -LiteralPath $LibrariesRoot -Recurse -Filter '*.jar' -File |
            Sort-Object FullName |
            ForEach-Object { $classPathEntries.Add($_.FullName) }
    }

    $classPath = [string]::Join([System.IO.Path]::PathSeparator, $classPathEntries)
    $tempJavaDirectory = Join-Path $env:TEMP "spire-dump-materials-$PID"
    $tempJavaPath = Join-Path $tempJavaDirectory 'SpireDumpMaterials.java'
    $tempOutputPath = Join-Path $tempJavaDirectory 'materials.txt'

    $javaSource = @'
import java.io.BufferedWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import net.minecraft.SharedConstants;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.server.Bootstrap;

public class SpireDumpMaterials {
    public static void main(String[] args) throws Exception {
        Path outputPath = Path.of(args[0]);
        SharedConstants.tryDetectVersion();
        Bootstrap.bootStrap();
        try (BufferedWriter writer = Files.newBufferedWriter(outputPath)) {
            for (Object key : BuiltInRegistries.ITEM.keySet()) {
                writer.write(String.valueOf(key));
                writer.newLine();
            }
        }
    }
}
'@

    New-Item -ItemType Directory -Path $tempJavaDirectory -Force | Out-Null
    Set-Content -LiteralPath $tempJavaPath -Value $javaSource -Encoding UTF8
    try {
        & java --class-path $classPath $tempJavaPath $tempOutputPath 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to enumerate material ids from the Paper jar.'
        }

        return (Get-Content -LiteralPath $tempOutputPath) |
            ForEach-Object { "$_".Trim() } |
            Where-Object { $_ -match '^[a-z0-9_.-]+:[a-z0-9_./-]+$' } |
            Sort-Object -Unique
    }
    finally {
        Remove-Item -LiteralPath $tempJavaDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-IsSurvivalObtainableMaterialId {
    param([string]$MaterialId)

    $normalizedMaterialId = [string]$MaterialId
    $normalizedMaterialId = $normalizedMaterialId.Trim().ToLowerInvariant()
    if (-not $normalizedMaterialId) {
        return $false
    }

    # Keep air available because inventory getter chips use it as the empty-slot material sentinel.
    if ($normalizedMaterialId -eq 'minecraft:air') {
        return $true
    }

    if ($normalizedMaterialId -match '_spawn_egg$') {
        return $false
    }

    $excludedMaterialIds = @(
        'minecraft:barrier',
        'minecraft:bedrock',
        'minecraft:budding_amethyst',
        'minecraft:chain_command_block',
        'minecraft:chorus_plant',
        'minecraft:command_block',
        'minecraft:command_block_minecart',
        'minecraft:debug_stick',
        'minecraft:dirt_path',
        'minecraft:end_portal_frame',
        'minecraft:farmland',
        'minecraft:frogspawn',
        'minecraft:infested_chiseled_stone_bricks',
        'minecraft:infested_cobblestone',
        'minecraft:infested_cracked_stone_bricks',
        'minecraft:infested_deepslate',
        'minecraft:infested_mossy_stone_bricks',
        'minecraft:infested_stone',
        'minecraft:infested_stone_bricks',
        'minecraft:jigsaw',
        'minecraft:knowledge_book',
        'minecraft:light',
        'minecraft:petrified_oak_slab',
        'minecraft:player_head',
        'minecraft:reinforced_deepslate',
        'minecraft:repeating_command_block',
        'minecraft:spawner',
        'minecraft:structure_block',
        'minecraft:structure_void',
        'minecraft:test_block',
        'minecraft:test_instance_block',
        'minecraft:trial_spawner',
        'minecraft:vault'
    )

    return -not ($excludedMaterialIds -contains $normalizedMaterialId)
}

function New-MaterialDefinitionRecords {
    param(
        [string[]]$MaterialIds,
        [hashtable]$BlockDefinitionsById
    )

    $records = [System.Collections.Generic.List[object]]::new()
    $definitions = [ordered]@{}
    $usedKeys = @{}

    foreach ($materialId in $MaterialIds) {
        $normalizedMaterialId = [string]$materialId
        $normalizedMaterialId = $normalizedMaterialId.Trim().ToLowerInvariant()
        if (-not $normalizedMaterialId) {
            continue
        }

        $existingBlockDefinition = $null
        if ($BlockDefinitionsById.ContainsKey($normalizedMaterialId)) {
            $existingBlockDefinition = $BlockDefinitionsById[$normalizedMaterialId]
        }

        $displayName = if ($existingBlockDefinition) {
            [string]$existingBlockDefinition['name']
        } else {
            Convert-MaterialIdToDisplayName -MaterialId $normalizedMaterialId
        }

        $imageFileName = if ($existingBlockDefinition) {
            [string]$existingBlockDefinition['image']
        } else {
            Get-MaterialImageFileName -MaterialId $normalizedMaterialId
        }

        $definitionKey = $displayName
        if (-not $definitionKey) {
            $definitionKey = $normalizedMaterialId
        }

        if ($usedKeys.ContainsKey($definitionKey)) {
            $definitionKey = "$displayName ($($normalizedMaterialId -replace '^minecraft:', ''))"
        }
        while ($usedKeys.ContainsKey($definitionKey)) {
            $definitionKey = "$definitionKey *"
        }
        $usedKeys[$definitionKey] = $true

        $definition = [ordered]@{
            id = $normalizedMaterialId
            name = $displayName
            image = ''
        }

        $definitions[$definitionKey] = $definition
        $records.Add([pscustomobject]@{
            Key = $definitionKey
            Definition = $definition
            Id = $normalizedMaterialId
            Name = $displayName
            ImageFileName = $imageFileName
        })
    }

    return [pscustomobject]@{
        Definitions = $definitions
        Records = $records
    }
}

function Build-MaterialLookups {
    param([System.Collections.Generic.List[object]]$Records)

    $materialsByName = @{}
    $materialsById = @{}
    foreach ($record in $Records) {
        $normalizedName = Normalize-Label -Value ([string]$record.Name)
        if ($normalizedName) {
            $materialsByName[$normalizedName] = $record
        }

        $normalizedId = Normalize-Label -Value ((([string]$record.Id) -replace '^minecraft:', ''))
        if ($normalizedId) {
            $materialsById[$normalizedId] = $record
        }
    }

    return [pscustomobject]@{
        ByName = $materialsByName
        ById = $materialsById
    }
}

$workspaceRoot = Get-WorkspaceRoot
if (-not $PaperJarPath) {
    $PaperJarPath = Resolve-DefaultPaperJarPath -WorkspaceRoot $workspaceRoot
}
if (-not $PaperJarPath) {
    throw 'Could not find a Paper jar automatically. Pass -PaperJarPath explicitly.'
}

if (-not $LibrariesRoot) {
    $LibrariesRoot = Resolve-DefaultLibrariesRoot -PaperJarPath $PaperJarPath
}

$blockDefinitionsById = @{}
if (Test-Path -LiteralPath $BlockJsonPath) {
    $blockDefinitions = Get-Content -LiteralPath $BlockJsonPath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($entry in $blockDefinitions.GetEnumerator()) {
        $blockId = [string]$entry.Value['id']
        if (-not [string]::IsNullOrWhiteSpace($blockId)) {
            $blockDefinitionsById[$blockId.Trim().ToLowerInvariant()] = $entry.Value
        }
    }
}

$materialIds = Get-MaterialIdsFromPaperJar -PaperJarPath $PaperJarPath -LibrariesRoot $LibrariesRoot |
    Where-Object { Test-IsSurvivalObtainableMaterialId -MaterialId $_ }
$materialBuild = New-MaterialDefinitionRecords -MaterialIds $materialIds -BlockDefinitionsById $blockDefinitionsById
$materialDefinitions = $materialBuild.Definitions
$materialRecords = $materialBuild.Records
$materialLookups = Build-MaterialLookups -Records $materialRecords

$exportUrl = "https://docs.google.com/spreadsheets/d/$SpreadsheetId/export?format=xlsx&id=$SpreadsheetId"
Invoke-WebRequestWithRetry -Uri $exportUrl -OutFile $DownloadPath

$zipArchive = [System.IO.Compression.ZipFile]::OpenRead($DownloadPath)
try {
    $sharedStrings = Get-SharedStrings -Zip $zipArchive
    $worksheetPaths = $zipArchive.Entries |
        Where-Object { $_.FullName -match '^xl/worksheets/sheet\d+\.xml$' } |
        ForEach-Object { $_.FullName }

    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($worksheetPath in $worksheetPaths) {
        $worksheet = Get-WorksheetInfo -Zip $zipArchive -SheetPath $worksheetPath -SharedStrings $sharedStrings
        $drawingPath = Get-SheetDrawingPath -Zip $zipArchive -SheetPath $worksheetPath
        if (-not $drawingPath) {
            continue
        }

        $headerRow = $worksheet.Rows[2]
        if (-not $headerRow) {
            continue
        }

        $headerItem = Normalize-Label -Value ([string]$headerRow[0])
        $headerItemName = Normalize-Label -Value ([string]$headerRow[1])
        if ($headerItem -ne 'Item' -or $headerItemName -ne 'Item Name') {
            continue
        }

        $anchors = Get-DrawingAnchors -Zip $zipArchive -DrawingPath $drawingPath
        $rowImages = @{}
        foreach ($anchor in $anchors) {
            if ($anchor.Column -ne 0) {
                continue
            }

            if (-not $rowImages.ContainsKey($anchor.Row)) {
                $rowImages[$anchor.Row] = $anchor.MediaPath
            }
        }

        $matchCount = 0
        foreach ($rowIndex in $worksheet.Rows.Keys) {
            $row = $worksheet.Rows[$rowIndex]
            $itemName = Normalize-Label -Value ([string]$row[1])
            $itemId = Normalize-Label -Value ([string]$row[2])
            if ($itemName -and $materialLookups.ByName.ContainsKey($itemName) -and $rowImages.ContainsKey($rowIndex)) {
                $matchCount += 1
                continue
            }
            if ($itemId -and $materialLookups.ById.ContainsKey($itemId) -and $rowImages.ContainsKey($rowIndex)) {
                $matchCount += 1
            }
        }

        $candidates.Add([pscustomobject]@{
            WorksheetPath = $worksheetPath
            Rows = $worksheet.Rows
            RowImages = $rowImages
            MatchCount = $matchCount
        })
    }

    $targetSheet = $candidates | Sort-Object MatchCount -Descending | Select-Object -First 1
    $matchedMaterials = @{}
    $generatedMaterials = [System.Collections.Generic.List[string]]::new()

    if ($targetSheet -and $targetSheet.MatchCount -gt 0) {
        foreach ($rowIndex in $targetSheet.Rows.Keys | Sort-Object) {
            if (-not $targetSheet.RowImages.ContainsKey($rowIndex)) {
                continue
            }

            $row = $targetSheet.Rows[$rowIndex]
            $itemName = Normalize-Label -Value ([string]$row[1])
            $itemId = Normalize-Label -Value ([string]$row[2])
            $record = $null

            if ($itemName -and $materialLookups.ByName.ContainsKey($itemName)) {
                $record = $materialLookups.ByName[$itemName]
            }
            elseif ($itemId -and $materialLookups.ById.ContainsKey($itemId)) {
                $record = $materialLookups.ById[$itemId]
            }

            if (-not $record) {
                continue
            }

            if (-not $matchedMaterials.ContainsKey($record.ImageFileName)) {
                $matchedMaterials[$record.ImageFileName] = [pscustomobject]@{
                    Name = [string]$record.Name
                    ImageFileName = [string]$record.ImageFileName
                    MediaPath = $targetSheet.RowImages[$rowIndex]
                }
                $record.Definition['image'] = [string]$record.ImageFileName
            }
        }
    }

    $airRecord = $materialRecords | Where-Object { $_.Id -eq 'minecraft:air' } | Select-Object -First 1
    if ($airRecord -and -not [string]::IsNullOrWhiteSpace($airRecord.ImageFileName) -and -not $matchedMaterials.ContainsKey($airRecord.ImageFileName)) {
        $matchedMaterials[$airRecord.ImageFileName] = [pscustomobject]@{
            Name = [string]$airRecord.Name
            ImageFileName = [string]$airRecord.ImageFileName
            MediaPath = $null
            IsGenerated = $true
        }
        $airRecord.Definition['image'] = [string]$airRecord.ImageFileName
        $generatedMaterials.Add([string]$airRecord.Name)
    }

    $unmatchedMaterials = [System.Collections.Generic.List[string]]::new()
    foreach ($record in $materialRecords) {
        if ([string]::IsNullOrWhiteSpace([string]$record.Definition['image'])) {
            $unmatchedMaterials.Add([string]$record.Name)
        }
    }

    if ($WriteDefinitionFile) {
        $jsonText = $materialDefinitions | ConvertTo-Json -Depth 4
        Set-Content -LiteralPath $MaterialJsonPath -Value $jsonText -Encoding UTF8
    }

    if ($WriteFiles) {
        New-Item -ItemType Directory -Path $ImageDirectory -Force | Out-Null
        foreach ($match in $matchedMaterials.Values) {
            $destinationPath = Join-Path $ImageDirectory $match.ImageFileName
            if ($match.PSObject.Properties.Name -contains 'IsGenerated' -and $match.IsGenerated) {
                Write-TransparentPng -DestinationPath $destinationPath
                continue
            }

            Copy-ZipEntryToFile -Zip $zipArchive -EntryPath $match.MediaPath -DestinationPath $destinationPath
        }
    }

    [pscustomobject]@{
        worksheetPath = if ($targetSheet) { $targetSheet.WorksheetPath } else { '' }
        matchedMaterials = $matchedMaterials.Count
        totalMaterials = $materialDefinitions.Count
        wroteDefinitionFile = [bool]$WriteDefinitionFile
        wroteFiles = [bool]$WriteFiles
        generatedMaterials = $generatedMaterials
        unmatchedMaterials = $unmatchedMaterials
        paperJarPath = $PaperJarPath
    } | ConvertTo-Json -Depth 4
}
finally {
    $zipArchive.Dispose()
}