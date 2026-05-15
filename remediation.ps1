# =====================================================================
# Windows Update Telemetry Collection
# Intune Remediation Script
# =====================================================================

$LogName = "WindowsUpdate"
$Source = "WUHealth"
$OutputFolder = "C:\ProgramData\Remediations\WindowsUpdate"
$OutputFile = Join-Path $OutputFolder "UpdateHealth.json"

function Convert-DateSafe {
    param($Date)

    if ($null -eq $Date) { return $null }

    try {
        return ([datetime]$Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    catch {
        return $null
    }
}

function Get-PendingReboot {
    $pending = $false

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $pending = $true
    }

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $pending = $true
    }

    try {
        $sessionManager = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction Stop
        if ($sessionManager.PendingFileRenameOperations) {
            $pending = $true
        }
    }
    catch {}

    return $pending
}

function Get-LastInstalledUpdate {
    try {
        Get-HotFix |
            Where-Object { $_.InstalledOn } |
            Sort-Object InstalledOn -Descending |
            Select-Object -First 1
    }
    catch {
        $null
    }
}

function Get-RecentInstalledUpdates {
    param([int]$Count = 10)

    try {
        Get-HotFix |
            Where-Object { $_.InstalledOn } |
            Sort-Object InstalledOn -Descending |
            Select-Object -First $Count |
            ForEach-Object {
                [PSCustomObject]@{
                    HotFixID    = $_.HotFixID
                    Description = $_.Description
                    InstalledOn = Convert-DateSafe $_.InstalledOn
                    InstalledBy = $_.InstalledBy
                }
            }
    }
    catch {
        @()
    }
}

function Get-RecentWindowsUpdateFailures {
    param([int]$Count = 10)

    try {
        Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-WindowsUpdateClient'
            Level        = 2
        } -MaxEvents 100 -ErrorAction Stop |
        Where-Object {
            $_.Message -notmatch 'MICROSOFT\.WINDOWSSTORE|WindowsStore|Spotify|DesktopAppInstaller|9WZDNCRFJBMP|9NCBCSZSJRSB|9NBLGGH4NNS1'
        } |
        Select-Object -First $Count |
        ForEach-Object {
$details = Get-WUFailureDetails $_.Message

[PSCustomObject]@{
    TimeCreated = Convert-DateSafe $_.TimeCreated
    EventId     = $_.Id
    ErrorCode   = $details.ErrorCode
    KB          = $details.KB
    UpdateName  = $details.UpdateName
    Message     = $_.Message
}
        }
    }
    catch {
        @()
    }
}

function Get-RecentStoreUpdateFailures {
    param([int]$Count = 10)

    try {
        Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-WindowsUpdateClient'
            Level        = 2
        } -MaxEvents 100 -ErrorAction Stop |
        Where-Object {
            $_.Message -match 'MICROSOFT\.WINDOWSSTORE|WindowsStore|Spotify|DesktopAppInstaller|9WZDNCRFJBMP|9NCBCSZSJRSB|9NBLGGH4NNS1'
        } |
        Select-Object -First $Count |
        ForEach-Object {
            [PSCustomObject]@{
                TimeCreated = Convert-DateSafe $_.TimeCreated
                EventId     = $_.Id
                Message     = $_.Message
            }
        }
    }
    catch {
        @()
    }
}

function Test-NetworkHealth {
    $tests = @(
        @{ Name = "Microsoft Update"; Host = "fe2.update.microsoft.com"; Port = 443 },
        @{ Name = "Windows Update"; Host = "sls.update.microsoft.com"; Port = 443 },
        @{ Name = "Delivery Optimization"; Host = "dl.delivery.mp.microsoft.com"; Port = 443 },
        @{ Name = "Microsoft Store"; Host = "storeedgefd.dsx.mp.microsoft.com"; Port = 443 }
    )

    foreach ($test in $tests) {
        try {
            $tcp = Test-NetConnection `
                -ComputerName $test.Host `
                -Port $test.Port `
                -InformationLevel Quiet `
                -WarningAction SilentlyContinue

            [PSCustomObject]@{
                Name      = $test.Name
                Host      = $test.Host
                Port      = $test.Port
                TcpPassed = $tcp
            }
        }
        catch {
            [PSCustomObject]@{
                Name      = $test.Name
                Host      = $test.Host
                Port      = $test.Port
                TcpPassed = $false
            }
        }
    }
}

function Get-WUFailureDetails {
    param([string]$Message)

    $ErrorCode = $null
    $KB = $null
    $UpdateName = $null

    if ($Message -match 'error (0x[0-9A-Fa-f]+)') {
        $ErrorCode = $matches[1]
    }

    if ($Message -match '(KB\d{7})') {
        $KB = $matches[1]
    }

    if ($Message -match 'error .*?: (.*)$') {
        $UpdateName = $matches[1]
    }

    [PSCustomObject]@{
        ErrorCode = $ErrorCode
        KB = $KB
        UpdateName = $UpdateName
    }
}

function Get-LastRebootReason {

    try {

        $event = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            Id = 1074
        } -MaxEvents 1 -ErrorAction Stop

        if ($null -eq $event) {
            return $null
        }

        return [PSCustomObject]@{
            TimeCreated = Convert-DateSafe $event.TimeCreated
            Message      = $event.Message
        }
    }
    catch {
        return $null
    }
}

function Get-NetworkAdapterHealth {
    try {
        Get-NetAdapter |
            Where-Object {
                $_.Status -eq "Up" -and
                $_.HardwareInterface -eq $true
            } |
            ForEach-Object {
                [PSCustomObject]@{
                    Name                 = $_.Name
                    InterfaceDesc        = $_.InterfaceDescription
                    Status               = $_.Status.ToString()
                    LinkSpeed            = $_.LinkSpeed
                    MacAddress           = $_.MacAddress
                    DriverVersion        = $_.DriverVersion
                    DriverDate           = Convert-DateSafe $_.DriverDate
                    MediaConnectionState = $_.MediaConnectionState.ToString()
                }
            }
    }
    catch {
        @()
    }
}

function Get-HealthSummary {
    param($Result)

    $reason = "Healthy"
    $evidence = "No major issue detected"
    $state = "Healthy"

    if ($Result.CFreeGB -lt 15) {
        $reason = "Low disk space"
        $evidence = "CFreeGB=$($Result.CFreeGB)"
        $state = "Issue"
    }
    elseif ($Result.NetworkHealth | Where-Object { $_.TcpPassed -eq $false }) {
        $failed = $Result.NetworkHealth | Where-Object { $_.TcpPassed -eq $false } | Select-Object -First 1
        $reason = "Microsoft update endpoint connectivity failure"
        $evidence = "$($failed.Name) $($failed.Host):$($failed.Port) TcpPassed=False"
        $state = "Issue"
    }
    elseif ($Result.WUServiceStatus -eq "Disabled" -or $Result.BITSServiceStatus -eq "Disabled") {
        $reason = "Update service disabled"
        $evidence = "WUService=$($Result.WUServiceStatus), BITS=$($Result.BITSServiceStatus)"
        $state = "Issue"
    }
    elseif ($Result.RecentWUFailures.Count -gt 0) {
        $failure = $Result.RecentWUFailures | Select-Object -First 1
        $reason = "Windows Update failure events detected"
        $evidence = "EventId=$($failure.EventId), Time=$($failure.TimeCreated), Message=$($failure.Message)"
        $state = "Issue"
    }
    elseif ($Result.RecentStoreFailures.Count -gt 0) {
        $failure = $Result.RecentStoreFailures | Select-Object -First 1
        $reason = "Store app update failures only"
        $evidence = "EventId=$($failure.EventId), Time=$($failure.TimeCreated), Message=$($failure.Message)"
        $state = "Warning"
    }
    elseif ($Result.RecentInstalledUpdates.Count -eq 0) {
        $reason = "No recent installed updates found"
        $evidence = "RecentInstalledUpdates=0"
        $state = "Issue"
    }
        elseif ($Result.PendingWUReboot -eq $true) {
        $reason = "Pending reboot"
        $evidence = "PendingWUReboot=True, LastBootTime=$($Result.LastBootTime)"
        $state = "Issue"
    }
    else {
        $reason = "Healthy"
        $evidence = "LastHotfix=$($Result.LastInstalledHotfix), LastHotfixDate=$($Result.LastHotfixDate)"
        $state = "Healthy"
    }

    return [PSCustomObject]@{
        HealthState  = $state
        LikelyReason = $reason
        Evidence     = $evidence
    }
}

try {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}
catch {
    Write-Output "Failed to create output folder: $($_.Exception.Message)"
    exit 1
}

$CanWriteEventLog = $false

try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($Source)) {
        New-EventLog -LogName $LogName -Source $Source -ErrorAction Stop
    }

    $CanWriteEventLog = $true
}
catch {
    Write-Output "Event log source unavailable: $($_.Exception.Message)"
}

$ComputerName = $env:COMPUTERNAME
$CollectedAt = Get-Date

$OS = Get-CimInstance Win32_OperatingSystem
$BootTime = $OS.LastBootUpTime
$UptimeDays = [math]::Round(((Get-Date) - $BootTime).TotalDays, 2)

$Disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$FreeSpaceGB = [math]::Round($Disk.FreeSpace / 1GB, 2)
$TotalSpaceGB = [math]::Round($Disk.Size / 1GB, 2)

$LastHotfix = Get-LastInstalledUpdate
$RecentInstalledUpdates = Get-RecentInstalledUpdates -Count 10
$RecentWUFailures = Get-RecentWindowsUpdateFailures -Count 10
$RecentStoreFailures = Get-RecentStoreUpdateFailures -Count 10

$PendingReboot = Get-PendingReboot

$WUService = Get-Service wuauserv -ErrorAction SilentlyContinue
$BITSService = Get-Service BITS -ErrorAction SilentlyContinue

$WSUSPolicyPresent = Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

$NetworkHealth = Test-NetworkHealth
$NetworkAdapters = Get-NetworkAdapterHealth
$LastRebootReason = Get-LastRebootReason

$Result = [PSCustomObject]@{
    ComputerName             = $ComputerName
    CollectedAt              = Convert-DateSafe $CollectedAt

    OSName                   = $OS.Caption
    OSVersion                = $OS.Version
    BuildNumber              = $OS.BuildNumber
    LastBootTime             = Convert-DateSafe $BootTime
    UptimeDays               = $UptimeDays
    LastRebootReason         = $LastRebootReason

    LastInstalledHotfix      = $LastHotfix.HotFixID
    LastHotfixDate           = Convert-DateSafe $LastHotfix.InstalledOn
    RecentInstalledUpdates   = $RecentInstalledUpdates

    RecentWUFailures         = $RecentWUFailures
    RecentStoreFailures      = $RecentStoreFailures

    PendingWUReboot          = $PendingReboot

    WUServiceStatus          = if ($WUService) { $WUService.Status.ToString() } else { $null }
    WUServiceStartType       = if ($WUService) { $WUService.StartType.ToString() } else { $null }
    BITSServiceStatus        = if ($BITSService) { $BITSService.Status.ToString() } else { $null }
    BITSServiceStartType     = if ($BITSService) { $BITSService.StartType.ToString() } else { $null }

    WSUSPolicyPresent        = $WSUSPolicyPresent

    NetworkHealth            = $NetworkHealth
    NetworkAdapters          = $NetworkAdapters

    CFreeGB                  = $FreeSpaceGB
    CSizeGB                  = $TotalSpaceGB
}

$Health = Get-HealthSummary -Result $Result

$Result | Add-Member -NotePropertyName HealthState -NotePropertyValue $Health.HealthState -Force
$Result | Add-Member -NotePropertyName LikelyReason -NotePropertyValue $Health.LikelyReason -Force
$Result | Add-Member -NotePropertyName Evidence -NotePropertyValue $Health.Evidence -Force

try {
    $Result |
        ConvertTo-Json -Depth 10 |
        Out-File -FilePath $OutputFile -Encoding UTF8 -Force

    Write-Output "Telemetry written to $OutputFile"
    Write-Output "WUHealth|Computer=$($Result.ComputerName)|HealthState=$($Result.HealthState)|Reason=$($Result.LikelyReason)|Evidence=$($Result.Evidence)"
}
catch {
    Write-Output "Failed to write telemetry file: $($_.Exception.Message)"
    exit 1
}

if ($CanWriteEventLog) {
    try {
        Write-EventLog `
            -LogName $LogName `
            -Source $Source `
            -EventId 1000 `
            -EntryType Information `
            -Message "Windows Update telemetry collected. HealthState=$($Result.HealthState), Reason=$($Result.LikelyReason), Evidence=$($Result.Evidence)"
    }
    catch {}
}

exit 0
