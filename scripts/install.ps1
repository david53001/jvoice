# One-line installer AND updater for JVoice on Windows 10/11 (64-bit). Paste into PowerShell:
#
#   irm https://raw.githubusercontent.com/david53001/jvoice/main/scripts/install.ps1 | iex
#
# Finds the newest Windows release on GitHub, downloads the installer that fits this PC and runs it:
# the GPU build when the PC has an NVIDIA graphics card (faster transcription), otherwise the smaller
# CPU build; an existing install keeps the build it has. JVoice goes to %LOCALAPPDATA%\Programs\JVoice
# with Start menu and Desktop shortcuts and an Apps & features entry (no admin needed), then starts in
# the system tray.
#
# Running it again UPDATES JVoice, and does nothing when you already have the newest version.
# Settings, custom words, stats, recent transcripts (%APPDATA%\JVoice) and the downloaded speech model
# (%LOCALAPPDATA%\JVoice) live outside the install folder and are never touched.
#
# The installer is downloaded by PowerShell, not a browser, so Windows does not show the
# "Windows protected your PC" (SmartScreen) prompt that a manual download gets.
#
# Options, set before the command (for example:  $env:JVOICE_FLAVOR='cpu'; irm ... | iex):
#   JVOICE_FLAVOR = cpu | gpu   choose the build instead of detecting it
#   JVOICE_FORCE  = 1           reinstall even when already up to date
#
# Everything runs inside a script block so an error never closes your PowerShell window.
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'   # Windows PowerShell's progress bar makes downloads crawl
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

    $repo     = 'david53001/jvoice'
    $taskName = 'JVoice Elevated Autostart'
    $target   = if ($env:JVOICE_INSTALL_DIR) { $env:JVOICE_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\JVoice' }
    $exePath  = Join-Path $target 'JVoice.exe'

    function Fail([string]$msg) { Write-Host "error: $msg" -ForegroundColor Red }
    function VersionOf([string]$s) { if ($s -match '(\d+\.\d+\.\d+)') { [version]$Matches[1] } else { $null } }

    if (-not [Environment]::Is64BitOperatingSystem -or [Environment]::OSVersion.Version.Major -lt 10) {
        Fail 'JVoice needs 64-bit Windows 10 or 11.'; return
    }

    # ---- Which build: keep the installed one, else GPU for NVIDIA cards, else CPU ----
    $old = if (Test-Path $exePath) { VersionOf (Get-Item $exePath).VersionInfo.ProductVersion } else { $null }
    $flavor = $env:JVOICE_FLAVOR
    if (-not $flavor) {
        if ($old) { $flavor = if (Test-Path (Join-Path $target 'runtimes\cuda')) { 'gpu' } else { 'cpu' } }
        else {
            $nvidia = $false
            try { $nvidia = [bool](Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' }) } catch {}
            $flavor = if ($nvidia) { 'gpu' } else { 'cpu' }
        }
    }
    $asset = if ($flavor -eq 'gpu') { 'JVoice-Setup-GPU.exe' } else { 'JVoice-Setup.exe' }

    # ---- Newest Windows release (the repo also has macOS releases, so "latest" can't be used) ----
    Write-Host '==> Finding the newest Windows release...'
    $releases = Invoke-RestMethod "https://api.github.com/repos/$repo/releases?per_page=30" -UseBasicParsing
    $release = $null; $url = $null
    foreach ($r in $releases) {
        if ($r.draft -or $r.prerelease) { continue }
        $a = $r.assets | Where-Object { $_.name -eq $asset } | Select-Object -First 1
        if ($a) { $release = $r; $url = $a.browser_download_url; break }
    }
    if (-not $url) { Fail "no release with $asset found for $repo"; return }
    $new = VersionOf $release.tag_name
    Write-Host "    JVoice $new ($flavor build)"

    if ($old -and $new -and $old -ge $new -and $env:JVOICE_FORCE -ne '1') {
        Write-Host "JVoice $old is already the newest version."
        if (-not (Get-Process JVoice -ErrorAction SilentlyContinue) -and -not $env:JVOICE_SKIP_LAUNCH) { Start-Process $exePath -WorkingDirectory $target }
        return
    }

    # ---- Download ----
    $setup = Join-Path $env:TEMP ("JVoice-Setup-" + [Guid]::NewGuid().ToString('N') + '.exe')
    Write-Host "==> Downloading $asset ($([math]::Round($a.size / 1MB)) MB)..."
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) { & $curl.Source -fL --progress-bar -o $setup $url; if ($LASTEXITCODE -ne 0) { Fail "download failed (curl exit $LASTEXITCODE)"; return } }
    else { Invoke-WebRequest $url -OutFile $setup -UseBasicParsing }
    if ((Get-Item $setup).Length -ne $a.size) { Fail 'the download is incomplete; please run the command again.'; Remove-Item $setup -Force -ErrorAction SilentlyContinue; return }

    # ---- Stop a running JVoice (an elevated copy is stopped through its logon task) ----
    $task = $null
    if (-not $env:JVOICE_NO_STOP) {
        try { $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop } catch {}
        if ($task -and (Get-Process JVoice -ErrorAction SilentlyContinue)) {
            Write-Host '==> Quitting the running copy...'
            try { Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop } catch {}
        }
        Get-Process JVoice -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill() } catch {} }
        for ($i = 0; $i -lt 50 -and (Get-Process JVoice -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 100 }
        if (Get-Process JVoice -ErrorAction SilentlyContinue) {
            Remove-Item $setup -Force -ErrorAction SilentlyContinue
            Fail 'JVoice is running as administrator and could not be closed. Right-click the J in the system tray, choose Quit, then paste the command again.'
            return
        }
    }

    # ---- Install (the installer shows its own progress window and keeps your data) ----
    Write-Host "==> Installing to $target..."
    $relaunchTask = [bool]$task
    $hadSkip = $env:JVOICE_SKIP_LAUNCH
    if ($relaunchTask) { $env:JVOICE_SKIP_LAUNCH = '1' }   # the elevated logon task starts it instead
    try { Start-Process -FilePath $setup -Wait }
    finally {
        if ($relaunchTask) { if ($hadSkip) { $env:JVOICE_SKIP_LAUNCH = $hadSkip } else { Remove-Item Env:JVOICE_SKIP_LAUNCH -ErrorAction SilentlyContinue } }
        Remove-Item $setup -Force -ErrorAction SilentlyContinue
    }

    $installed = if (Test-Path $exePath) { VersionOf (Get-Item $exePath).VersionInfo.ProductVersion } else { $null }
    if (-not $installed -or ($new -and $installed -ne $new)) { Fail "the installer did not finish (found version '$installed'). Please run the command again."; return }
    if ($relaunchTask) { try { Start-ScheduledTask -TaskName $taskName } catch {} }

    if ($old) { Write-Host "Updated JVoice $old -> $installed. Your settings, custom words and speech model are kept." -ForegroundColor Green }
    else {
        Write-Host "Installed JVoice $installed. Look for the J in the system tray; press Ctrl+Shift+Space to dictate." -ForegroundColor Green
        Write-Host 'First use only: the speech model downloads once (about 570 MB).'
    }
}
