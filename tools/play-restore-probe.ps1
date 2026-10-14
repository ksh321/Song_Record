#requires -Version 7.0
param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path (Split-Path $PSScriptRoot -Parent) '.local/workflow/restore'))+[IO.Path]::DirectorySeparatorChar
$resolved=[IO.Path]::GetFullPath($Path)
if(-not $resolved.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -cnotmatch '^[0-9a-f]{64}\.wav$'){throw 'Restore probe scope refused'}
if(-not (Test-Path -LiteralPath $resolved -PathType Leaf)){throw 'Restore probe missing'}
$player=[System.Media.SoundPlayer]::new($resolved)
try{$player.Load();$player.PlaySync();Write-Host 'RESTORED_SYNTHETIC_SOUND_PLAYBACK=PASS'}
finally{$player.Dispose()}
