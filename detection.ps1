# =====================================================================
# Windows Update Telemetry Detection
# Intune Detection-Only Script
# =====================================================================

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
        return $null
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
        return @()
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
        ErrorCode  = $ErrorCode
        KB         = $KB
        UpdateName = $UpdateName
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
        return @()
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
        return @()
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

function Get-LastRebootReason {
    try {
        $event = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            Id      = 1074
        } -MaxEvents 1 -ErrorAction Stop

        if ($null -eq $event) {
            return $null
        }

        return [PSCustomObject]@{
            TimeCreated = Convert-DateSafe $event.TimeCreated
            Message     = $event.Message
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
        return @()
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
        $evidence = "EventId=$($failure.EventId), Time=$($failure.TimeCreated), Error=$($failure.ErrorCode), KB=$($failure.KB), Update=$($failure.UpdateName)"
        $state = "Issue"
    }
    elseif ($Result.PendingWUReboot -eq $true) {
        $reason = "Pending reboot"
        $evidence = "PendingWUReboot=True, LastBootTime=$($Result.LastBootTime)"
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
    else {
        $reason = "Healthy"
        $evidence = "LastHotfix=$($Result.LastInstalledHotfix), LastHotfixDate=$($Result.LastHotfixDate)"
        $state = "Healthy"
    }

    [PSCustomObject]@{
        HealthState  = $state
        LikelyReason = $reason
        Evidence     = $evidence
    }
}

function Write-DetectionOutput {
    param(
        [object]$Data
    )

    $primaryNic = $null

    if ($Data -and $Data.NetworkAdapters) {
        $primaryNic = $Data.NetworkAdapters |
            Where-Object { $_.Status -eq "Up" -and $_.MediaConnectionState -eq "Connected" } |
            Select-Object -First 1
    }

    $RecentFailures = @()

    if ($Data -and $Data.RecentWUFailures -and $Data.RecentWUFailures.Count -gt 0) {
        $RecentFailures = $Data.RecentWUFailures | Select-Object -First 3
    }

    $output = [PSCustomObject]@{
        ComputerName      = $Data.ComputerName
        HealthState       = $Data.HealthState
        LikelyReason      = $Data.LikelyReason
        Evidence          = $Data.Evidence

        LastRebootTime    = if ($Data.LastRebootReason) { $Data.LastRebootReason.TimeCreated } else { $null }
        LastRebootReason  = if ($Data.LastRebootReason) { $Data.LastRebootReason.Message } else { $null }

        RecentWUFailures  = if ($RecentFailures.Count -gt 0) {
            ($RecentFailures | ForEach-Object {
                "$($_.TimeCreated) | $($_.ErrorCode) | $($_.KB) | $($_.UpdateName)"
            }) -join " || "
        } else {
            $null
        }

        PendingWUReboot   = $Data.PendingWUReboot
        LastHotfix        = $Data.LastInstalledHotfix
        LastHotfixDate    = $Data.LastHotfixDate
        CFreeGB           = $Data.CFreeGB

        WUServiceStatus   = $Data.WUServiceStatus
        BITSServiceStatus = $Data.BITSServiceStatus

        PrimaryNic        = if ($primaryNic) { $primaryNic.Name } else { $null }
        PrimaryNicSpeed   = if ($primaryNic) { $primaryNic.LinkSpeed } else { $null }

        CollectedAt       = $Data.CollectedAt
    }

    $output | ConvertTo-Json -Compress
}

try {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}
catch {
    $fallback = [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        HealthState  = "Issue"
        LikelyReason = "Failed to create output folder"
        Evidence     = $_.Exception.Message
    }

    $fallback | ConvertTo-Json -Compress
    exit 1
}

$ComputerName = $env:COMPUTERNAME
$CollectedAt = Get-Date

try {
    $OS = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $BootTime = $OS.LastBootUpTime
    $UptimeDays = [math]::Round(((Get-Date) - $BootTime).TotalDays, 2)
}
catch {
    $OS = $null
    $BootTime = $null
    $UptimeDays = $null
}

try {
    $Disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
    $FreeSpaceGB = [math]::Round($Disk.FreeSpace / 1GB, 2)
    $TotalSpaceGB = [math]::Round($Disk.Size / 1GB, 2)
}
catch {
    $FreeSpaceGB = $null
    $TotalSpaceGB = $null
}

$LastHotfix = Get-LastInstalledUpdate
$RecentInstalledUpdates = @(Get-RecentInstalledUpdates -Count 10)
$RecentWUFailures = @(Get-RecentWindowsUpdateFailures -Count 10)
$RecentStoreFailures = @(Get-RecentStoreUpdateFailures -Count 10)

$PendingReboot = Get-PendingReboot

$WUService = Get-Service wuauserv -ErrorAction SilentlyContinue
$BITSService = Get-Service BITS -ErrorAction SilentlyContinue

$WSUSPolicyPresent = Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

$NetworkHealth = @(Test-NetworkHealth)
$NetworkAdapters = @(Get-NetworkAdapterHealth)
$LastRebootReason = Get-LastRebootReason

$Result = [PSCustomObject]@{
    ComputerName            = $ComputerName
    CollectedAt             = Convert-DateSafe $CollectedAt

    OSName                  = if ($OS) { $OS.Caption } else { $null }
    OSVersion               = if ($OS) { $OS.Version } else { $null }
    BuildNumber             = if ($OS) { $OS.BuildNumber } else { $null }
    LastBootTime            = Convert-DateSafe $BootTime
    UptimeDays              = $UptimeDays
    LastRebootReason        = $LastRebootReason

    LastInstalledHotfix     = if ($LastHotfix) { $LastHotfix.HotFixID } else { $null }
    LastHotfixDate          = if ($LastHotfix) { Convert-DateSafe $LastHotfix.InstalledOn } else { $null }
    RecentInstalledUpdates  = $RecentInstalledUpdates

    RecentWUFailures        = $RecentWUFailures
    RecentStoreFailures     = $RecentStoreFailures

    PendingWUReboot         = $PendingReboot

    WUServiceStatus         = if ($WUService) { $WUService.Status.ToString() } else { $null }
    WUServiceStartType      = if ($WUService) { $WUService.StartType.ToString() } else { $null }
    BITSServiceStatus       = if ($BITSService) { $BITSService.Status.ToString() } else { $null }
    BITSServiceStartType    = if ($BITSService) { $BITSService.StartType.ToString() } else { $null }

    WSUSPolicyPresent       = $WSUSPolicyPresent

    NetworkHealth           = $NetworkHealth
    NetworkAdapters         = $NetworkAdapters

    CFreeGB                 = $FreeSpaceGB
    CSizeGB                 = $TotalSpaceGB
}

$Health = Get-HealthSummary -Result $Result

$Result | Add-Member -NotePropertyName HealthState -NotePropertyValue $Health.HealthState -Force
$Result | Add-Member -NotePropertyName LikelyReason -NotePropertyValue $Health.LikelyReason -Force
$Result | Add-Member -NotePropertyName Evidence -NotePropertyValue $Health.Evidence -Force

try {
    $Result |
        ConvertTo-Json -Depth 10 |
        Out-File -FilePath $OutputFile -Encoding UTF8 -Force
}
catch {
    $Result | Add-Member -NotePropertyName HealthState -NotePropertyValue "Issue" -Force
    $Result | Add-Member -NotePropertyName LikelyReason -NotePropertyValue "Failed to write telemetry JSON" -Force
    $Result | Add-Member -NotePropertyName Evidence -NotePropertyValue $_.Exception.Message -Force

    Write-DetectionOutput -Data $Result
    exit 1
}

Write-DetectionOutput -Data $Result

if ($Result.HealthState -eq "Issue") {
    exit 1
}

exit 0
