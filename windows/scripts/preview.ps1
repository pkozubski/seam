# Buduje Seam i zapisuje zrzuty ekranu wszystkich stron (tryb offline: dane demo, bez sieci).
# Agent AI ogląda wynik, czytając pliki PNG z output/preview/.
#
#   pwsh windows/scripts/preview.ps1                     # wszystkie strony paska bocznego
#   pwsh windows/scripts/preview.ps1 -Section windows    # jedna strona (connection, displays, control,
#                                                        #   audio, clipboard, windows, settings, log)
#   pwsh windows/scripts/preview.ps1 -Section windows -FullPage   # cała przewijana strona Okna
#   pwsh windows/scripts/preview.ps1 -NoBuild            # bez ponownej kompilacji
param(
    [string]$Section,
    [switch]$FullPage,
    [switch]$NoBuild,
    [string]$Out
)
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "../..")
if (-not $Out) { $Out = Join-Path $root "output/preview/seam.png" }
New-Item -ItemType Directory -Force -Path (Split-Path $Out) | Out-Null

if (-not $NoBuild) {
    # Ta sama kolejność co w CI: restore Debug w trybie locked, potem build Release bez restore.
    # Restore w Release przepisałby packages.lock.json (znika Avalonia.Diagnostics).
    dotnet restore (Join-Path $root "windows/ClipboardChecks/Seam.ClipboardChecks.csproj") --locked-mode
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    dotnet build (Join-Path $root "windows/Seam/Seam.csproj") -c Release --no-restore -nologo -v q
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
}

$exe = Join-Path $root "windows/Seam/bin/Release/net8.0/Seam.exe"
$arguments = @("--screenshot", "`"$Out`"")
if ($Section) { $arguments += @("--screenshot-section", $Section) }
if ($FullPage) { $arguments += "--screenshot-full-page" }
$process = Start-Process -FilePath $exe -ArgumentList $arguments -Wait -PassThru -NoNewWindow
if ($process.ExitCode) { exit $process.ExitCode }

Get-ChildItem (Split-Path $Out) -Filter "*.png" |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-2) } |
    ForEach-Object { $_.FullName }
