#**************************** Log Analytics Workspace Info ****************************
$WorkspaceId = "" # Log Analytics Workspace ID (GUID)
$PrimaryKey = "" # Log Analytics Workspace Primary Key
$LogType = "DevicesBrowserExtensionsInventory" # Custom log name in Log Analytics
$TimeStampField = "" # Leave blank unless you want to specify a time field
#*************************************************************************************

Function Build-Signature ($workspaceId, $primaryKey, $date, $contentLength, $method, $contentType, $resource) {
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource
    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($primaryKey)
    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $workspaceId,$encodedHash
    return $authorization
}

Function Post-LogAnalyticsData($workspaceId, $primaryKey, $body, $logType) {
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -workspaceId $workspaceId `
        -primaryKey $primaryKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $workspaceId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"
    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }
    try {
        $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
        return $response.StatusCode
    } catch {
        Write-Output "Error uploading to Log Analytics: $_"
        return 0
    }
}

function Collect-BrowserExtensions {
    $Extensions = @()
    $UserPaths = (Get-WmiObject win32_userprofile | Where-Object localpath -notmatch 'C:\\Windows').localpath
    foreach ($Path in $UserPaths) {
        # Edge and Chrome
        $MSEdgeDir = $Path + '\AppData\Local\Microsoft\Edge\User Data'
        $GoogDir = $Path + '\AppData\Local\Google\Chrome\User Data'
        $CheckBrowserDir = New-Object Collections.Generic.List[string]
        if (Test-Path $MSEdgeDir) { $CheckBrowserDir.Add($MSEdgeDir) }
        if (Test-Path $GoogDir) { $CheckBrowserDir.Add($GoogDir) }
        foreach ($BrowserDir in $CheckBrowserDir) {
            $ProfilePaths = (Get-ChildItem -Path $BrowserDir | Where-Object Name -match 'Default|Profile').FullName
            foreach ($ProfilePath in $ProfilePaths) {
                $ExtPath = $ProfilePath + '\Extensions'
                if (Test-Path $ExtPath) {
                    $BrowserProfileName = ($ProfilePath | Split-Path -Leaf)
                    $Application = ($ProfilePath | Split-Path -Parent | Split-Path -Parent | Split-Path -Leaf)
                    $Username = ($ProfilePath | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent | Split-Path -Leaf)
                    $ExtFolders = Get-Childitem $ExtPath | Where-Object Name -ne 'Temp'
                    foreach ($Folder in $ExtFolders) {
                        $VerFolders = Get-Childitem $Folder.FullName
                        foreach ($Version in $VerFolders) {
                            if (Test-Path -Path ($Version.FullName + '\manifest.json')) {
                                $Manifest = Get-Content ($Version.FullName + '\manifest.json') -Encoding UTF8 | ConvertFrom-Json
                                $ExtName = $null # <-- Always reset for each extension
                                if ($Manifest.name -like '__MSG*') {
                                    $AppId = ($Manifest.name -replace '__MSG_', '').Trim('_')
                                    @('\_locales\en_US\', '\_locales\en\') | ForEach-Object {
                                        if (Test-Path -Path ($Version.Fullname + $_ + 'messages.json')) {
                                            $AppManifest = Get-Content ($Version.Fullname + $_ + 'messages.json') -Encoding UTF8 | ConvertFrom-Json
                                            @($AppManifest.appName.message, $AppManifest.extName.message,
                                                $AppManifest.extensionName.message, $AppManifest.app_name.message,
                                                $AppManifest.application_title.message, $AppManifest.$AppId.message) |
                                            ForEach-Object {
                                                if (($_) -and (-not($ExtName))) {
                                                    $ExtName = $_
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    $ExtName = $Manifest.name
                                }
                                if (-not $ExtName -or $ExtName -eq "") {
                                    $ExtName = $Folder.Name
                                }
                                $Extensions += [PSCustomObject]@{
                                    TimeCollected = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                                    DeviceName    = $env:COMPUTERNAME
                                    Browser       = $Application
                                    BrowserID     = $BrowserProfileName
                                    Profile       = $BrowserProfileName
                                    ExtensionName = $ExtName
                                    ExtensionID   = $Folder.Name
                                    Version       = $Manifest.version
                                    Username      = $Username
                                }
                            }
                        }
                    }
                }
            }
        }
        # Firefox
        $FirefoxProfilesDir = $Path + '\AppData\Roaming\Mozilla\Firefox\Profiles'
        if (Test-Path $FirefoxProfilesDir) {
            $FirefoxProfiles = Get-ChildItem -Path $FirefoxProfilesDir -Directory
            foreach ($FirefoxProfile in $FirefoxProfiles) {
                $ExtensionsJson = Join-Path $FirefoxProfile.FullName 'extensions.json'
                if (Test-Path $ExtensionsJson) {
                    try {
                        $ExtensionsData = Get-Content $ExtensionsJson -Raw -Encoding UTF8 | ConvertFrom-Json
                        foreach ($Addon in $ExtensionsData.addons) {
                            if ($Addon.type -eq "extension" -and $Addon.active -eq $true) {
                                $ExtName = $Addon.defaultLocale.name
                                if (-not $ExtName -or $ExtName -eq "") {
                                    $ExtName = $Addon.id
                                }
                                $Extensions += [PSCustomObject]@{
                                    TimeCollected = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                                    DeviceName    = $env:COMPUTERNAME
                                    Browser       = "Mozilla Firefox"
                                    BrowserID     = $FirefoxProfile.Name
                                    Profile       = $FirefoxProfile.Name
                                    ExtensionName = $ExtName
                                    ExtensionID   = $Addon.id
                                    Version       = $Addon.version
                                    Username      = ($Path | Split-Path -Leaf)
                                }
                            }
                        }
                    } catch {
                        Write-Output "Error reading $ExtensionsJson"
                    }
                }
            }
        }
    }
    return $Extensions
}

# Collect all extensions
$AllExtensions = Collect-BrowserExtensions

# Deduplicate
$UniqueExtensions = $AllExtensions | Sort-Object DeviceName,Profile,ExtensionID,ExtensionName -Unique

# Convert to JSON for Log Analytics
$ExtensionsJson = $UniqueExtensions | ConvertTo-Json

# Only send data if there are extensions found
if ($ExtensionsJson -and $ExtensionsJson -ne "[]") {
    $params = @{
        WorkspaceId = $WorkspaceId
        PrimaryKey  = $PrimaryKey
        Body        = ([System.Text.Encoding]::UTF8.GetBytes($ExtensionsJson))
        LogType     = $LogType
    }
    $LogResponse = Post-LogAnalyticsData @params
    Write-Output "Uploaded $($UniqueExtensions.Count) browser extensions to Azure Log Analytics. Status: $LogResponse"
    exit 0
} else {
    Write-Output "No browser extensions found to upload."
    exit 1
}