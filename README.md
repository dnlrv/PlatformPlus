# PlatformPlus
The intent is to add ease of use with certain queries when working directly with a Delinea PAS tenant once you are authenticated. This script provides new functions and classes to work with data within your PAS tenant.

## Installation

To install the script via the command line, run the following:
```
(Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/dnlrv/PlatformPlus/main/PlatformPlus.ps1').Content | Out-File .\PlatformPlus.ps1
```

## Requirements

This script has only one requirement:
 - Authenticated to your PAS tenant via the Connect-DelineaPlatform cmdlet.
   - You can authenticated either interactively or using a bearer token, it does not matter. Only that the $PlatformConnection variable exists.

All results are based on your existing tenant permissions. If you are not getting expected results, ensure that your tenant permissions are accurate.

This script does not require privilege elevation to run.

## Usage

The following major functions are now available once this script is executed. A number of sub functions are also available, but they are primarily used to support the major functions and are not intended to be used directly.

### Verify-PlatformConnection

This function simply checks if you have an existing connection to a PAS tenant. Returns if $PlatformConnection is not null. Breaks with a message to the console if $PlatformConnection is null.

#### Syntax
```
PS:> Verify-PlatformConnection  [<CommonParameters>]
```
#### Example
```
PS:> Verify-PlatformConnection
````

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

### Get-PlatformSecret

This function enables you to get Secret objects from the PAS tenant. Using the function without any parameters will get all Secret objects in the PAS tenant.

#### Syntax
```
PS:> Get-PlatformSecret [-Name <string>] [-Uuid <string>] [<CommonParameters>]
```
 - Name - The name of the Secret object to get.
 - Uuid - The Uuid of the Secret object to get.

#### Example
```
PS:> Get-PlatformSecret -Name FileSecret1

Name              : FileSecret1
Type              : File
ParentPath        : .
Description       : This is the decsription
ID                : aaaaaaaa-aaaa-aaaa-aaaa-cccccccccccc
FolderId          :
whenCreated       : 2/11/2021 7:40:43 PM
whenModified      : 1/1/0001 12:00:00 AM
lastRetrieved     : 1/28/2022 1:37:05 PM
SecretText        :
SecretFileName    : config.txt
SecretFileSize    : 171 B
SecretFilePath    :
RowAces           : {serviceuser@domain.com, cloudadmin@domain.com,
                    dave.smith@domain.com, servicedesk@domain.com}
WorkflowEnabled   : True
WorkflowApprovers : {cloudadmin@domain.com, servicedesk@domain.com}
````

### Get-PlatformSet

This function enables you to get Set objects from the PAS tenant. Using the function without any parameters will get all Set objects in the PAS tenant.

These Set objects will also get basic information about the members of these Sets.

#### Syntax
```
PS:> Get-PlatformSet [-Type <string>] [-Name <string>] [-Uuid <string>]  [<CommonParameters>]
```
 - Type - The Type of the Set object to get.
  - Currently, only the following options are supported:
   - System - For System Sets.
   - Database - For Database Sets.
   - Account - For Account Sets.
   - Secret - For Secret Sets.
 - Name - The Name of the Set object to get.
 - Uuid - The Uuid of the Set object to get.
#### Example
```
PS:> Get-PlatformSet -Name "Williams Accounts"

SetType                 : ManualBucket
ObjectType              : VaultAccount
Name                    : Williams Accounts
ID                      : aaaaaaaa-aaaa-aaaa-aaaa-cccccccccccc
Description             :
whenCreated             : 2/7/2022 7:51:14 PM
PermissionRowAces       : {cloudadmin@domain.com}
MemberPermissionRowAces :
MembersUuid             : {51c08e41-a532-4501-a25a-9128f3458cfa,
                          f49d922d-e73b-4024-8ccf-354ad0cbfe87}
SetMembers              : {CENTOS701\root, CFYADMIN\Administrator}
PotentialOwner          : cloudadmin@domain.com
````

### Get-PlatformAccount

This function enables you to get Account objects from the PAS tenant. Using the function without any parameters will get all Account objects in the PAS tenant.

#### Syntax
```
PS:> Get-PlatformAccount [-Type <string>] [-SourceName <string>] [-UserName <string>] [-Uuid <string>]  [<CommonParameters>]
```
 - Type - The Type of the Account object to get.
  - Currently, only the following options are supported:
   - Local - For Local Accounts.
   - Domain - For Domain Accounts.
   - Database - For Database Accounts.
 - SourceName - The name of the parent object holding the account.
 - UserName - The user name of the Account.
 - Uuid - The Uuid of the Account object.
#### Example
```
PS:> Get-PlatformAccount -Type Domain -Username Administrator

AccountType       : Domain
SourceName        : domain.com
SourceID          : aaaaaaaa-aaaa-aaaa-aaaa-cccccccccccc
Username          : Administrator
ID                : aaaaaaaa-aaaa-aaaa-aaaa-dddddddddddd
isManaged         : False
Healthy           : OK
LastHealthCheck   : 1/11/2021 7:16:25 PM
Password          :
Description       :
PermissionRowAces : {cloudadmin@domain.com, Demo Role,
                    Everybody...}
WorkflowEnabled   : True
WorkflowApprovers : {servicedesk@domain.com, System Administrator}
````

### Verify-PlatformCredentials

This function enables you to Verify Account Credentials for a specified vaulted account. Returns TRUE if the credentials known by the PAS vault are correct. Returns FALSE if credentials are invalid, or a connection to verify could not be completed.

#### Syntax
```
PS:> Verify-PlatformCredentials [-Uuid <string>]  [<CommonParameters>]
```
 - Uuid - The Uuid of the Account object to check.
#### Example
```
PS:> Verify-PlatformCredentials -Uuid "aaaaaaaa-aaaa-aaaa-aaaa-cccccccccccc"
True
````