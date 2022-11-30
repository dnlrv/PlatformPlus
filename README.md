# PlatformPlus
The intent is to add ease of use with certain queries when working directly with a Delinea PAS tenant once you are authenticated. This script provides new functions and classes to work with data within your PAS tenant.

## Installation

To install the script to your current working directory via the command line, run the following:
```
(Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/dnlrv/PlatformPlus/main/PlatformPlus.ps1').Content | Out-File .\PlatformPlus.ps1
```

## Running the script

If scripts are not allowed to be run in your environment, an alternative method is the run the following once the script is downloaded:

```
([ScriptBlock]::Create((Get-Content .\PlatformPlus.ps1 -Raw))).Invoke()
```

Alternatively, for a completely scriptless run, where the script's contents is retrieved from the internet, and immediately executed as a ScriptBlock object (basically combining the previous cmdlets):
```
([ScriptBlock]::Create(((Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/dnlrv/PlatformPlus/main/PlatformPlus.ps1').Content))).Invoke()
```

## Requirements

This script has only one requirement:
 - Authenticated to your PAS tenant via the Connect-DelineaPlatform cmdlet.
   - You can authenticated either interactively, using a bearer token, or secret. Only that the $PlatformConnection variable exists.

All results are based on your existing tenant permissions. If you are not getting expected results, ensure that your tenant permissions are accurate.

This script does not require privilege elevation to run.

## Major functions

Each major function also has Help documentation built into it. For example, use `help Get-PlatformSecret -Full` for more information about each function.

- Invoke-PlatformAPI - Allows a direct call to a named RestAPI endpoint with a JSON body payload.
- Query-VaultRedRock - Allows a direct SQL query to the Delinea Platform SQL tables.
- SetPlatformConnection - Allows changing existing connection to another Delinea Platform tenant.
  - This is only useful to customers that are working with two or more tenants.
- Search-PlatformDirectory - Allows you to search by name (like operator) for the UUID of a user, group, or Role known to the Delinea Platform.
- Get-PlatformAccount - Allows you to get an Account object from the Delinea Platform.
- Get-PlatformPrincipal - Allows you to get by name (exact match) for the UUID of a user, group, or Role known to the Delinea Platform.
- Get-PlatformSecret - Allows you to get a Secret object from the Delinea Platform.
- Get-PlatformSet - Allows you to get a Set object from the Delinea Platform.
- Get-PlatformVault - Allows you to get a Vault object from the Delinea Platform.
- Get-PlatformSystem - Allows you to get a System object from the Delinea Platform.
- Get-PlatformRole - Allows you to get a Role object from the Delinea Platform.
- Verify-PlatformCredentials - Verifies if the Account object (specified by UUID) has the correct credentials.
- Verify-PlatformConnection - verifies if you have a valid connection to a Delinea Platform tenant.
- Get-PlatformMetrics - Gets metrics and object count from the Delinea Platform tenant.
