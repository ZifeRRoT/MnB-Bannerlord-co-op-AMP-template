$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoPath = Split-Path $PSScriptRoot
. (Join-Path $repoPath 'mount-and-blade2-coop.ps1')
$testParent = [IO.Path]::GetFullPath((Join-Path $repoPath '.research'))
$testPath = Join-Path $testParent ('windows-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testPath) | Out-Null
$script:RootPath = Join-Path $testPath 'instance with spaces/bannerlord-coop'
[IO.Directory]::CreateDirectory($script:RootPath) | Out-Null
$script:Checks = 0
function Assert-Coop([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:Checks++
    Write-Host "PASS $Message"
}
function Assert-CoopFailure([scriptblock]$Operation, [string]$Message) {
    $failed = $false
    try { & $Operation | Out-Null } catch { $failed = $true }
    Assert-Coop $failed $Message
}
try {
    $initial = Read-CoopConfig
    Assert-Coop ($initial.saveName -eq 'saveauto1' -and $initial.steam -eq $false) 'Windows init creates AutoMap target with Steam advertising off'
    $configPath = Join-Path $script:RootPath 'data/server-config.json'
    $password = 'p"a\ss,} | & $(should-not-run)' + [char]10 + [char]0x041F + [char]0x0440
    $initial.saveName = 'dadada'
    $initial.password = $password
    $initial.autosaveMinutes = 7
    $initial.steam = $true
    $initial | Add-Member NoteProperty futureOption 42
    Write-CoopConfig $initial
    Assert-Coop ((Read-CoopConfig).password -ceq $password) 'JSON password preserves quotes, newline, Unicode and shell metacharacters'

    $gamePath = Join-Path $script:RootPath 'workshop/steamapps/workshop/content/261550/3770450698/DedicatedServer'
    [IO.Directory]::CreateDirectory((Join-Path $gamePath 'engine/dotnet')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $gamePath 'engine/Modules/Coop')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $gamePath 'engine/bin/Win64_Shipping_Server')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $gamePath 'server-data/Game Saves')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $gamePath 'engine/dotnet/dotnet.exe'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $gamePath 'engine/Modules/Coop/SubModule.xml'), '<Module><Id value="Coop" /></Module>')
    [IO.File]::WriteAllText((Join-Path $gamePath 'server-data/Game Saves/default_new_game.sav'), 'new campaign')
    Assert-Coop ((Find-CoopGame) -eq $gamePath) 'Windows discovers native SteamCMD Workshop layout'
    Copy-CoopServer
    Assert-Coop (Test-Path -LiteralPath (Join-Path $script:RootPath 'server/.amp-coop-managed')) 'Windows Update stages a physical managed engine directory'
    Prepare-CoopServer 4400 7210 Coop
    $after = Read-CoopConfig
    Assert-Coop ($after.saveName -eq 'dadada' -and $after.password -ceq $password -and $after.port -eq 4400 -and $after.futureOption -eq 42 -and $after.steam -eq $true) 'Pre-start preserves AMP fields including Steam advertising, sets allocated port'
    $savePath = Join-Path $script:RootPath 'data/Game Saves/dadada.sav'
    Assert-Coop ([IO.File]::ReadAllText($savePath) -eq 'new campaign') 'First Start seeds missing campaign'
    [IO.File]::WriteAllText($savePath, 'existing progress')
    $after.steam = $false
    Write-CoopConfig $after
    Prepare-CoopServer 4400 7210 Coop
    Assert-Coop ([IO.File]::ReadAllText($savePath) -eq 'existing progress' -and (Read-CoopConfig).steam -eq $false) 'Repeated Pre-start preserves progress and disabled Steam advertising'
    Assert-CoopFailure { Prepare-CoopServer 4400 4401 Coop } 'Overlapping Windows allocations are rejected'
    Assert-CoopFailure { Prepare-CoopServer 4400 7210 CoopNightly } 'Mismatched module ID is rejected before launch'

    $markerPath = Join-Path $script:RootPath 'server/.amp-coop-managed'
    Remove-Item -LiteralPath $markerPath
    Assert-CoopFailure { Copy-CoopServer } 'Windows Update refuses an unmanaged staging directory'
    Assert-Coop (Test-Path -LiteralPath $savePath) 'Staging refusal leaves persistent data intact'
    [IO.File]::WriteAllText($markerPath, '')
    $staleFile = Join-Path $script:RootPath 'server/stale.dll'
    [IO.File]::WriteAllText($staleFile, 'old')
    Copy-CoopServer
    Assert-Coop (-not (Test-Path -LiteralPath $staleFile)) 'Managed Windows staging removes stale application files'
    Assert-Coop ([IO.File]::ReadAllText($savePath) -eq 'existing progress') 'Restaging never removes campaign data'

    [IO.Directory]::CreateDirectory((Join-Path $script:RootPath 'config')) | Out-Null
    $cachePath = Join-Path $script:RootPath 'config/config.vdf'
    [IO.File]::WriteAllText($cachePath, '"InstallConfigStore" { "Software" { "Valve" { "Steam" { "ConnectCache" { "id" "PRIVATE_TOKEN" } "Accounts" { "OWNER" { "SteamID" "123" } } } } } }')
    Assert-Coop ((@(Get-CoopAccounts) -join ',') -eq 'owner') 'Windows cache parser reads only the cached account name'
    [IO.File]::WriteAllText($cachePath, '"ConnectCache" "PRIVATE_TOKEN" malformed')
    $cacheError = $null
    try { Get-CoopAccounts | Out-Null } catch { $cacheError = $_.Exception.Message }
    Assert-Coop ($null -ne $cacheError -and -not $cacheError.Contains('PRIVATE_TOKEN')) 'Malformed cache errors do not reveal token contents'

    # A failed native AMP login must produce one useful line, not a PowerShell
    # stack trace or any dump of the private cache contents.
    [IO.File]::WriteAllText($cachePath, '"InstallConfigStore" { "Software" { } }')
    $helperPath = Join-Path $script:RootPath 'mount-and-blade2-coop.ps1'
    Copy-Item -LiteralPath (Join-Path $repoPath 'mount-and-blade2-coop.ps1') -Destination $helperPath
    $helperInfo = New-Object Diagnostics.ProcessStartInfo
    $helperInfo.FileName = Join-Path $PSHOME 'powershell.exe'
    $helperInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $helperPath + '" -Action update'
    $helperInfo.UseShellExecute = $false
    $helperInfo.CreateNoWindow = $true
    $helperInfo.RedirectStandardOutput = $true
    $helperInfo.RedirectStandardError = $true
    $helperProcess = New-Object Diagnostics.Process
    $helperProcess.StartInfo = $helperInfo
    try {
        [void]$helperProcess.Start()
        $helperOut = $helperProcess.StandardOutput.ReadToEndAsync()
        $helperError = $helperProcess.StandardError.ReadToEndAsync()
        if (-not $helperProcess.WaitForExit(10000)) { $helperProcess.Kill(); throw 'Helper diagnostic test timed out' }
        $helperProcess.WaitForExit()
        $diagnostic = $helperOut.Result + $helperError.Result
        Assert-Coop ($helperProcess.ExitCode -eq 1 -and $diagnostic.Contains('-Action login') -and
            -not $diagnostic.Contains('CategoryInfo') -and -not $diagnostic.Contains('PRIVATE_TOKEN')) 'Incomplete Steam sign-in reports a safe actionable error without a stack trace'
    } finally { $helperProcess.Dispose() }

    # This disposable real Windows console exe verifies closed stdin and argument
    # quoting in the native cached SteamCMD process boundary, without any account.
    $fakeExe = Join-Path $script:RootPath 'steamcmd.exe'
    Add-Type -TypeDefinition @'
using System;
public static class CoopFakeSteam {
  public static int Main(string[] args) {
    if (args.Length == 1 && args[0] == "--console-probe") {
      string data = System.IO.Path.GetFullPath(Environment.GetEnvironmentVariable("BANNERLORD_USER_DIR"));
      Console.WriteLine(System.IO.File.Exists(System.IO.Path.Combine(data,"server-config.json")) ? "DIRECT_DATA_PATH_OK" : "BAD_DATA_PATH");
      Console.WriteLine("DIRECT_READY");
      if (Console.ReadLine() != "stop") return 7;
      Console.WriteLine("DIRECT_CONSOLE_STOP_OK");
      return 0;
    }
    if (Console.ReadLine() != null) return 9;
    if (Array.IndexOf(args, "+@NoPromptForPassword") < 0) return 8;
    Console.WriteLine("Success. Downloaded item 3770450698 to workshop");
    Console.Error.WriteLine("stderr captured");
    return 0;
  }
}
'@ -OutputAssembly $fakeExe -OutputType ConsoleApplication
    $processResult = Invoke-CoopSteam @('+@NoPromptForPassword','1','+force_install_dir',(Join-Path $script:RootPath 'workshop'),'+login','owner','+quit') 30
    Assert-Coop ($processResult.ExitCode -eq 0 -and $processResult.Output.Contains('stderr captured')) 'Native Windows SteamCMD boundary closes stdin and captures both output streams'
    Assert-Coop (-not $processResult.Output.Contains($password)) 'No server password is passed to SteamCMD'

    $consoleInfo = New-Object Diagnostics.ProcessStartInfo
    $consoleInfo.FileName = $fakeExe
    $consoleInfo.Arguments = '--console-probe'
    $consoleInfo.WorkingDirectory = Join-Path $script:RootPath 'server/engine/bin/Win64_Shipping_Server'
    $consoleInfo.EnvironmentVariables['BANNERLORD_USER_DIR'] = Join-Path $script:RootPath 'data'
    $consoleInfo.UseShellExecute = $false
    $consoleInfo.CreateNoWindow = $true
    $consoleInfo.RedirectStandardInput = $true
    $consoleInfo.RedirectStandardOutput = $true
    $console = New-Object Diagnostics.Process
    $console.StartInfo = $consoleInfo
    try {
        [void]$console.Start()
        $readyLine = $console.StandardOutput.ReadLineAsync()
        if (-not $readyLine.Wait(10000)) { throw 'Windows console startup timed out' }
        Assert-Coop ($readyLine.Result -eq 'DIRECT_DATA_PATH_OK') 'Direct Windows console resolves the absolute persistent data path'
        $console.StandardInput.WriteLine('stop')
        $console.StandardInput.Close()
        if (-not $console.WaitForExit(10000)) { throw 'Windows console stop timed out' }
        $consoleOutput = $console.StandardOutput.ReadToEnd()
        Assert-Coop ($console.ExitCode -eq 0 -and $consoleOutput.Contains('DIRECT_CONSOLE_STOP_OK')) 'Direct Windows executable accepts stop through redirected stdin'
    } finally {
        if (-not $console.HasExited) { $console.Kill() }
        $console.Dispose()
    }

    [IO.File]::WriteAllText($configPath, '{"password":"PRIVATE_PASSWORD", // invalid JSON' , $script:Utf8)
    $jsonError = $null
    try { Read-CoopConfig | Out-Null } catch { $jsonError = $_.Exception.Message }
    Assert-Coop ($null -ne $jsonError -and -not $jsonError.Contains('PRIVATE_PASSWORD')) 'Invalid JSON fails without logging its password'
    $kvp = [IO.File]::ReadAllText((Join-Path $repoPath 'mount-and-blade2-coop.kvp'))
    $environmentJson = [regex]::Match($kvp, '(?m)^App\.EnvironmentVariables=(.*)$').Groups[1].Value | ConvertFrom-Json
    $settingsManifest = [IO.File]::ReadAllText((Join-Path $repoPath 'mount-and-blade2-coopconfig.json')) | ConvertFrom-Json
    $eulaSetting = @($settingsManifest | Where-Object FieldName -eq 'AcceptEULA')
    Assert-Coop ($kvp.Contains('App.ExecutableWin=server\engine\dotnet\dotnet.exe') -and $kvp.Contains('Meta.OS=Windows, Linux') -and
        $environmentJson.DS_ACCEPT_EULA -ceq '{{AcceptEULA}}' -and $eulaSetting.Count -eq 1 -and $eulaSetting[0].DefaultValue -eq 'false') 'Native startup uses the optional EULA environment flag, disabled by default'
    $monitorPattern = [regex]::Match($kvp, '(?m)^App\.MonitorChildProcessName=(.*)$').Groups[1].Value.Trim().Replace('{{$EnginePort}}','7210')
    Assert-Coop (([regex]::IsMatch('"D:\AMP instance\server\engine\dotnet\dotnet.exe" TaleWorlds.Starter.DotNetCore.dll modules /dedicatedcustomserver 7210 EU 0',$monitorPattern)) -and
        ([regex]::IsMatch('../../dotnet/dotnet.exe TaleWorlds.Starter.DotNetCore.dll modules /dedicatedcustomserver 7210 EU 0',$monitorPattern))) 'Process monitor matches native Windows and Wine engine commands'
    Assert-Coop ((-not [regex]::IsMatch('/usr/bin/socat STDIO EXEC:/usr/bin/wine ../../dotnet/dotnet.exe TaleWorlds.Starter.DotNetCore.dll modules /dedicatedcustomserver 7210 EU 0,pty',$monitorPattern)) -and
        (-not [regex]::IsMatch('dotnet.exe TaleWorlds.Starter.DotNetCore.dll modules /dedicatedcustomserver 7211 EU 0',$monitorPattern))) 'Process monitor excludes relay and other instance engine ports'
    Write-Host "All $script:Checks Windows checks passed"
} finally {
    # Exact resolved temp path is checked before this recursive Windows removal.
    $resolvedTest = [IO.Path]::GetFullPath($testPath)
    if ((Split-Path $resolvedTest) -eq $testParent -and (Split-Path $resolvedTest -Leaf) -like 'windows-tests-*') {
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
}
