# Zrzut okna DZIAŁAJĄCEJ aplikacji (połączonej z Makiem, z prawdziwymi danymi).
# PrintWindow z PW_RENDERFULLCONTENT działa też, gdy okno jest zasłonięte; zminimalizowane
# okno trzeba najpierw przywrócić (-Restore).
#
#   pwsh windows/scripts/capture-window.ps1                       # okno główne Seam
#   pwsh windows/scripts/capture-window.ps1 -Title "Seam – Mac"   # inne okno (np. podgląd ekranu Maca)
#   pwsh windows/scripts/capture-window.ps1 -Restore -Out C:\tmp\seam.png
param(
    [string]$Title = "seam",
    [string]$ProcessName = "Seam",
    [switch]$Restore,
    [string]$Out
)
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "../..")
if (-not $Out) { $Out = Join-Path $root "output/preview/live.png" }
New-Item -ItemType Directory -Force -Path (Split-Path $Out) | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class SeamCapture {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[SeamCapture]::SetProcessDPIAware() | Out-Null

# Okno główne może być ukryte w zasobniku: wtedy MainWindowHandle = 0. Szukamy po tytule wśród procesów Seam
# (także starszych instalacji BorderlessMouse.exe, które aktualizują się w miejscu).
$window = Get-Process -Name $ProcessName, "BorderlessMouse" -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$Title*" } |
    Select-Object -First 1
if (-not $window) {
    Write-Error "Nie znaleziono widocznego okna '$Title' procesu $ProcessName. Otwórz okno z zasobnika (ikona Seam) i spróbuj ponownie."
}
$handle = $window.MainWindowHandle
if ([SeamCapture]::IsIconic($handle)) {
    if (-not $Restore) { Write-Error "Okno jest zminimalizowane – użyj -Restore." }
    [SeamCapture]::ShowWindow($handle, 9) | Out-Null   # SW_RESTORE
    Start-Sleep -Milliseconds 500
}

$rect = New-Object SeamCapture+RECT
[SeamCapture]::GetWindowRect($handle, [ref]$rect) | Out-Null
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$hdc = $graphics.GetHdc()
[SeamCapture]::PrintWindow($handle, $hdc, 2) | Out-Null   # PW_RENDERFULLCONTENT
$graphics.ReleaseHdc($hdc)
$graphics.Dispose()
$bitmap.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()
$Out
