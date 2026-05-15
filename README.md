# Intune Windows Update Telemetry

Windows Update telemetry collection and reporting script for Microsoft Intune.

This script was built to help investigate Windows devices that are behind on security updates despite remaining active and checking into Intune and Microsoft Defender.

Native Intune reporting provides compliance visibility, but often lacks the operational telemetry required to determine *why* devices are not patching successfully.

This solution collects local Windows Update telemetry, stores it as structured JSON, and surfaces condensed diagnostics directly into Intune Remediations output for centralized review and export.

---

# Features

## Telemetry Collection

The detection script collects:

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

Telemetry is written locally to:

```text
C:\ProgramData\Remediations\WindowsUpdate\UpdateHealth.json
```

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
├── detection.ps1
└── README.md
```

---

# How It Works

## Detection Script

The detection script:

1. Collects local Windows Update telemetry
2. Writes structured telemetry JSON locally
3. Calculates a likely operational health state
4. Outputs compact JSON into Intune Remediations reporting

The script is intentionally detection-only and does not perform remediation or servicing actions on the endpoint.

Example classifications include:

- Pending reboot
- Windows Update failure events detected
- Microsoft Update connectivity failure
- Low disk space
- Store/runtime update failures only
- Healthy

The script also separates Microsoft Store/runtime package failures from core Windows Update servicing failures to reduce operational noise.

---

# Example Detection Output

```json
{
  "ComputerName":"PC-001",
  "HealthState":"Issue",
  "LikelyReason":"Windows Update failure events detected",
  "Evidence":"EventId=20, Time=2026-05-13 17:44:52, Error=0x800F0905, KB=KB5083769",
  "RecentWUFailures":"2026-05-13 17:44:52 | 0x800F0905 | KB5083769 | 2026-04 Security Update (KB5083769)",
  "PendingWUReboot":true,
  "LastHotfix":"KB5068865",
  "LastHotfixDate":"2026-05-11 00:00:00",
  "CFreeGB":22.13,
  "WUServiceStatus":"Running",
  "BITSServiceStatus":"Running",
  "PrimaryNic":"Ethernet",
  "PrimaryNicSpeed":"1 Gbps"
}
```

---

# Intune Deployment

Deploy using:

```text
Microsoft Intune
→ Devices
→ Scripts and remediations
```

Upload the script as a **Detection script**.

A remediation script is optional and not required for telemetry collection.

---

## Recommended Configuration

| Setting | Value |
|---|---|
| Run script in 64-bit PowerShell | Yes |
| Run this script using logged-on credentials | No |
| Enforce signature check | No |
| Frequency | Daily or every 6 hours |

---

# Viewing the Data

Detection output can be viewed directly in Intune:

```text
Devices
→ Scripts and remediations
→ [Your Script]
→ Device status
```

Enable the following columns:

- Pre-remediation detection output
- Post-remediation detection output

Telemetry can then be:

- Exported to CSV
- Imported into Excel
- Analysed
---

# Important Notes

## Intune Output Limitations

Intune Remediations output is size constrained.

The script intentionally summarizes telemetry into compact operational fields while storing richer telemetry locally in JSON format.

---

## Native Intune Reporting Limitations

Native Windows Update for Business and Feature Update reporting primarily provides:

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

This script is intended to complement native Intune reporting, not replace it.

---

# Requirements

- Windows 10 or Windows 11
- Microsoft Intune
- PowerShell 5.1+
- Administrative privileges
- Endpoint Analytics Remediations licensing

---

# Disclaimer

This script is provided as-is with no warranty.

Test thoroughly before deploying broadly in production environments.

---

# License

MIT License
