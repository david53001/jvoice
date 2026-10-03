# One-line uninstaller for JVoice on Windows. Paste into PowerShell:
#
#   irm https://raw.githubusercontent.com/david53001/jvoice/main/scripts/uninstall.ps1 | iex
#
# Quits JVoice and removes everything it put on this PC: the app (%LOCALAPPDATA%\Programs\JVoice),
# its shortcuts and Apps & features entry, launch at login (including the "run as administrator"
# logon task), its settings, custom words, stats and recent transcripts (%APPDATA%\JVoice), and the
# downloaded speech model (%LOCALAPPDATA%\JVoice). Reinstall any time with scripts/install.ps1.
#
# Test overrides (unset for real use): JVOICE_INSTALL_DIR, JVOICE_DESKTOP_DIR, JVOICE_STARTMENU_DIR,
# JVOICE_ARP_NAME, JVOICE_APPDATA_DIR, JVOICE_DATA_DIR, and JVOICE_NO_STOP (leaves the running app,
# its logon task and its Run entry alone).
& {
    $ErrorActionPreference = 'Stop'
    $target    = if ($env:JVOICE_INSTALL_DIR)   { $env:JVOICE_INSTALL_DIR }   else { Join-Path $env:LOCALAPPDATA 'Programs\JVoice' }
    $desktop   = if ($env:JVOICE_DESKTOP_DIR)   { $env:JVOICE_DESKTOP_DIR }   else { [Environment]::GetFolderPath('Desktop') }
    $startmenu = if ($env:JVOICE_STARTMENU_DIR) { $env:JVOICE_STARTMENU_DIR } else { Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs' }
    $arpName   = if ($env:JVOICE_ARP_NAME)      { $env:JVOICE_ARP_NAME }      else { 'JVoice' }
    $appData   = if ($env:JVOICE_APPDATA_DIR)   { $env:JVOICE_APPDATA_DIR }   else { Join-Path $env:APPDATA 'JVoice' }
    $dataDir   = if ($env:JVOICE_DATA_DIR)      { $env:JVOICE_DATA_DIR }      else { Join-Path $env:LOCALAPPDATA 'JVoice' }
    $taskName  = 'JVoice Elevated Autostart'
    $problems  = @()

    if (-not $env:JVOICE_NO_STOP) {
        $task = $null
        try { $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop } catch {}
        if (Get-Process JVoice -ErrorAction SilentlyContinue) {
            Write-Host '==> Quitting JVoice...'
            if ($task) { try { Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop } catch {} }
            Get-Process JVoice -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill() } catch {} }
            for ($i = 0; $i -lt 50 -and (Get-Process JVoice -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 100 }
            if (Get-Process JVoice -ErrorAction SilentlyContinue) {
                Write-Host 'error: JVoice is running as administrator and could not be closed. Right-click the J in the system tray, choose Quit, then paste the command again.' -ForegroundColor Red
                return
            }
        }
        Write-Host '==> Turning off launch at login...'
        Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'JVoice' -ErrorAction SilentlyContinue
        if ($task) {
            try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop }
            catch { $problems += "The '$taskName' task needs an administrator PowerShell to remove: Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false" }
        }
    }

    Write-Host "==> Removing $target..."
    Remove-Item (Join-Path $desktop 'JVoice.lnk'), (Join-Path $startmenu 'JVoice.lnk') -Force -ErrorAction SilentlyContinue
    Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$arpName" -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($dir in @($target, $appData, $dataDir)) {
        if (-not (Test-Path $dir)) { continue }
        if ($dir -ne $target) { Write-Host "==> Removing $dir..." }
        try { Remove-Item $dir -Recurse -Force -ErrorAction Stop }
        catch { $problems += "Could not fully remove $dir ($($_.Exception.Message))" }
    }

    if ($problems.Count) {
        Write-Host 'JVoice is uninstalled, except:' -ForegroundColor Yellow
        $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    } else {
        Write-Host 'JVoice is uninstalled. Its settings, history and speech model were removed too.' -ForegroundColor Green
    }
}
