param(
  [Parameter(Mandatory = $true)]
  [string]$ProducerRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$releaseRoot = Join-Path $repoRoot 'releases/2026-08-27-fga-complete'
$temporaryRoot = Join-Path $repoRoot '.packet-assembly'
$sourceTree = Join-Path $temporaryRoot 'source'
$fixedTimestamp = [DateTimeOffset]::Parse('2026-08-27T00:00:00Z')

function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Write-Utf8Json([object]$Value, [string]$Path, [int]$Depth = 100) {
  $json = $Value | ConvertTo-Json -Depth $Depth
  [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}

$script:pathRewrites = 0
$script:fieldRemovals = 0

function Convert-ToPublicValue([object]$Value) {
  if ($null -eq $Value) { return $null }

  if ($Value -is [string]) {
    if ($Value -match '^[A-Za-z]:[\\/]' -or $Value -match '^/(Users|home)/') {
      $script:pathRewrites++
      $leaf = [IO.Path]::GetFileName($Value.Replace('\', '/'))
      return "external-source/$leaf"
    }
    if ($Value -match '^codex://') {
      $script:pathRewrites++
      return 'internal-task-reference-removed'
    }
    return $Value
  }

  if ($Value -is [System.Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in $Value.Keys) {
      if ($key -in @('task_id', 'coordinator_task', 'keeper_task')) {
        $script:fieldRemovals++
        continue
      }
      $result[$key] = Convert-ToPublicValue $Value[$key]
    }
    return [pscustomobject]$result
  }

  if ($Value -is [pscustomobject]) {
    $result = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) {
      if ($property.Name -in @('task_id', 'coordinator_task', 'keeper_task')) {
        $script:fieldRemovals++
        continue
      }
      $result[$property.Name] = Convert-ToPublicValue $property.Value
    }
    return [pscustomobject]$result
  }

  if ($Value -is [System.Collections.IEnumerable]) {
    return @($Value | ForEach-Object { Convert-ToPublicValue $_ })
  }

  return $Value
}

function Copy-SanitizedJson([string]$Source, [string]$Destination) {
  $value = Get-Content -LiteralPath $Source -Raw | ConvertFrom-Json
  $publicValue = Convert-ToPublicValue $value
  Write-Utf8Json $publicValue $Destination
}

function Copy-SanitizedJsonLines([string]$Source, [string]$Destination) {
  $lines = [Collections.Generic.List[string]]::new()
  foreach ($line in Get-Content -LiteralPath $Source) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $value = $line | ConvertFrom-Json
    $publicValue = Convert-ToPublicValue $value
    $lines.Add(($publicValue | ConvertTo-Json -Depth 100 -Compress))
  }
  [IO.File]::WriteAllText($Destination, (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
}

function New-DeterministicZip([string]$SourceDirectory, [string]$Destination) {
  Add-Type -AssemblyName System.IO.Compression
  if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
  $stream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew)
  try {
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
      $files = Get-ChildItem -LiteralPath $SourceDirectory -File -Recurse | Sort-Object {
        [IO.Path]::GetRelativePath($SourceDirectory, $_.FullName).Replace('\', '/')
      }
      foreach ($file in $files) {
        $relative = [IO.Path]::GetRelativePath($SourceDirectory, $file.FullName).Replace('\', '/')
        $entry = $archive.CreateEntry($relative, [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $fixedTimestamp
        $input = [IO.File]::OpenRead($file.FullName)
        try {
          $output = $entry.Open()
          try { $input.CopyTo($output) } finally { $output.Dispose() }
        } finally { $input.Dispose() }
      }
    } finally { $archive.Dispose() }
  } finally { $stream.Dispose() }
}

if (-not (Test-Path -LiteralPath $ProducerRoot -PathType Container)) {
  throw "Producer root does not exist."
}

$required = @(
  'build/main.pdf',
  'qa/final.json',
  'qa/final_text.txt',
  'control/AUTHORITY.csv',
  'release/fga-zh-hans-cn-complete.zip',
  'release/MANIFEST.json',
  'release/RECEIPT.json',
  'release/ZENODO_22083916_PUBLICATION_RECEIPT.json'
)
foreach ($relative in $required) {
  if (-not (Test-Path -LiteralPath (Join-Path $ProducerRoot $relative) -PathType Leaf)) {
    throw "Required producer artifact is absent: $relative"
  }
}

$sourceLocks = @{
  'build/main.pdf' = 'F12BBA02B9927D06E102ACD8C84435B3187F2BA9B7F7AD1EBC8BEFDB10E95A0E'
  'qa/final.json' = 'E6A868D19FE908E1046BEC275A4C72C2A730DFA53ADF2029274DEEA0C12D97DA'
  'qa/final_text.txt' = 'EAF278A4E083B65E0515E63A5D0E60B4FD0482D3FB3DEBBF1D78DB2802D2724D'
  'control/AUTHORITY.csv' = 'D697A5E8053E0583E433ED4709C742B4B0AA7A5414032A41AB7FEAEC47FEE138'
  'release/fga-zh-hans-cn-complete.zip' = '31063347F42424AC65EA2A2911B79B845540FB7C031E61F47C63E6AA3FC1F494'
  'release/MANIFEST.json' = 'FAAA82D5DE461338470FBCEB04050014F3C4CB065A423EEAB909B81254736881'
  'release/RECEIPT.json' = '7E9729BF4A5B6891440B7E1F3FCE125E289963E9CE11EEA47CECF71B236161D7'
  'release/ZENODO_22083916_PUBLICATION_RECEIPT.json' = '4F0DF866076F581EBCB715E4A1417A497312370B3293B5F54C8B57A82FD84B63'
}
foreach ($relative in $sourceLocks.Keys) {
  $actual = Get-Sha256 (Join-Path $ProducerRoot $relative)
  if ($actual -ne $sourceLocks[$relative]) {
    throw "Producer lock mismatch: $relative"
  }
}

if (Test-Path -LiteralPath $temporaryRoot) {
  $resolvedTemporary = (Resolve-Path -LiteralPath $temporaryRoot).Path
  $resolvedRepo = (Resolve-Path -LiteralPath $repoRoot).Path
  if (-not $resolvedTemporary.StartsWith($resolvedRepo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to remove a temporary path outside the staging repository.'
  }
  Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $sourceTree | Out-Null
foreach ($directory in @('01_source/zh', '01_source/tex', 'terminology', 'qa', 'provenance')) {
  New-Item -ItemType Directory -Force -Path (Join-Path $sourceTree $directory) | Out-Null
}

Copy-Item -LiteralPath (Join-Path $ProducerRoot 'build/main.pdf') -Destination (Join-Path $releaseRoot 'fga-zh-hans-cn.pdf') -Force
Get-ChildItem -LiteralPath (Join-Path $ProducerRoot 'zh') -File -Filter '*.tex' |
  Copy-Item -Destination (Join-Path $sourceTree '01_source/zh') -Force
Copy-Item -LiteralPath (Join-Path $ProducerRoot 'tex/zh.tex') -Destination (Join-Path $sourceTree '01_source/tex/zh.tex') -Force
Copy-Item -LiteralPath (Join-Path $ProducerRoot 'control/AUTHORITY.csv') -Destination (Join-Path $sourceTree 'provenance/AUTHORITY.csv') -Force

foreach ($name in @('BASE.json', 'WITNESSES.jsonl', 'LOCI.jsonl', 'TERM.jsonl', 'QA.jsonl')) {
  $source = Join-Path $ProducerRoot "terms/$name"
  $destination = Join-Path $sourceTree "terminology/$name"
  if ($name.EndsWith('.jsonl')) {
    Copy-SanitizedJsonLines $source $destination
  } else {
    Copy-SanitizedJson $source $destination
  }
}

$detailedQaNames = @('149.json', '182.json', '190.json', '195.json', '212.json', '221.json', '232.json', '236.json', 'com.json', 'errata_149_190.json', 'errata_195_221.json')
foreach ($name in $detailedQaNames) {
  Copy-SanitizedJson (Join-Path $ProducerRoot "qa/$name") (Join-Path $sourceTree "qa/$name")
}
Copy-Item -LiteralPath (Join-Path $ProducerRoot 'qa/final_text.txt') -Destination (Join-Path $sourceTree 'qa/final_text.txt') -Force

$termProjection = [ordered]@{}
foreach ($name in @('BASE.json', 'WITNESSES.jsonl', 'LOCI.jsonl', 'TERM.jsonl', 'QA.jsonl')) {
  $file = Get-Item -LiteralPath (Join-Path $sourceTree "terminology/$name")
  $termProjection[$name] = [ordered]@{ bytes = $file.Length; sha256 = Get-Sha256 $file.FullName }
}

$qaValue = Get-Content -LiteralPath (Join-Path $ProducerRoot 'qa/final.json') -Raw | ConvertFrom-Json
$publicQa = Convert-ToPublicValue $qaValue
$publicQa | Add-Member -NotePropertyName producer_evidence_origin -NotePropertyValue ([pscustomobject][ordered]@{
  filename = 'fga-zh-hans-cn-qa.json'
  bytes = 10586
  sha256 = 'E6A868D19FE908E1046BEC275A4C72C2A730DFA53ADF2029274DEEA0C12D97DA'
  historical_parent_record_doi = '10.5281/zenodo.22083916'
})
$publicQa | Add-Member -NotePropertyName public_privacy_projection -NotePropertyValue ([pscustomobject][ordered]@{
  absolute_private_path_values_rewritten = $script:pathRewrites
  internal_task_fields_removed = $script:fieldRemovals
  chinese_tex_bytes_changed = $false
  mathematical_content_changed = $false
  terminology_projection = $termProjection
})
$publicQa | Add-Member -NotePropertyName canonical_source_archive_replay -NotePropertyValue ([pscustomobject][ordered]@{
  status = 'PASS_CONTENT_EQUIVALENT_WITH_NONIDENTICAL_CONTAINER_BYTES'
  fresh_directory_passes = 5
  consecutive_final_passes_identical = $true
  converged_fresh_pdf_bytes_observed = 973662
  converged_fresh_pdf_sha256_observed = '7866D3FE80DE209D07308AD6FF9B22CC2BD1BC6F73E7EE3F34DA40F581706B32'
  preserved_release_pdf_bytes = 973659
  preserved_release_pdf_sha256 = 'F12BBA02B9927D06E102ACD8C84435B3187F2BA9B7F7AD1EBC8BEFDB10E95A0E'
  byte_identical_to_preserved_release = $false
  pages = 148
  default_text_extraction_bytes_each = 465004
  default_text_extraction_sha256_each = 'D8780366B8DA286B0561655CF7F574ABC5D3E496841354364A197E6D77A4B62B'
  all_page_72dpi_render_md5_mismatches = 0
  observed_container_differences = 'XeTeX/dvipdfmx generated different font-subset prefixes and a different PDF document ID in the clean build.'
  disposition = 'Preserve the previously verified reader bytes; the clean source replay has byte-identical extracted text and pixel-identical rendering on all 148 pages but is not a byte-for-byte PDF-container reproduction.'
})
Write-Utf8Json $publicQa (Join-Path $releaseRoot 'QA.json')

Copy-Item -LiteralPath (Join-Path $releaseRoot 'README.md') -Destination (Join-Path $sourceTree 'README.md') -Force
Copy-Item -LiteralPath (Join-Path $releaseRoot 'RIGHTS.md') -Destination (Join-Path $sourceTree 'RIGHTS.md') -Force
Copy-Item -LiteralPath (Join-Path $releaseRoot 'PROVENANCE.json') -Destination (Join-Path $sourceTree 'PROVENANCE.json') -Force
Copy-Item -LiteralPath (Join-Path $releaseRoot 'QA.json') -Destination (Join-Path $sourceTree 'QA.json') -Force

$payloadFiles = Get-ChildItem -LiteralPath $sourceTree -File -Recurse | Sort-Object {
  [IO.Path]::GetRelativePath($sourceTree, $_.FullName).Replace('\', '/')
}
$entries = @()
$treeLines = [Collections.Generic.List[string]]::new()
foreach ($file in $payloadFiles) {
  $relative = [IO.Path]::GetRelativePath($sourceTree, $file.FullName).Replace('\', '/')
  $sha = Get-Sha256 $file.FullName
  $entries += [pscustomobject][ordered]@{ path = $relative; bytes = $file.Length; sha256 = $sha }
  $treeLines.Add("$sha`t$($file.Length)`t$relative")
}
$treeSerialization = ($treeLines -join "`n") + "`n"
$treeBytes = [Text.Encoding]::UTF8.GetBytes($treeSerialization)
$treeHashObject = [Security.Cryptography.SHA256]::Create()
try { $treeHash = [Convert]::ToHexString($treeHashObject.ComputeHash($treeBytes)) } finally { $treeHashObject.Dispose() }

$sourceArchiveManifest = [ordered]@{
  schema = 'fga_zh_hans_cn_source_archive_manifest/v1'
  recorded = '2026-08-27T00:00:00Z'
  archive_filename = 'fga-zh-hans-cn-source.zip'
  payload_entries_excluding_this_manifest = $entries.Count
  payload_bytes = ($payloadFiles | Measure-Object Length -Sum).Sum
  payload_serialization_bytes = $treeBytes.Length
  payload_tree_sha256 = $treeHash
  privacy_projection = [ordered]@{
    absolute_private_path_values_rewritten = $script:pathRewrites
    internal_task_fields_removed = $script:fieldRemovals
    chinese_tex_bytes_changed = $false
    authority_scans_included = $false
    french_or_english_witness_files_included = $false
  }
  entries = $entries
}
$externalSourceManifest = Join-Path $releaseRoot 'SOURCE_ARCHIVE_MANIFEST.json'
Write-Utf8Json $sourceArchiveManifest $externalSourceManifest
Copy-Item -LiteralPath $externalSourceManifest -Destination (Join-Path $sourceTree 'SOURCE_ARCHIVE_MANIFEST.json') -Force

$zipA = Join-Path $temporaryRoot 'source-a.zip'
$zipB = Join-Path $temporaryRoot 'source-b.zip'
New-DeterministicZip $sourceTree $zipA
New-DeterministicZip $sourceTree $zipB
$zipAHash = Get-Sha256 $zipA
$zipBHash = Get-Sha256 $zipB
if ($zipAHash -ne $zipBHash) { throw 'Deterministic ZIP replay mismatch.' }
Copy-Item -LiteralPath $zipA -Destination (Join-Path $releaseRoot 'fga-zh-hans-cn-source.zip') -Force

$reader = Get-Item -LiteralPath (Join-Path $releaseRoot 'fga-zh-hans-cn.pdf')
$sourceArchive = Get-Item -LiteralPath (Join-Path $releaseRoot 'fga-zh-hans-cn-source.zip')
$qa = Get-Item -LiteralPath (Join-Path $releaseRoot 'QA.json')
$supportNames = @('README.md', 'RIGHTS.md', 'PROVENANCE.json', 'SOURCE_ARCHIVE_MANIFEST.json')
$supporting = foreach ($name in $supportNames) {
  $file = Get-Item -LiteralPath (Join-Path $releaseRoot $name)
  [pscustomobject][ordered]@{ filename = $name; bytes = $file.Length; sha256 = Get-Sha256 $file.FullName }
}

$releaseManifest = [ordered]@{
  schema = 'fga_zh_hans_cn_release_manifest/v2'
  recorded = '2026-08-27T00:00:00Z'
  work = 'Fondements de la géométrie algébrique (FGA)'
  display_title_zh = '《代数几何基础》简体中文版'
  locale = 'zh-Hans-CN'
  locale_characterization = 'mainland-oriented Simplified Chinese; not Singapore zh-Hans and not a Traditional-Chinese localization'
  status = 'PRODUCER_COMPLETE_UNCERTIFIED'
  coverage = 'all eight Exposés 149, 182, 190, 195, 212, 221, 232, and 236; the 1962 Commentaires; and all eight linked errata through EOF of e236'
  public_candidates = @(
    [ordered]@{ filename = 'fga-zh-hans-cn.pdf'; role = 'complete reader'; bytes = $reader.Length; sha256 = Get-Sha256 $reader.FullName; pages = 148 },
    [ordered]@{ filename = 'fga-zh-hans-cn-source.zip'; role = 'editable Chinese source, sanitized provenance, terminology, and compact QA evidence'; bytes = $sourceArchive.Length; sha256 = Get-Sha256 $sourceArchive.FullName; entries = $entries.Count + 1; uncompressed_bytes = ((Get-ChildItem -LiteralPath $sourceTree -File -Recurse | Measure-Object Length -Sum).Sum); deterministic_rebuild_match = $true },
    [ordered]@{ filename = 'MANIFEST.json'; role = 'release inventory; self identity is recorded by the producer receipt' },
    [ordered]@{ filename = 'QA.json'; role = 'privacy-clean terminal QA record'; bytes = $qa.Length; sha256 = Get-Sha256 $qa.FullName },
    [ordered]@{ filename = 'PRODUCER_RELEASE_RECEIPT.json'; role = 'post-manifest producer receipt' }
  )
  supporting_local_files = $supporting
  historical_parent = [ordered]@{ record_doi = '10.5281/zenodo.22083916'; relation = 'isDerivedFrom'; version_lineage = $false }
  qa = [ordered]@{ corpus_replay = 'PASS'; pdf_mechanics = 'PASS'; bounded_visual = 'PASS'; archive_replay = 'PASS'; privacy_projection = 'PASS'; fresh_source_replay = 'PASS_CONTENT_EQUIVALENT_WITH_NONIDENTICAL_CONTAINER_BYTES'; independent_chinese_certification = $false }
  rights = 'Independent unofficial translation/typesetting; no endorsement implied and no new blanket public-domain or open-license claim over the underlying FGA text.'
  destination = 'new canonical FGA zh-Hans-CN GitHub repository and new Zenodo concept; never a new version of the historical multilingual concept'
}
$manifestPath = Join-Path $releaseRoot 'MANIFEST.json'
Write-Utf8Json $releaseManifest $manifestPath

$manifestFile = Get-Item -LiteralPath $manifestPath
$sourceArchiveManifestFile = Get-Item -LiteralPath $externalSourceManifest
$receipt = [ordered]@{
  schema = 'fga_zh_hans_cn_producer_release_receipt/v2'
  recorded = '2026-08-27T00:00:00Z'
  status = 'READY_FOR_NEW_CANONICAL_LANGUAGE_LINEAGE'
  scope = 'complete bounded FGA zh-Hans-CN corpus through EOF of e236'
  historical_parent = [ordered]@{ record_doi = '10.5281/zenodo.22083916'; concept_doi = '10.5281/zenodo.21792434'; relation = 'isDerivedFrom'; preserved_as_immutable_history = $true }
  manifest = [ordered]@{ filename = 'MANIFEST.json'; bytes = $manifestFile.Length; sha256 = Get-Sha256 $manifestFile.FullName }
  reader = [ordered]@{ filename = 'fga-zh-hans-cn.pdf'; bytes = $reader.Length; sha256 = Get-Sha256 $reader.FullName; pages = 148; byte_identity_with_historical_parent = $true }
  editable_source = [ordered]@{
    filename = 'fga-zh-hans-cn-source.zip'
    bytes = $sourceArchive.Length
    sha256 = Get-Sha256 $sourceArchive.FullName
    entries = $entries.Count + 1
    deterministic_rebuild_match = $true
    internal_manifest = [ordered]@{ filename = 'SOURCE_ARCHIVE_MANIFEST.json'; bytes = $sourceArchiveManifestFile.Length; sha256 = Get-Sha256 $sourceArchiveManifestFile.FullName; payload_entries = $entries.Count; payload_tree_sha256 = $treeHash }
  }
  qa = [ordered]@{ filename = 'QA.json'; bytes = $qa.Length; sha256 = Get-Sha256 $qa.FullName; corpus_replay = 'PASS'; pdf_mechanics = 'PASS'; bounded_visual = 'PASS'; producer_certification_only = $true; independent_chinese_certification = $false }
  clean_source_replay = [ordered]@{
    status = 'PASS_CONTENT_EQUIVALENT_WITH_NONIDENTICAL_CONTAINER_BYTES'
    passes = 5
    final_converged = $true
    fresh_pdf_sha256_observed = '7866D3FE80DE209D07308AD6FF9B22CC2BD1BC6F73E7EE3F34DA40F581706B32'
    preserved_pdf_sha256 = 'F12BBA02B9927D06E102ACD8C84435B3187F2BA9B7F7AD1EBC8BEFDB10E95A0E'
    default_text_extraction_sha256_each = 'D8780366B8DA286B0561655CF7F574ABC5D3E496841354364A197E6D77A4B62B'
    all_page_render_md5_mismatches = 0
    byte_identical_pdf_container = $false
  }
  privacy_and_scope = [ordered]@{
    status = 'PASS'
    absolute_private_path_values_rewritten = $script:pathRewrites
    internal_task_fields_removed = $script:fieldRemovals
    credentials_included = $false
    authority_scans_included = $false
    french_or_english_witness_files_included = $false
    chinese_tex_bytes_changed = $false
    mathematical_content_changed = $false
  }
  prior_release_packet = [ordered]@{ filename = 'fga-zh-hans-cn-complete.zip'; bytes = 1422652; sha256 = '31063347F42424AC65EA2A2911B79B845540FB7C031E61F47C63E6AA3FC1F494'; disposition = 'historical input only; not republished because the canonical packet uses a privacy-clean projection' }
  next_action = 'Create the new GitHub repository and new Zenodo deposition, reserve the new DOIs, insert them into repository metadata, publish the exact nine release files, and anonymously read back every public byte.'
}
$receiptPath = Join-Path $releaseRoot 'PRODUCER_RELEASE_RECEIPT.json'
Write-Utf8Json $receipt $receiptPath

$releaseIndexPath = Join-Path $repoRoot 'RELEASES.json'
$releaseIndex = Get-Content -LiteralPath $releaseIndexPath -Raw | ConvertFrom-Json
$releaseIndex.releases[0].source_archive_sha256 = Get-Sha256 $sourceArchive.FullName
Write-Utf8Json $releaseIndex $releaseIndexPath

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($sourceArchive.FullName)
try {
  $manifestByPath = @{}
  foreach ($entry in $entries) { $manifestByPath[$entry.path] = $entry }
  $nameMismatches = 0
  $sizeMismatches = 0
  $hashMismatches = 0
  $unsafeEntries = 0
  $duplicates = 0
  $seen = @{}
  foreach ($entry in $zip.Entries) {
    $name = $entry.FullName.Replace('\', '/')
    if ($seen.ContainsKey($name)) { $duplicates++ } else { $seen[$name] = 1 }
    if ($name.StartsWith('/') -or $name -match '(^|/)\.\.(/|$)' -or $name -match '^[A-Za-z]:') { $unsafeEntries++ }
    if ($name -eq 'SOURCE_ARCHIVE_MANIFEST.json') { continue }
    if (-not $manifestByPath.ContainsKey($name)) { $nameMismatches++; continue }
    $expected = $manifestByPath[$name]
    if ([int64]$expected.bytes -ne [int64]$entry.Length) { $sizeMismatches++ }
    $input = $entry.Open()
    try {
      $hasher = [Security.Cryptography.SHA256]::Create()
      try { $actual = [Convert]::ToHexString($hasher.ComputeHash($input)) } finally { $hasher.Dispose() }
    } finally { $input.Dispose() }
    if ($actual -ne $expected.sha256) { $hashMismatches++ }
  }
  foreach ($name in $manifestByPath.Keys) { if (-not $seen.ContainsKey($name)) { $nameMismatches++ } }
  $archiveVerification = [ordered]@{
    status = if (($nameMismatches + $sizeMismatches + $hashMismatches + $unsafeEntries + $duplicates) -eq 0 -and $seen.ContainsKey('SOURCE_ARCHIVE_MANIFEST.json')) { 'PASS' } else { 'FAIL' }
    entries = $zip.Entries.Count
    expected_entries = $entries.Count + 1
    name_mismatches = $nameMismatches
    size_mismatches = $sizeMismatches
    sha256_mismatches = $hashMismatches
    duplicate_entries = $duplicates
    unsafe_entries = $unsafeEntries
    internal_manifest_present = $seen.ContainsKey('SOURCE_ARCHIVE_MANIFEST.json')
  }
} finally { $zip.Dispose() }
if ($archiveVerification.status -ne 'PASS') { throw 'Source archive verification failed.' }

$privatePathPattern = '(?i)([A-Za-z]:[\\/]+Users[\\/]|/(Users|home)/)'
$taskPattern = '(?i)(codex://|\b01a0[0-9a-f-]{8,}\b)'
$credentialPattern = '(?i)(access[_-]?token\s*[:=]|api[_-]?key\s*[:=]|bearer\s+[A-Za-z0-9_-]{12,})'
$privatePathHits = 0
$taskReferenceHits = 0
$credentialHits = 0
$textExtensions = @('.md', '.json', '.jsonl', '.csv', '.tex', '.txt', '.cff', '.gitattributes')
foreach ($file in Get-ChildItem -LiteralPath $repoRoot -File -Recurse | Where-Object { $_.FullName -notlike "$temporaryRoot*" -and $textExtensions -contains $_.Extension.ToLowerInvariant() }) {
  $text = [IO.File]::ReadAllText($file.FullName)
  $privatePathHits += [regex]::Matches($text, $privatePathPattern).Count
  $taskReferenceHits += [regex]::Matches($text, $taskPattern).Count
  $credentialHits += [regex]::Matches($text, $credentialPattern).Count
}

$zip = [IO.Compression.ZipFile]::OpenRead($sourceArchive.FullName)
try {
  foreach ($entry in $zip.Entries) {
    $extension = [IO.Path]::GetExtension($entry.FullName).ToLowerInvariant()
    if ($textExtensions -notcontains $extension) { continue }
    $readerStream = [IO.StreamReader]::new($entry.Open())
    try { $text = $readerStream.ReadToEnd() } finally { $readerStream.Dispose() }
    $privatePathHits += [regex]::Matches($text, $privatePathPattern).Count
    $taskReferenceHits += [regex]::Matches($text, $taskPattern).Count
    $credentialHits += [regex]::Matches($text, $credentialPattern).Count
  }
} finally { $zip.Dispose() }

if (($privatePathHits + $taskReferenceHits + $credentialHits) -ne 0) {
  throw "Privacy scan failed: private=$privatePathHits task=$taskReferenceHits credential=$credentialHits"
}

$inventory = foreach ($file in Get-ChildItem -LiteralPath $repoRoot -File -Recurse | Where-Object { $_.FullName -notlike "$temporaryRoot*" -and $_.Name -ne 'STAGING_RECEIPT.json' } | Sort-Object {
  [IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/')
}) {
  [pscustomobject][ordered]@{
    path = [IO.Path]::GetRelativePath($repoRoot, $file.FullName).Replace('\', '/')
    bytes = $file.Length
    sha256 = Get-Sha256 $file.FullName
  }
}

$stagingReceipt = [ordered]@{
  schema = 'fga_zh_hans_cn_canonical_staging_receipt/v1'
  recorded = '2026-08-27T00:00:00Z'
  status = 'PASS_STAGED_NO_REMOTE_MUTATION'
  repository = [ordered]@{ proposed_url = 'https://github.com/KokunoYumeto/fga-zh-hans-cn'; branch = 'main'; tag = 'fga-zh-hans-cn-2026-08-27-r1'; remote_created = $false }
  zenodo = [ordered]@{ new_concept_required = $true; concept_doi = $null; record_doi = $null; historical_parent_record_doi = '10.5281/zenodo.22083916'; relation = 'isDerivedFrom'; remote_created = $false }
  source_locks = [ordered]@{ exact_prior_packet_and_receipt_hashes = 'PASS'; original_complete_zip_member_verification = 'PASS_54_OF_54'; chinese_reader_byte_identity_preserved = $true }
  source_archive = [ordered]@{ filename = 'fga-zh-hans-cn-source.zip'; bytes = $sourceArchive.Length; sha256 = Get-Sha256 $sourceArchive.FullName; deterministic_rebuild_match = $true; verification = $archiveVerification }
  clean_source_replay = [ordered]@{ status = 'PASS_CONTENT_EQUIVALENT_WITH_NONIDENTICAL_CONTAINER_BYTES'; passes = 5; pages = 148; default_text_extraction_sha256_each = 'D8780366B8DA286B0561655CF7F574ABC5D3E496841354364A197E6D77A4B62B'; all_page_render_md5_mismatches = 0; preserved_pdf_sha256 = 'F12BBA02B9927D06E102ACD8C84435B3187F2BA9B7F7AD1EBC8BEFDB10E95A0E'; fresh_pdf_sha256_observed = '7866D3FE80DE209D07308AD6FF9B22CC2BD1BC6F73E7EE3F34DA40F581706B32'; byte_identical_pdf_container = $false }
  privacy_scan = [ordered]@{ status = 'PASS'; absolute_private_path_hits = $privatePathHits; internal_task_reference_hits = $taskReferenceHits; credential_marker_hits = $credentialHits; authority_scans_included = $false; french_or_english_witness_files_included = $false }
  inventory_excluding_this_receipt = $inventory
  deterministic_gaps = @(
    'A new Zenodo deposition must be created remotely before its record DOI and concept DOI can be known.',
    'An authenticated Zenodo draft-deposition duplicate check must be repeated immediately before creation because public search cannot see private drafts.',
    'The reserved DOIs must be inserted into CITATION.cff, README.md, RELEASES.json, and publication state before commit/tag.',
    'Remote GitHub and Zenodo byte-readback receipts do not exist until publication.',
    'A clean five-pass source replay is text- and pixel-identical on all 148 pages but not PDF-byte-identical to the preserved reader because the XeTeX/dvipdfmx container uses different font-subset prefixes and a different document ID.'
  )
}
Write-Utf8Json $stagingReceipt (Join-Path $PSScriptRoot 'STAGING_RECEIPT.json')

$resolvedTemporary = (Resolve-Path -LiteralPath $temporaryRoot).Path
$resolvedRepo = (Resolve-Path -LiteralPath $repoRoot).Path
if (-not $resolvedTemporary.StartsWith($resolvedRepo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Refusing final temporary removal outside the staging repository.'
}
Remove-Item -LiteralPath $temporaryRoot -Recurse -Force

[pscustomobject]@{
  status = 'PASS'
  reader_bytes = $reader.Length
  reader_sha256 = Get-Sha256 $reader.FullName
  source_archive_bytes = $sourceArchive.Length
  source_archive_sha256 = Get-Sha256 $sourceArchive.FullName
  source_archive_entries = $entries.Count + 1
  private_path_hits = $privatePathHits
  task_reference_hits = $taskReferenceHits
  credential_marker_hits = $credentialHits
} | ConvertTo-Json -Depth 4
