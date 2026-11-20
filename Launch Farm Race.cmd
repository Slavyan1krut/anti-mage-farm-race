@echo off
setlocal
set "AM_FARM_RACE_ROOT=%~dp0"
set "AM_FARM_RACE_MODE=%~1"
powershell.exe -NoProfile -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "$steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam').SteamPath;" ^
    "$registry = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 570', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 570';" ^
    "$dota = (Get-ItemProperty $registry -ErrorAction SilentlyContinue | Select-Object -First 1).InstallLocation;" ^
    "if (-not $dota) { $dota = Join-Path $steam 'steamapps/common/dota 2 beta'; }" ^
    "if (-not (Test-Path -LiteralPath (Join-Path $dota 'game/bin/win64/dota2.exe'))) { throw 'Dota 2 installation was not found.' };" ^
    "$addons = Join-Path $dota 'game/dota_addons'; $source = Join-Path $env:AM_FARM_RACE_ROOT 'game/dota_addons/am_farm_race';" ^
    "if (-not (Test-Path -LiteralPath (Join-Path $source 'addoninfo.txt'))) { throw 'Addon files are missing. Extract the complete zip.' };" ^
    "Copy-Item -LiteralPath $source -Destination $addons -Recurse -Force;" ^
    "$command = 'dota_launch_custom_game am_farm_race dota'; $settings = '-applaunch 570 -novid -console';" ^
    "if ($env:AM_FARM_RACE_MODE -eq 'host') { $command = 'sv_lan 1; ' + $command; $settings += ' -port 27015 +sv_lan 1 +dota_launch_custom_game am_farm_race dota'; Write-Host 'Share your LAN or virtual LAN IPv4 address with friends. In game type -start when everyone has joined.';" ^
    "Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.PrefixOrigin -ne 'WellKnown' } | Select-Object InterfaceAlias,IPAddress | Format-Table -AutoSize }" ^
    "elseif ($env:AM_FARM_RACE_MODE -eq 'join') { $command = 'connect HOST_IPV4:27015' } else { $command = 'sv_lan 0; ' + $command; $settings += ' +sv_lan 0 +dota_launch_custom_game am_farm_race dota' };" ^
    "if (Get-Process dota2 -ErrorAction SilentlyContinue) { Write-Host 'Run this in the Dota 2 console:'; Write-Host $command; exit 2 };" ^
    "Start-Process -FilePath (Join-Path $steam 'steam.exe') -ArgumentList $settings -WindowStyle Hidden;" ^
    "if ($env:AM_FARM_RACE_MODE -in 'host','join') { if ($env:AM_FARM_RACE_MODE -eq 'join') { Write-Host 'Run this in the Dota 2 console:'; Write-Host $command }; exit 2 };"
if errorlevel 1 pause
