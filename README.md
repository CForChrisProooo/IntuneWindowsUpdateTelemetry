# IntuneWindowsUpdateTelemetry
# Intune Windows Update Telemetry Scripts

Windows Update telemetry collection and reporting scripts for Microsoft Intune.

These scripts were built to help investigate Windows devices that are behind on security updates despite remaining active and checking into Intune/Defender. 
Native Intune reporting provides compliance visibility, but often lacks the operational telemetry required to determine *why* devices are not patching successfully.

This solution collects local Windows Update telemetry, stores it as structured JSON, and surfaces condensed diagnostics directly into Intune Remediations output for centralized review.

---

# Features

## Telemetry Collection

The remediation script collects:

- Windows version/build information
- Last installed hotfix
- Recent installed updates
- Recent Windows Update failures
- Windows Update HRESULT error codes
- Failed KB/package names
- Pending reboot state
- Last reboot reason
- Windows Update service status
- BITS service status
- Disk space availability
- Microsoft Update connectivity checks
- Network adapter health
- Device uptime
- Last boot time

---

# Example Use Cases

- Devices several months behind on updates
- Devices checking into Intune but not patching
- Identifying reboot-related servicing issues
- Identifying recurring KB failures
- Identifying intermittent device usage patterns
- Governance/risk reporting
- SOC operational evidence gathering
- Bulk update troubleshooting without interactive device access

---

# Repository Structure

```text
.
├── remediation.ps1
├── detection.ps1
└── README.md
```

---

# How It Works

## Remediation Script

The remediation script:

1. Collects local Windows Update telemetry
2. Writes telemetry to:
   ```text
   C:\ProgramData\Remediations\WindowsUpdate\UpdateHealth.json
   ```
3. Outputs summarized telemetry for Intune reporting allowing the key data to be exported from Intune.

---

## Detection Script

The detection script:

- Reads the JSON telemetry file
- Extracts condensed operational diagnostics
- Outputs compact JSON into Intune Remediations reporting

This allows:
- Intune reporting visibility
- Defender Advanced Hunting ingestion
- Export to CSV/Excel
- Governance reporting

---

# Example Detection Output

```json
{
  "ComputerName":"PC-001",
  "LikelyReason":"Windows Update failure events detected",
  "RecentWUFailures":"2026-05-13 17:44:52 | 0x800F0905 | KB5083769 | 2026-04 Security Update (KB5083769)",
  "PendingWUReboot":true,
  "LastHotfix":"KB5068865",
  "CFreeGB":22.13,
  "WUServiceStatus":"Running",
  "BITSServiceStatus":"Running"
}
```

---

# Intune Deployment

Deploy using:

- Microsoft Intune
- Devices > Scripts and Remediations
- Endpoint Analytics Remediations

## Recommended Configuration

| Setting | Value |
|---|---|
| Run script in 64-bit PowerShell | Yes |
| Run this script using logged-on credentials | No |
| Enforce signature check | No |
| Frequency | Daily or 6-hour interval |

---

# Important Notes

## Intune Output Limitations

Intune Remediations output is size constrained.  
The scripts intentionally summarize telemetry into compact fields while storing richer telemetry locally in JSON format.

---

## Native Intune Reporting Limitations

Native Windows Update for Business and Feature Update reports primarily provide:

- compliance visibility
- deployment state
- safeguard holds
- orchestration telemetry

They do **not** provide deep endpoint troubleshooting telemetry such as:

- detailed Windows Update HRESULT analysis
- reboot behavior
- BITS/WU service health
- local servicing corruption evidence
- operational root-cause diagnostics

These scripts are intended to complement native Intune reporting, not replace it.

---

# Requirements

- Windows 10/11
- Microsoft Intune
- PowerShell 5.1+
- Administrative privileges
- Endpoint Analytics Remediations licensing

---

# Disclaimer

These scripts are provided as-is with no warranty.  
Test thoroughly before deploying broadly in production environments.

---

# License

MIT License
