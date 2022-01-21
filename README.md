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

### Get-PlatformObjectUuid

This function enables you to retrieve the Uuid of a specified Platform object.

#### Syntax
```
PS:> Get-PlatformObjectUuid [-Type] <string> [-Name] <string> [<CommonParameters>]
```
 - Type - The type of the object. Currently only "Secret" and "Set" is supported.
   - for example: "Secret"
 - Name - The name of the object to get.

#### Example
```
PS:> Get-PlatformObjectUuid -Type Secret -Name FileSecret1
aaaaaaaa-0000-0000-0000-eeeeeeeeeeee
````

### Convert-PermissionToString

This function enables you to convert a permission-based Grant integer to a human-readable string.

#### Syntax
```
PS:> Convert-PermissionToString [-Type] <string> [-PermissionInt] <Int32> [<CommonParameters>]
```
 - Type - The type of the object. Currently only "Secret" is supported.
   - for example: "Secret"
 - PermissionInt - The Grant integer number to convert to human-readable format.

#### Example
```
PS:> Convert-PermissionToString -Type Secret -PermissionInt 65613
DeleteSecret|RetrieveSecret|EditSecret|ViewSecret|GrantSecret
````

### Get-PlatformRowAce

This function enables you to get all RowAces for a specified platform object.
It is advisable to convert this output to JSON before exporting to a file.

#### Syntax
```
PS:> Get-PlatformRowAce [-Type] <string> [-Name] <string> [<CommonParameters>]

OR

PS:> Get-PlatformSecret [-Type] <string> [-Uuid] <string>  [<CommonParameters>]
```
 - Type - The type of the object. Currently only "Secret" is supported.
   - for example: "Secret"
 - Name - The name of the object to get.
 - Uuid - The Uuid of the object to get.

#### Example
```
PS:> Get-PlatformRowAce -Type Secret -Name FileSecret1

PrincipalType      : User
PrincipalUuid      : aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
PrincipalName      : serviceuser@domain
AceID              : aaaaaaaa-aaaa-aaaa-bbbb-aaaaaaaaaaaa
PlatformPermission : PlatformPermission

PrincipalType      : User
PrincipalUuid      : cccccccc-cccc-cccc-cccc-cccccccccccc
PrincipalName      : cloudadmin@domain
AceID              : cccccccc-cccc-cccc-dddd-cccccccccccc
PlatformPermission : PlatformPermission
````

### Get-PlatformSecret

This function enables you to get a new PlatformSecret object from the tenant.

#### Syntax
```
PS:> Get-PlatformSecret [-Name] <string>  [<CommonParameters>]

OR 

PS:> Get-PlatformSecret [-Uuid] <string>  [<CommonParameters>]
```
 - Name - The name of the Secret to get.
   - for example: "TextSecret1"
 - Uuid - The Uuid of the Secret to get.
   - for example: "aaaaaaaa-0000-0000-0000-eeeeeeeeeeee"
     - this version would always return only one Secret.

#### Example
```
PS:> Get-PlatformSecret -Name TextSecret2

Name           : TextSecret2
Type           : Text
ParentPath     : .
Description    : Descript2
ID             : aaaaaaaa-0000-0000-0000-eeeeeeeeeeee
FolderId       :
whenCreated    : 2/11/2021 7:40:42 PM
whenModified   : 1/19/2022 6:16:43 PM
SecretText     :
SecretFileName :
SecretFileSize :
SecretFilePath :
RowAces        : {cloudadmin@domain}
```

#### Output

Get-PlatformSecret produces a new PlatformSecret object which has two relevant methods:

##### RetrieveSecret()

For Text Secrets, this will retrieve the contents of the Text Secret and store it in the SecretText member property.

For File Secrets, this will retrieve the special FileDownloadUrl needed to download the file and store that URL in the SecretFilePath member property.

##### ExportSecret()

For Text Secrets, this will export the contents of the SecretText member property into a .txt file with the same name as the Secret, in the directory that it exists currently according to the ParentPath.

For File Secrets, this will download the Secret File in the directory that it exists currently according to the ParentPath.

### Get-PlatformWorkflowApprover

This function enables you perform a search for Approver information based on name of user or name of role. Should be used in conjunction when working with Workflow gets/sets.

#### Syntax
```
PS:> Get-PlatformWorkflowApprover [-User] <string> [<CommonParameters>]

OR

PS:> Get-PlatformWorkflowApprover [-Role] <string>  [<CommonParameters>]
```
 - User - The name of the User to search.
   - for example: "cloudadmin@domain.com"
 - Role - The name of the Role to search.
   - for example: "Widget Owners"

#### Example
```
PS:> Get-PlatformWorkflowApprover -Role "System Administrator"

Name                 : System Administrator
Guid                 : sysadmin
_ID                  : sysadmin
Principal            : System Administrator
Description          : The primary administrative role for the Admin
                       Portal. Users in this role can delegate specific
                       administrative rights to other roles who require
                       more limited administrative access.
RoleType             : PrincipalList
ReadOnly             : False
DirectoryServiceUuid : AAAAAAAA-EEEE-EEEE-EEEE-EEEEEEEEEEEE
Type                 : Role
PType                : Role
ObjectType           : Role
OptionsSelector      : True
````

### Get-PlatformSecretWorkflowApprovers

This function enables you get all Workflow Approvers for a specified Secret. Returns $null if Workflow is not approved for this Secret.

#### Syntax
```
PS:> Get-PlatformSecretWorkflowApprovers [-Name] <string> [<CommonParameters>]

OR

PS:> Get-PlatformSecretWorkflowApprovers [-Uuid] <string>  [<CommonParameters>]
```
 - Name - The name of the Secret to get.
   - for example: "TextSecret1"
 - Uuid - The Uuid of the Secret to get.
   - for example: "aaaaaaaa-0000-0000-0000-eeeeeeeeeeee"
     - this version would always return only one Secret.

#### Example
```
PS:> Get-PlatformSecretWorkflowApprovers -Uuid "aaaaaaaa-0000-0000-0000-eeeeeeeeeeee"

isBackUp                 : False
NoManagerAction          :
DisplayName              : cloudadmin
ObjectType               : User
DistinguishedName        : cloudadmin@domain
DirectoryServiceUuid     : bbbbbbbb-cccc-cccc-cccc-eeeeeeeeeeee
SystemName               : cloudadmin@qtglab
ServiceInstance          : CDS
PType                    : User
Locked                   : False
InternalName             : cccccccc-dddd-dddd-dddd-dddddddddddd
StatusEnum               : Active
ServiceInstanceLocalized : Centrify Directory
ServiceType              : CDS
Type                     : User
Name                     : cloudadmin@domain
Email                    : user@domain.com
Status                   : Active
Enabled                  : True
Principal                : cloudadmin@domain
Guid                     : ffffffff-eeee-eeee-eeee-eeeeeeeeeeee
OptionsSelector          : True
RoleType                 :
_ID                      :
ReadOnly                 : False
Description              :
````