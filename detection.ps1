# =====================================================================
# Windows Update Telemetry Detection
# Intune Detection Script
# =====================================================================

$JsonPath = "C:\ProgramData\Remediations\WindowsUpdate\UpdateHealth.json"

function Write-DetectionOutput {
    param(
        [string]$ComputerName,
        [string]$HealthState,
        [string]$LikelyReason,
        [string]$Evidence,
        [object]$Data = $null
    )

    $primaryNic = $null

    if ($Data -and $Data.NetworkAdapters) {
        $primaryNic = $Data.NetworkAdapters |
            Where-Object { $_.Status -eq "Up" -and $_.MediaConnectionState -eq "Connected" } |
            Select-Object -First 1
    }

$RecentFailures = @()

if ($Data -and $Data.RecentWUFailures -and $Data.RecentWUFailures.Count -gt 0) {

    $RecentFailures = $Data.RecentWUFailures |
        Select-Object -First 3

}

$output = [PSCustomObject]@{
    ComputerName         = $ComputerName
    LikelyReason         = $LikelyReason
    Evidence             = $Evidence
LastRebootTime = if ($Data -and $Data.LastRebootReason) {
    $Data.LastRebootReason.TimeCreated
} else {
    $null
}

LastRebootReason = if ($Data -and $Data.LastRebootReason) {
    $Data.LastRebootReason.Message
} else {
    $null
}

RecentWUFailures = if ($RecentFailures.Count -gt 0) {

    ($RecentFailures | ForEach-Object {

        "$($_.TimeCreated) | $($_.ErrorCode) | $($_.KB) | $($_.UpdateName)"

    }) -join " || "

} else {

    $null

}

    PendingWUReboot      = if ($Data) { $Data.PendingWUReboot } else { $null }

    LastHotfix           = if ($Data) { $Data.LastInstalledHotfix } else { $null }
    LastHotfixDate       = if ($Data) { $Data.LastHotfixDate } else { $null }

    CFreeGB              = if ($Data) { $Data.CFreeGB } else { $null }

    WUServiceStatus      = if ($Data) { $Data.WUServiceStatus } else { $null }
    BITSServiceStatus    = if ($Data) { $Data.BITSServiceStatus } else { $null }

    PrimaryNic           = if ($primaryNic) { $primaryNic.Name } else { $null }
    PrimaryNicSpeed      = if ($primaryNic) { $primaryNic.LinkSpeed } else { $null }

    CollectedAt          = if ($Data) { $Data.CollectedAt } else { $null }
}

    $output | ConvertTo-Json -Compress
}

if (-not (Test-Path $JsonPath)) {
    Write-DetectionOutput `
        -ComputerName $env:COMPUTERNAME `
        -HealthState "Issue" `
        -LikelyReason "No telemetry file found" `
        -Evidence "$JsonPath missing"

    exit 1
}

try {
    $data = Get-Content $JsonPath -Raw | ConvertFrom-Json
}
catch {
    Write-DetectionOutput `
        -ComputerName $env:COMPUTERNAME `
        -HealthState "Issue" `
        -LikelyReason "Invalid telemetry JSON" `
        -Evidence $_.Exception.Message

    exit 1
}

$reason = $data.LikelyReason
$evidence = $data.Evidence
$healthState = $data.HealthState

if ([string]::IsNullOrWhiteSpace($reason)) {
    $reason = "Unknown"
}

if ([string]::IsNullOrWhiteSpace($evidence)) {
    $evidence = "No evidence field found in telemetry JSON"
}

if ([string]::IsNullOrWhiteSpace($healthState)) {
    $healthState = "Issue"
}

Write-DetectionOutput `
    -ComputerName $data.ComputerName `
    -HealthState $healthState `
    -LikelyReason $reason `
    -Evidence $evidence `
    -Data $data

if ($healthState -eq "Issue") {
    exit 1
}

exit 0
