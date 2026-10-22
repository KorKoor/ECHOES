# Installs the three ECHOES mod folders into %USERPROFILE%\Zomboid\mods (never overwrites an existing folder).
$ErrorActionPreference = "Stop"
$branch = "claude/echoes-technical-research"
$tmp = Join-Path $env:TEMP "echoes-src"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
git clone --depth 1 -b $branch https://github.com/KorKoor/ECHOES $tmp
$dest = Join-Path $env:USERPROFILE "Zomboid\mods"
foreach ($m in "Echoes","EchoesEngine","EchoesProbe") {
    $t = Join-Path $dest $m
    if (Test-Path $t) { Write-Host "SKIP $m (already exists: delete it first to update)"; continue }
    Copy-Item (Join-Path $tmp $m) $t -Recurse
    Write-Host "Installed $m"
}
Write-Host "Jar present: $(Test-Path (Join-Path $dest 'EchoesEngine\42\media\java\EchoesEngine.jar'))"
