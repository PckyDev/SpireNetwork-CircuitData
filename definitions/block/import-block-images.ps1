param(
    [string]$BlockJsonPath = (Join-Path $PSScriptRoot 'block.json'),
    [string]$ImageDirectory = (Join-Path $PSScriptRoot 'image'),
    [string]$SpreadsheetId = '1QTsnLFqjG1YQ0siEPl4shL7jXKkWCYl3Hoo9YcvfL5k',
    [string]$DownloadPath = (Join-Path $env:TEMP 'spire-block-sheet.xlsx'),
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

function New-SpreadsheetNamespaceManager {
    param([xml]$Document)

    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($Document.NameTable)
    $namespaceManager.AddNamespace('x', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
    $namespaceManager.AddNamespace('xdr', 'http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing')
    $namespaceManager.AddNamespace('a', 'http://schemas.openxmlformats.org/drawingml/2006/main')
    $namespaceManager.AddNamespace('r', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships')
    $namespaceManager.AddNamespace('rel', 'http://schemas.openxmlformats.org/package/2006/relationships')
    return $namespaceManager
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
        [System.Xml.XmlNamespaceManager]$NamespaceManager,
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
            $cells[$columnIndex] = (Get-CellText -CellNode $cellNode -NamespaceManager $null -SharedStrings $SharedStrings).Trim()
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

if (-not (Test-Path -LiteralPath $BlockJsonPath)) {
    throw "Could not find block definitions at $BlockJsonPath"
}

$exportUrl = "https://docs.google.com/spreadsheets/d/$SpreadsheetId/export?format=xlsx&id=$SpreadsheetId"
Invoke-WebRequest -Uri $exportUrl -OutFile $DownloadPath -UseBasicParsing

$blockDefinitions = Get-Content -LiteralPath $BlockJsonPath -Raw | ConvertFrom-Json -AsHashtable
$blocksByName = @{}
$blocksById = @{}

foreach ($entry in $blockDefinitions.GetEnumerator()) {
    $block = $entry.Value
    $normalizedName = Normalize-Label -Value ([string]$block['name'])
    if ($normalizedName) {
        $blocksByName[$normalizedName] = $block
    }

    $normalizedId = Normalize-Label -Value ((([string]$block['id']) -replace '^minecraft:', ''))
    if ($normalizedId) {
        $blocksById[$normalizedId] = $block
    }
}

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
            if ($itemName -and $blocksByName.ContainsKey($itemName) -and $rowImages.ContainsKey($rowIndex)) {
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
    if (-not $targetSheet -or $targetSheet.MatchCount -eq 0) {
        throw 'Could not find a worksheet that maps embedded images to block rows.'
    }

    $matchedBlocks = @{}
    foreach ($rowIndex in $targetSheet.Rows.Keys | Sort-Object) {
        $row = $targetSheet.Rows[$rowIndex]
        if (-not $targetSheet.RowImages.ContainsKey($rowIndex)) {
            continue
        }

        $itemName = Normalize-Label -Value ([string]$row[1])
        $itemId = Normalize-Label -Value ([string]$row[2])
        $block = $null

        if ($itemName -and $blocksByName.ContainsKey($itemName)) {
            $block = $blocksByName[$itemName]
        }
        elseif ($itemId -and $blocksById.ContainsKey($itemId)) {
            $block = $blocksById[$itemId]
        }

        if (-not $block) {
            continue
        }

        $targetFileName = [string]$block['image']
        if (-not $matchedBlocks.ContainsKey($targetFileName)) {
            $matchedBlocks[$targetFileName] = [pscustomobject]@{
                Name = [string]$block['name']
                ImageFileName = $targetFileName
                MediaPath = $targetSheet.RowImages[$rowIndex]
            }
        }
    }

    $generatedBlocks = [System.Collections.Generic.List[string]]::new()
    if ($blocksByName.ContainsKey('Air')) {
        $airBlock = $blocksByName['Air']
        $airFileName = [string]$airBlock['image']
        if (-not $matchedBlocks.ContainsKey($airFileName)) {
            $matchedBlocks[$airFileName] = [pscustomobject]@{
                Name = [string]$airBlock['name']
                ImageFileName = $airFileName
                MediaPath = $null
                IsGenerated = $true
            }
            $generatedBlocks.Add([string]$airBlock['name'])
        }
    }

    $unmatchedBlocks = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $blockDefinitions.GetEnumerator()) {
        $targetFileName = [string]$entry.Value['image']
        if (-not $matchedBlocks.ContainsKey($targetFileName)) {
            $unmatchedBlocks.Add([string]$entry.Value['name'])
        }
    }

    if ($WriteFiles) {
        New-Item -ItemType Directory -Path $ImageDirectory -Force | Out-Null
        foreach ($match in $matchedBlocks.Values) {
            $destinationPath = Join-Path $ImageDirectory $match.ImageFileName
            if ($match.PSObject.Properties.Name -contains 'IsGenerated' -and $match.IsGenerated) {
                Write-TransparentPng -DestinationPath $destinationPath
                continue
            }

            Copy-ZipEntryToFile -Zip $zipArchive -EntryPath $match.MediaPath -DestinationPath $destinationPath
        }
    }

    [pscustomobject]@{
        worksheetPath = $targetSheet.WorksheetPath
        matchedBlocks = $matchedBlocks.Count
        totalBlocks = $blockDefinitions.Count
        wroteFiles = [bool]$WriteFiles
        generatedBlocks = $generatedBlocks
        unmatchedBlocks = $unmatchedBlocks
    } | ConvertTo-Json -Depth 4
}
finally {
    $zipArchive.Dispose()
}