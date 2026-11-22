param(
    [ValidateSet('init','update','prepare','login')][string]$Action = 'init',
    [int]$GamePort = 4200,
    [int]$EnginePort = 7210,
    [string]$ModuleId = 'Coop'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:RootPath = $PSScriptRoot
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

function Read-CoopConfig {
    $dataPath = Join-Path $script:RootPath 'data'
    [IO.Directory]::CreateDirectory($dataPath) | Out-Null
    $configPath = Join-Path $dataPath 'server-config.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        [IO.File]::WriteAllText($configPath, '{"port":4200,"saveName":"saveauto1","autosaveMinutes":5,"password":"","logFile":true,"steam":false}', $script:Utf8)
    }
    try { $config = [IO.File]::ReadAllText($configPath) | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Invalid data/server-config.json; fix JSON syntax before continuing' }
    if ($null -eq $config -or $config -isnot [pscustomobject]) { throw 'Server config must be a JSON object' }
    foreach ($entry in @{saveName='saveauto1'; autosaveMinutes=5; password=''; steam=$false}.GetEnumerator()) {
        if (-not $config.PSObject.Properties[$entry.Key]) { $config | Add-Member NoteProperty $entry.Key $entry.Value }
    }
    if ($config.saveName -isnot [string] -or $config.saveName -cnotmatch '^[A-Za-z0-9_-]{1,80}$') { throw 'Invalid campaign save name' }
    if ($config.autosaveMinutes -isnot [ValueType] -or $config.autosaveMinutes -is [bool] -or
        $config.autosaveMinutes -lt 1 -or $config.autosaveMinutes -gt 1440 -or
        [math]::Floor([double]$config.autosaveMinutes) -ne $config.autosaveMinutes) { throw 'Autosave minutes must be an integer in 1..1440' }
    if ($config.password -isnot [string]) { throw 'Server password must be a string' }
    if ($config.steam -isnot [bool]) { throw 'Steam registration flag must be a JSON boolean' }
    return $config
}

function Write-CoopConfig($Config) {
    $configPath = Join-Path $script:RootPath 'data/server-config.json'
    $temporary = Join-Path (Split-Path $configPath) ('.server-config-' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporary, ($Config | ConvertTo-Json -Depth 32), $script:Utf8)
        Move-Item -LiteralPath $temporary -Destination $configPath -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Find-CoopGame {
    $suffix = 'steamapps/workshop/content/261550/3770450698/DedicatedServer'
    $candidates = @((Join-Path $script:RootPath 'workshop'), $script:RootPath,
        (Join-Path (Split-Path $script:RootPath) '.virtualhome/Steam'),
        (Join-Path $script:RootPath 'steam/Steam'), (Join-Path $script:RootPath 'steam'))
    foreach ($basePath in $candidates) {
        $candidate = Join-Path $basePath $suffix
        if (Test-Path -LiteralPath (Join-Path $candidate 'engine/dotnet/dotnet.exe')) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    throw 'Workshop DedicatedServer is missing; complete AMP Update first'
}

function Copy-CoopServer {
    $sourcePath = Find-CoopGame
    $rootAbsolute = [IO.Path]::GetFullPath($script:RootPath).TrimEnd('\','/')
    $targetPath = [IO.Path]::GetFullPath((Join-Path $rootAbsolute 'server'))
    # Verify the exact absolute disposable target before any recursive removal.
    if ((Split-Path $targetPath) -ne $rootAbsolute -or (Split-Path $targetPath -Leaf) -ne 'server') { throw 'Unsafe staging path' }
    if (Test-Path -LiteralPath $targetPath) {
        $targetItem = Get-Item -LiteralPath $targetPath -Force
        if (($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            -not (Test-Path -LiteralPath (Join-Path $targetPath '.amp-coop-managed'))) {
            throw 'server/ is not a managed physical staging directory; move it aside before Update'
        }
    } else { [IO.Directory]::CreateDirectory($targetPath) | Out-Null }
    [IO.File]::WriteAllText((Join-Path $targetPath '.amp-coop-managed'), '', $script:Utf8)
    $readyPath = Join-Path $targetPath '.amp-coop-ready'
    if (Test-Path -LiteralPath $readyPath) { Remove-Item -LiteralPath $readyPath -Force }
    Get-ChildItem -LiteralPath $targetPath -Force | Where-Object Name -ne '.amp-coop-managed' | ForEach-Object {
        # Refuse reparse points anywhere in the disposable tree before traversing it.
        if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing reparse point in staged server' }
        $nestedLinks = @(Get-ChildItem -LiteralPath $_.FullName -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
        if ($nestedLinks.Count) { throw 'Refusing nested reparse point in staged server' }
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
    Get-ChildItem -LiteralPath $sourcePath -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $targetPath -Recurse -Force
    }
    if (-not (Test-Path -LiteralPath (Join-Path $targetPath 'engine/dotnet/dotnet.exe'))) { throw 'Staged .NET engine is missing' }
    [IO.File]::WriteAllText($readyPath, '', $script:Utf8)
}

function Get-CoopAccounts {
    $cachePath = Join-Path $script:RootPath 'config/config.vdf'
    if (-not (Test-Path -LiteralPath $cachePath)) {
        throw 'Steam sign-in was not completed by the AMP SteamCMD stage. Complete login/Guard in AMP, or run this helper with -Action login in an interactive PowerShell terminal. No server files were changed.'
    }
    $cacheText = [IO.File]::ReadAllText($cachePath)
    $cacheTokens = [regex]::Matches($cacheText, '\s+|//[^\r\n]*|"((?:\\.|[^"\\])*)"|([{}])')
    $position = 0; $depth = 0; $accountDepth = 0; $pendingKey = $null; $hasCache = $false
    $paths = @{}; $names = @{}
    foreach ($token in $cacheTokens) {
        if ($token.Index -ne $position) { throw 'Unreadable AMP Steam cache structure' }
        $position = $token.Index + $token.Length
        if ($token.Groups[1].Success) {
            $value = $token.Groups[1].Value
            if ($null -eq $pendingKey) { $pendingKey = $value; continue }
            if ($pendingKey -ieq 'ConnectCache' -and $value.Length) { $hasCache = $true }
            if ($accountDepth -and $depth -eq ($accountDepth+1) -and $pendingKey -ieq 'SteamID' -and $value.Length) {
                $account = [string]$paths[$depth]
                if ($account -match '^[A-Za-z0-9_]{1,64}$') { $names[$account.ToLowerInvariant()] = $true }
            }
            $pendingKey = $null
        } elseif ($token.Groups[2].Success) {
            if ($token.Value -eq '{') {
                if ($null -eq $pendingKey) { throw 'Invalid AMP Steam cache' }
                $depth++; $paths[$depth] = $pendingKey
                if ($pendingKey -ieq 'Accounts') { $accountDepth = $depth }
                if ($pendingKey -ieq 'ConnectCache') { $hasCache = $true }
                $pendingKey = $null
            } else {
                if ($null -ne $pendingKey -or $depth -lt 1) { throw 'Invalid AMP Steam cache' }
                if ($depth -eq $accountDepth) { $accountDepth = 0 }
                $depth--
            }
        }
    }
    if ($position -ne $cacheText.Length -or $depth -or $null -ne $pendingKey -or -not $hasCache -or -not $names.Count) {
        throw 'Steam sign-in has not created a reusable session. Complete login/Guard in AMP, or run this helper with -Action login in an interactive PowerShell terminal. A config.vdf file alone does not mean login succeeded.'
    }
    return @($names.Keys | Sort-Object)
}

function Invoke-CoopInteractiveLogin {
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'Manual Steam login requires an interactive PowerShell terminal, not AMP Console or an Update task'
    }
    $exePath = Join-Path $script:RootPath 'steamcmd.exe'
    if (-not (Test-Path -LiteralPath $exePath)) { throw 'SteamCMD is missing; run AMP Update once to install it first' }
    Write-Host '[coop] At the Steam> prompt enter: login YOUR_STEAM_LOGIN'
    Write-Host '[coop] Enter the password only at the SteamCMD password prompt, complete Steam Guard, then enter: quit'
    Write-Host '[coop] This helper does not read or store the password. SteamCMD keeps its token in this instance.'
    Push-Location -LiteralPath $script:RootPath
    try {
        & $exePath
        if ($LASTEXITCODE -ne 0) { throw 'Interactive SteamCMD exited with an error; check its own logs' }
        $null = Get-CoopAccounts
        Write-Host '[coop] Reusable Steam session found. Retry Update in AMP.'
    } finally { Pop-Location }
}

function Invoke-CoopSteam([string[]]$SteamArguments, [int]$TimeoutSeconds) {
    $exePath = Join-Path $script:RootPath 'steamcmd.exe'
    if (-not (Test-Path -LiteralPath $exePath)) { throw 'Run the AMP SteamCMD stage first' }
    # Arguments here are only fixed Steam commands, validated account names and
    # filesystem paths. No Steam or server password ever enters the argument list.
    foreach ($value in $SteamArguments) { if ($value.Contains('"')) { throw 'Unexpected quote in SteamCMD argument' } }
    $processInfo = New-Object Diagnostics.ProcessStartInfo
    $processInfo.FileName = $exePath
    $processInfo.Arguments = (($SteamArguments | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    $processInfo.WorkingDirectory = $script:RootPath
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardInput = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $processInfo
    try {
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while (-not $process.WaitForExit(10000)) {
            if ($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) { $process.Kill(); throw 'SteamCMD timed out; retry AMP Update' }
            if ($TimeoutSeconds -gt 180) { Write-Host '[coop] SteamCMD Workshop download is running...' }
        }
        $process.WaitForExit()
        return [pscustomobject]@{ ExitCode=$process.ExitCode; Output=($stdout.Result + $stderr.Result) }
    } finally { $process.Dispose() }
}

function Update-CoopWorkshop {
    $accounts = @(Get-CoopAccounts)
    $selected = $null
    if ($accounts.Count -eq 1) { $selected = $accounts[0] } else {
        foreach ($account in $accounts) {
            $probe = Invoke-CoopSteam @('+@NoPromptForPassword','1','+login',$account,'+quit') 180
            if ($probe.ExitCode -eq 0 -and $probe.Output -match 'Logging in.*\.\.\..*OK') { $selected=$account; break }
        }
    }
    if (-not $selected) { throw 'No reusable cached account; repeat AMP Steam login' }
    Write-Host '[coop] Downloading Co-op Workshop files using AMP cached login'
    $result = Invoke-CoopSteam @('+@NoPromptForPassword','1','+force_install_dir',(Join-Path $script:RootPath 'workshop'),
        '+login',$selected,'+workshop_download_item','261550','3770450698','validate','+quit') 7200
    Write-Host $result.Output
    if ($result.ExitCode -ne 0 -or $result.Output -notmatch 'Success\. Downloaded item 3770450698(?:\s|$)') {
        throw 'Workshop download was not confirmed; retry AMP Update'
    }
    Copy-CoopServer
}

function Prepare-CoopServer([int]$Port, [int]$InternalPort, [string]$ExpectedModule) {
    if ($Port -lt 1 -or $Port -gt 65534 -or $InternalPort -lt 1 -or $InternalPort -gt 65535 -or
        $InternalPort -eq $Port -or $InternalPort -eq ($Port+1)) { throw 'Invalid or overlapping allocated ports' }
    $gamePath = Join-Path $script:RootPath 'server'
    if (-not (Test-Path -LiteralPath (Join-Path $gamePath '.amp-coop-managed')) -or
        -not (Test-Path -LiteralPath (Join-Path $gamePath '.amp-coop-ready'))) { throw 'Complete Update before Start' }
    $config = Read-CoopConfig
    foreach ($entry in @{port=$Port; logFile=$true}.GetEnumerator()) {
        $config | Add-Member NoteProperty $entry.Key $entry.Value -Force
    }
    Write-CoopConfig $config
    $savePath = Join-Path $script:RootPath ('data/Game Saves/' + $config.saveName + '.sav')
    [IO.Directory]::CreateDirectory((Split-Path $savePath)) | Out-Null
    if (-not (Test-Path -LiteralPath $savePath)) {
        Copy-Item -LiteralPath (Join-Path $gamePath 'server-data/Game Saves/default_new_game.sav') -Destination $savePath
    }
    try { [xml]$moduleXml = [IO.File]::ReadAllText((Join-Path $gamePath 'engine/Modules/Coop/SubModule.xml')) }
    catch { throw 'Cannot read staged Coop SubModule.xml' }
    $moduleNode = $moduleXml.SelectSingleNode('/Module/Id')
    if ($null -eq $moduleNode -or $ExpectedModule -cnotmatch '^[A-Za-z0-9_.-]+$' -or $moduleNode.GetAttribute('value') -cne $ExpectedModule) {
        throw 'Installed Coop module ID does not match template CoopModuleId; update the template before Start'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $gamePath 'engine/dotnet/dotnet.exe'))) { throw 'Staged .NET engine is missing' }
    Write-Host '[coop] Pre-start preparation complete; AMP will launch the engine directly'
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        switch ($Action) {
            init { $null = Read-CoopConfig }
            update { Update-CoopWorkshop }
            prepare { Prepare-CoopServer $GamePort $EnginePort $ModuleId }
            login { Invoke-CoopInteractiveLogin }
        }
    } catch {
        [Console]::Error.WriteLine('[coop] ERROR: ' + $_.Exception.Message)
        exit 1
    }
}
