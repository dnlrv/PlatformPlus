# PlatformPlus
PlatformPlus is an enhancement script to the Centrify Platform PowerShell module (https://github.com/centrify/powershell-sdk).

The intent is to add ease of use with certain queries when working directly with a Centrify tenant once you are authenticated.

## Installation

To install the script via the command line, run the following:
```
(Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/dnlrv/PlatformPlus/main/PlatformPlus.ps1').Content | Out-File .\PlatformPlus.ps1
```

## Requirements

This script has a few requirements:
 - The Centrify Platform PowerShell module installed on your system. (https://github.com/centrify/powershell-sdk).
 - Authenticated to your Centrify tenant via the Connect-CentrifyPlatform cmdlet.
   - You can authenticated either interactively or using a bearer token, it does not matter. Only that the $PlatformConnection variable exists.

All results are based on your existing tenant permissions. If you are not getting expected results, ensure that your tenant permissions are accurate.

This script does not require privilege elevation to run.

## Usage

The following functions are now available once this script is executed:

### Invoke-PlatformAPI

This function enables you to make a basic RestAPI call with simple syntax. A JSON body can be provided for RestAPI calls that require it.

#### Syntax
```
PS:> Invoke-PlatformAPI [-APICall] <string> [[-Body] <string>] [<CommonParameters>]
```
 - APICall - The RestAPI call to make, remove the leading /.
   - for example: "Security/whoami"
 - Body - The JSON body payload. Must be in JSON format.

#### Example
```
PS:> Invoke-PlatformAPI -APICall Security/whoami

TenantId User              UserUuid
-------- ----              --------
AAA0000  user@domain       aaaaaaaa-0000-0000-0000-eeeeeeeeeeee
````

### Query-VaultRedrock

This function enables you to make a direct SQL query against the database.

#### Syntax
```
PS:> Query-VaultRedRock [-SQLQuery] <string>  [<CommonParameters>]
```
 - SQLQuery - The SQL query to make.
   - for example: "SELECT Name,ID FROM Server"

#### Example
```
PS:> Query-VaultRedRock -SQLQuery "SELECT Name,ID FROM Server"

Name                          ID
----                          --
MEMBER01.domain.com           aaaaaaaa-0000-0000-0000-eeeeeeeeeeee
CENTOS701                     aaaaaaaa-0000-0000-0000-ffffffffffff
CFYADMIN.domain.com           aaaaaaaa-0000-0000-0000-gggggggggggg
```
