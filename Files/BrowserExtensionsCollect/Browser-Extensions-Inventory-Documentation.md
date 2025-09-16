# Browser Extensions Inventory Collection for Azure Log Analytics

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites and Requirements](#prerequisites-and-requirements)
3. [Configuration Parameters and Setup](#configuration-parameters-and-setup)
4. [Detailed Functionality Breakdown](#detailed-functionality-breakdown)
5. [Data Collection Methodology](#data-collection-methodology)
6. [Azure Log Analytics Integration](#azure-log-analytics-integration)
7. [Security Considerations](#security-considerations)
8. [Deployment and Usage](#deployment-and-usage)
9. [Troubleshooting Guide](#troubleshooting-guide)
10. [Best Practices](#best-practices)

## Overview

### Purpose
The **Collect-BrowserExtentionsToLogAnalytics.ps1** script is designed to collect comprehensive browser extension inventory data from enterprise endpoints and upload it to Azure Log Analytics for security monitoring, compliance reporting, and risk assessment purposes.

### Scope
This script automatically discovers and inventories browser extensions across:
- **Google Chrome** (all user profiles)
- **Microsoft Edge** (all user profiles)
- **Mozilla Firefox** (all user profiles)

### Business Value
- **Security Compliance**: Monitor potentially risky or unauthorized browser extensions
- **Risk Assessment**: Identify shadow IT and non-approved browser add-ons
- **Audit Requirements**: Maintain detailed inventory for compliance reporting
- **Centralized Monitoring**: Aggregate extension data across enterprise endpoints

## Prerequisites and Requirements

### System Requirements
- **Operating System**: Windows 10/11, Windows Server 2016 or later
- **PowerShell**: Windows PowerShell 5.1 or later
- **Network Access**: HTTPS connectivity to Azure Log Analytics (*.ods.opinsights.azure.com)
- **Permissions**: Local administrator rights or equivalent to read user profile data

### Azure Requirements
- **Azure Subscription**: Active Azure subscription with Log Analytics workspace
- **Log Analytics Workspace**: Configured workspace with primary key access
- **Network Configuration**: Firewall rules allowing outbound HTTPS to Azure endpoints

### Required Modules and Dependencies
```powershell
# No additional PowerShell modules required - uses built-in capabilities:
# - WMI (Win32_UserProfile)
# - System.Security.Cryptography
# - Invoke-WebRequest
```

## Configuration Parameters and Setup

### Initial Configuration
Before executing the script, configure the following parameters at the top of the script:

```powershell
#**************************** Log Analytics Workspace Info ****************************
$WorkspaceId = "12345678-1234-1234-1234-123456789012" # Log Analytics Workspace ID (GUID)
$PrimaryKey = "base64encodedprimarykey==" # Log Analytics Workspace Primary Key
$LogType = "BrowserExtensionsInventory" # Custom log name in Log Analytics
$TimeStampField = "" # Leave blank unless you want to specify a time field
#*************************************************************************************
```

### Parameter Details

| Parameter | Type | Description | Required | Example |
|-----------|------|-------------|----------|---------|
| `$WorkspaceId` | GUID | Azure Log Analytics Workspace ID | Yes | `12345678-1234-1234-1234-123456789012` |
| `$PrimaryKey` | String | Workspace primary key (base64 encoded) | Yes | `abcd1234base64key==` |
| `$LogType` | String | Custom log table name in Log Analytics | Yes | `BrowserExtensionsInventory` |
| `$TimeStampField` | String | Custom timestamp field (optional) | No | Leave empty for system timestamp |

### Obtaining Azure Log Analytics Credentials

1. **Navigate to Azure Portal**: Go to portal.azure.com
2. **Locate Log Analytics Workspace**: Search for your workspace name
3. **Access Workspace Settings**:
   - Select **Settings** > **Agents management**
   - Copy the **Workspace ID**
   - Copy the **Primary Key**

```powershell
# Example configuration
$WorkspaceId = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
$PrimaryKey = "abcdefghijklmnopqrstuvwxyz1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ123456789012345678901234567890abcdefghijklmnopqrstuvwxyz=="
```

## Detailed Functionality Breakdown

### Core Functions

#### 1. Build-Signature Function
**Purpose**: Creates Azure Log Analytics authentication signature using HMAC-SHA256.

```powershell
Function Build-Signature ($workspaceId, $primaryKey, $date, $contentLength, $method, $contentType, $resource)
```

**Process**:
- Constructs string to hash from HTTP method, content details, and headers
- Generates HMAC-SHA256 hash using workspace primary key
- Returns SharedKey authorization header for Azure authentication

#### 2. Post-LogAnalyticsData Function
**Purpose**: Uploads JSON data to Azure Log Analytics workspace.

```powershell
Function Post-LogAnalyticsData($workspaceId, $primaryKey, $body, $logType)
```

**Process**:
- Builds authentication signature
- Constructs Azure Log Analytics REST API request
- Handles HTTP POST with proper headers and error handling
- Returns HTTP status code (200 = success)

#### 3. Collect-BrowserExtensions Function
**Purpose**: Main data collection function that scans all user profiles for browser extensions.

**Workflow**:
1. Enumerates user profiles using WMI (Win32_UserProfile)
2. Scans Chrome and Edge extension directories
3. Parses Firefox extensions.json files
4. Extracts extension metadata and user context
5. Returns structured extension inventory

## Data Collection Methodology

### User Profile Discovery
The script uses WMI to identify all user profiles on the system:

```powershell
$UserPaths = (Get-WmiObject win32_userprofile | Where-Object localpath -notmatch 'C:\\Windows').localpath
```

**Excluded Profiles**: System profiles under C:\Windows are automatically excluded.

### Chrome and Edge Extension Collection

**Extension Locations**:
- **Chrome**: `%USERPROFILE%\AppData\Local\Google\Chrome\User Data\[Profile]\Extensions\`
- **Edge**: `%USERPROFILE%\AppData\Local\Microsoft\Edge\User Data\[Profile]\Extensions\`

**Data Extraction Process**:
1. Scan for Default and Profile directories
2. Enumerate extension folders by ID
3. Read manifest.json files for metadata
4. Handle localized extension names from messages.json files
5. Extract version information and installation context

**Localization Handling**:
```powershell
# Handles internationalized extension names
if ($Manifest.name -like '__MSG*') {
    $AppId = ($Manifest.name -replace '__MSG_', '').Trim('_')
    # Check en_US and en locales for display names
}
```

### Firefox Extension Collection

**Extension Location**: `%USERPROFILE%\AppData\Roaming\Mozilla\Firefox\Profiles\[Profile]\extensions.json`

**Data Extraction Process**:
1. Locate Firefox profile directories
2. Parse extensions.json configuration file
3. Filter for active extensions (type="extension", active=true)
4. Extract addon metadata including names, IDs, and versions

### Data Structure

Each extension record contains the following fields:

```powershell
[PSCustomObject]@{
    TimeCollected = "2024-01-15 14:30:25"     # Collection timestamp
    DeviceName    = "WORKSTATION01"           # Computer name
    Browser       = "Google Chrome"           # Browser application
    BrowserID     = "Profile 1"               # Browser profile identifier
    Profile       = "Profile 1"               # User profile name
    ExtensionName = "uBlock Origin"           # Extension display name
    ExtensionID   = "cjpalhdlnbpafiamejdnhcphjbkeiagm" # Unique extension ID
    Version       = "1.48.4"                 # Extension version
    Username      = "jsmith"                  # Windows username
}
```

## Azure Log Analytics Integration

### Data Upload Process

1. **Collection**: Extensions are collected from all browsers and users
2. **Deduplication**: Removes duplicate entries based on device, profile, and extension ID
3. **JSON Serialization**: Converts data to JSON format for Log Analytics
4. **Authentication**: Generates HMAC-SHA256 signature for secure upload
5. **Upload**: Posts data via REST API to Azure Log Analytics

### Custom Log Table

Data is stored in a custom log table with the naming convention:
- **Table Name**: `[LogType]_CL` (e.g., `BrowserExtensionsInventory_CL`)
- **Retention**: Follows workspace retention policy
- **Schema**: Auto-generated based on uploaded JSON structure

### Query Examples

**Basic Extension Inventory**:
```kusto
BrowserExtensionsInventory_CL
| summarize count() by ExtensionName_s, Browser_s
| order by count_ desc
```

**Risk Assessment by Device**:
```kusto
BrowserExtensionsInventory_CL
| where ExtensionName_s contains "Remote" or ExtensionName_s contains "VPN"
| summarize Extensions = make_set(ExtensionName_s) by DeviceName_s, Username_s
```

**Extension Version Compliance**:
```kusto
BrowserExtensionsInventory_CL
| where ExtensionName_s == "Specific Extension Name"
| summarize Devices = count() by Version_s
| order by Devices desc
```

## Security Considerations

### Data Privacy
- **User Context**: Script accesses user profile directories but does not read personal browser data
- **Extension Metadata Only**: Collects only extension names, IDs, versions, and installation context
- **No Browsing History**: Does not access or collect web browsing history or personal data

### Network Security
- **HTTPS Transport**: All data transmitted to Azure using encrypted HTTPS
- **Authentication**: Secure HMAC-SHA256 signature-based authentication
- **Endpoint Security**: Connections only to official Azure Log Analytics endpoints

### Credential Management
**Best Practices**:
- Store workspace keys securely (Azure Key Vault, encrypted configuration)
- Use least-privilege service accounts for script execution
- Regularly rotate Log Analytics workspace keys
- Implement credential encryption for production deployments

**Example Secure Configuration**:
```powershell
# Production approach - retrieve from secure store
$WorkspaceId = Get-SecureString -Name "LogAnalyticsWorkspaceId"
$PrimaryKey = Get-SecureString -Name "LogAnalyticsPrimaryKey"
```

### Execution Security
- **Administrator Rights**: Requires elevated permissions to read all user profiles
- **Code Signing**: Consider signing scripts for production deployment
- **Execution Policy**: Ensure appropriate PowerShell execution policy

## Deployment and Usage

### Manual Execution

1. **Configure Parameters**: Update workspace ID and primary key in script
2. **Set Execution Policy** (if required):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```
3. **Run Script**:
   ```powershell
   .\Collect-BrowserExtentionsToLogAnalytics.ps1
   ```

### Scheduled Deployment

**Task Scheduler Configuration**:
```powershell
# Create scheduled task for weekly execution
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\Collect-BrowserExtentionsToLogAnalytics.ps1"
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 9AM
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "Browser Extensions Inventory" -Action $Action -Trigger $Trigger -Settings $Settings -User "SYSTEM"
```

### Group Policy Deployment

1. **Script Placement**: Deploy script to network share or local path
2. **GPO Configuration**: Create computer startup/shutdown script policy
3. **Security Context**: Ensure script runs with appropriate permissions

### Microsoft Intune Deployment

**PowerShell Script Policy**:
1. Navigate to **Devices** > **Scripts** > **PowerShell scripts**
2. Add new script with the following settings:
   - **Run this script using logged on credentials**: No
   - **Enforce script signature check**: Recommended
   - **Run script in 64-bit PowerShell**: Yes

## Troubleshooting Guide

### Common Issues and Solutions

#### Issue: "Access Denied" Errors
**Symptoms**: Script fails to read user profile directories
**Causes**:
- Insufficient permissions
- User profile encryption

**Solutions**:
```powershell
# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Script requires administrator privileges"
    exit 1
}
```

#### Issue: No Extensions Found
**Symptoms**: Script reports "No browser extensions found to upload"
**Causes**:
- No browsers installed
- No user profiles with extensions
- Path resolution issues

**Diagnostic Steps**:
```powershell
# Check browser installation paths
$EdgePath = "${env:LOCALAPPDATA}\Microsoft\Edge\User Data"
$ChromePath = "${env:LOCALAPPDATA}\Google\Chrome\User Data"
$FirefoxPath = "${env:APPDATA}\Mozilla\Firefox\Profiles"

Write-Output "Edge installed: $(Test-Path $EdgePath)"
Write-Output "Chrome installed: $(Test-Path $ChromePath)"
Write-Output "Firefox installed: $(Test-Path $FirefoxPath)"
```

#### Issue: Azure Upload Failures
**Symptoms**: HTTP errors or "Error uploading to Log Analytics"
**Causes**:
- Invalid workspace credentials
- Network connectivity issues
- Firewall blocking

**Diagnostic Commands**:
```powershell
# Test connectivity to Azure Log Analytics
$TestUri = "https://$WorkspaceId.ods.opinsights.azure.com"
Test-NetConnection -ComputerName "$WorkspaceId.ods.opinsights.azure.com" -Port 443

# Verify workspace ID format (should be GUID)
if ($WorkspaceId -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
    Write-Output "Workspace ID format is valid"
} else {
    Write-Warning "Invalid Workspace ID format"
}
```

#### Issue: JSON Parsing Errors
**Symptoms**: Errors reading manifest.json or extensions.json files
**Causes**:
- Corrupted browser files
- Invalid JSON syntax
- File locking issues

**Mitigation**:
```powershell
# Add error handling for JSON parsing
try {
    $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
} catch {
    Write-Warning "Failed to parse $ManifestPath : $($_.Exception.Message)"
    continue
}
```

### Performance Optimization

**For Large Environments**:
- Implement parallel processing for multiple user profiles
- Add progress indicators for long-running operations
- Consider batching uploads for systems with many extensions

```powershell
# Progress tracking example
$UserCount = $UserPaths.Count
$CurrentUser = 0
foreach ($Path in $UserPaths) {
    $CurrentUser++
    Write-Progress -Activity "Collecting Extensions" -Status "Processing user $CurrentUser of $UserCount" -PercentComplete (($CurrentUser / $UserCount) * 100)
    # Extension collection logic
}
```

### Logging and Monitoring

**Enhanced Logging Implementation**:
```powershell
# Add logging function
function Write-Log {
    param($Message, $Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    Write-Output $LogEntry
    Add-Content -Path "C:\Logs\BrowserExtensions.log" -Value $LogEntry
}

# Usage throughout script
Write-Log "Starting browser extension collection"
Write-Log "Found $($AllExtensions.Count) total extensions"
Write-Log "Uploaded $($UniqueExtensions.Count) unique extensions"
```

## Best Practices

### Deployment Best Practices

1. **Phased Rollout**: Deploy to pilot group before enterprise-wide deployment
2. **Testing**: Validate in test environment with various browser configurations
3. **Monitoring**: Implement alerting for failed uploads or collection errors
4. **Documentation**: Maintain deployment documentation and change management

### Security Best Practices

1. **Credential Security**:
   - Use Azure Key Vault for workspace credentials
   - Implement credential rotation procedures
   - Avoid hardcoding sensitive values

2. **Access Control**:
   - Limit script access to authorized administrators
   - Use dedicated service accounts with minimal permissions
   - Implement code signing for script integrity

3. **Network Security**:
   - Whitelist Azure Log Analytics endpoints in firewalls
   - Use corporate proxy configurations where required
   - Monitor network traffic for anomalies

### Operational Best Practices

1. **Scheduling**:
   - Run during low-impact hours (evenings/weekends)
   - Implement randomized execution to avoid thundering herd
   - Consider user logon triggers for real-time collection

2. **Data Management**:
   - Establish data retention policies in Log Analytics
   - Implement data archival for compliance requirements
   - Regular cleanup of obsolete extension records

3. **Monitoring and Alerting**:
   - Set up alerts for collection failures
   - Monitor extension trends and anomalies
   - Create dashboards for security team visibility

### Performance Best Practices

1. **Resource Management**:
   - Limit concurrent operations on systems with many users
   - Implement timeout handling for slow file operations
   - Monitor CPU and memory usage during execution

2. **Error Handling**:
   - Implement comprehensive try-catch blocks
   - Log errors with sufficient detail for troubleshooting
   - Continue processing on non-critical errors

3. **Optimization**:
   - Cache frequently accessed data
   - Use efficient PowerShell cmdlets and operators
   - Consider PowerShell Jobs for parallel processing

---

**Document Version**: 1.0
**Last Updated**: January 2025
**Author**: Technical Documentation Team
**Review Cycle**: Quarterly