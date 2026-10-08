# Creates "F2L Companion" on the Desktop, pointing at the launcher so it always runs the latest build.
# Used by: "Open F2L Companion.bat" --install-shortcut
param([Parameter(Mandatory = $true)][string]$Target)
$desktop = [Environment]::GetFolderPath('Desktop')
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut((Join-Path $desktop 'F2L Companion.lnk'))
$link.TargetPath = $Target
$link.WorkingDirectory = Split-Path -Parent $Target
$link.WindowStyle = 7  # start minimised: only Pip appears
$exe = Join-Path (Split-Path -Parent $Target) 'Windows\F2L.Windows\bin\Release\net10.0-windows10.0.19041.0\F2L.Windows.exe'
if (Test-Path $exe) { $link.IconLocation = "$exe,0" }
$link.Description = 'Open Pip, the F2L AI desktop companion'
$link.Save()
Write-Host "Added 'F2L Companion' to your Desktop."
