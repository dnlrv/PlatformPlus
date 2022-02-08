#######################################
#region ### FUNCTIONS #################
#######################################

###########
#region ### Check-Module # Checks for and imports the necessary PowerShell modules.
###########
function Check-Module
{
    Param
    (
        [Parameter(Position = 0, HelpMessage="The module to check.")]
        [System.String]$Module

    )# Param

    # if the module hasn't already been imported
    if (-Not (Get-Module).Name.Contains($Module))
    {
        # if the module is available
        if ((Get-Module -ListAvailable).Name.Contains($Module))
        {
            # try importing it
            Try
            {
                Import-Module -Name $Module -DisableNameChecking
            }
            Catch
            {
                Write-Error ("An error occurred while trying to import the {0} module. This is required. [{1}]" -f $Module, $_.Exception.Message)
                Write-Error ($_.Exception.Message)
                Exit 2 # EXITCODE 2 : Unknown error while importing required module.
            }
        }# if ((Get-Module -ListAvailable).Name.Contains($Module))
        else
        {
            Write-Error ("The required module [{0}] does not seemed to be installed." -f $Module)
            Exit 1 #  EXITCODE 1 : Required module not found.
        }
    }# if (-Not (Get-Module).Contains($Module))
}# function Check-Module
#endregion
###########

###########
#region ### global:Invoke-PlatformAPI # Invokes RestAPI using either the interactive session or the bearer token
###########
function global:Invoke-PlatformAPI
{
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "Specify the API call to make.")]
        [System.String]$APICall,

        [Parameter(Mandatory = $false, HelpMessage = "Specify the JSON Body payload.")]
        [System.String]$Body
    )

    # setting the url based on our PlatformConnection information
    $uri = ("https://{0}/{1}" -f $global:PlatformConnection.PodFqdn, $APICall)

    # Try
    Try
    {
        Write-Debug ("Uri=[{0}]" -f $uri)
        Write-Debug ("Body=[{0}]" -f $Body)

        # making the call using our a Splat version of our connection
        $Response = Invoke-RestMethod -Method Post -Uri $uri -Body $Body @global:SessionInformation

        # if the response was successful
        if ($Response.Success)
        {
            # return the results
            return $Response.Result
        }
        else
        {
            # otherwise throw what went wrong
            Throw $Response.Message
        }
    }# Try
    Catch
    {
        $LastError = [PlatformAPIException]::new("A PlatformAPI error has occured. Check `$LastError for more information")
        $LastError.APICall = $APICall
        $LastError.Payload = $Body
        $LastError.Response = $Response
        $LastError.ErrorMessage = $_.Exception.Message
        $global:LastError = $LastError
        Throw $_.Exception
    }
}# function global:Invoke-PlatformAPI 
#endregion
###########

###########
#region ### global:Query-VaultRedRock # Make an SQL RedRock query to the tenant
###########
function global:Query-VaultRedRock
{
    param
    (
		[Parameter(Mandatory = $true, HelpMessage = "The SQL query to make.")]
		[System.String]$SQLQuery
    )

    # Set Arguments
	$Arguments = @{}
	$Arguments.PageNumber 	= 1
	$Arguments.PageSize 	= 10000
	$Arguments.Limit	 	= 10000
	$Arguments.SortBy	 	= ""
	$Arguments.Direction 	= "False"
	$Arguments.Caching		= 0
	$Arguments.FilterQuery	= "null"

    # Build the JsonQuery string
	$JsonQuery = @{}
	$JsonQuery.Script 	= $SQLQuery
	$JsonQuery.Args 	= $Arguments

    # make the call, using whatever SQL statement was provided
    $RedRockResponse = Invoke-PlatformAPI -APICall RedRock/query -Body ($JsonQuery | ConvertTo-Json)
    
    # return the rows that were queried
    return $RedRockResponse.Results.Row
}# function global:Query-VaultRedRock
#endregion
###########

###########
#region ### global:Get-PlatformObjectUuid # Gets the Platform Uuid for the specified object
###########
function global:Get-PlatformObjectUuid
{
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The type of object to search.")]
        [System.String]$Type,

        [Parameter(Mandatory = $true, HelpMessage = "The name of the object to search.")]
        [System.String]$Name
    )

    # variables for the table, id, and name attributes
    [System.String]$tablename  = ""
    [System.String]$idname     = ""
    [System.String]$columnname = ""

    # switch to change the sqlquery based on the type of object
    switch ($Type)
    {
        "Secret" { $tablename = "DataVault"; $idname = "ID"; $columnname = "SecretName"; break }
        "Set"    { $tablename = "Sets"     ; $idname = "ID"; $columnname = "Name"      ; break }
        
    }

    # setting the SQL query string
    $sqlquery = ("SELECT {0}.{1} FROM {0} WHERE {0}.{2} = '{3}'" -f $tablename, $idname, $columnname, $Name)

    Write-Verbose ("SQLQuery: [{0}] " -f $sqlquery)

    # making the query
    $Uuid = Query-VaultRedRock -SqlQuery $sqlquery | Select-Object -ExpandProperty Id

    # warning if multiple Uuids are returned
    if ($uuid.Count -gt 1)
    {
        Write-Warning ("Multiple Uuids returned!")
    }

    # return $false if no Uuids were found
    if ($uuid.Count -eq 0)
    {
        Write-Warning ("No Uuids found!")
        return $false
    }

    # returning just the Uuid
    return $Uuid
}# global:Get-PlatformObjectUuid
#endregion
###########

###########
#region ### global:Convert-PermissionToString # Converts a Grant integer permissions number to readable permissions
###########
function global:Convert-PermissionToString
{
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The type of permission to convert.")]
        [System.String]$Type,

        [Parameter(Mandatory = $true, HelpMessage = "The Grant (int) number of the permissions to convert.")]
        [System.Int32]$PermissionInt
    )

    # setting our return value
    [System.String]$ReturnValue = ""

    # setting our readable permission hash based on our object type
    switch -Regex ($Type)
    {
        "Secret|DataVault" { $AceHash = @{ GrantSecret = 1; ViewSecret = 4; EditSecret  = 8; DeleteSecret = 64; RetrieveSecret = 65536} ; break }
        "Set"              { $AceHash = @{ GrantSet    = 1; ViewSet    = 4; EditSet     = 8; DeleteSet    = 64} ; break }
        "ManualBucket|SqlDynamic"    
                           { $AceHash = @{ GrantSet    = 1; ViewSet    = 4; EditSet     = 8; DeleteSet    = 64} ; break }
        "Phantom"          { $AceHash = @{ GrantFolder = 1; ViewFolder = 4; EditFolder  = 8; DeleteFolder = 64; AddFolder = 65536} ; break }
        "Server"           { $AceHash = @{ GrantServer = 1; ViewServer = 4; EditServer  = 8; DeleteServer = 64; AgentAuthServer = 65536; 
                                           ManageSessionServer = 128; RequestZoneRoleServer = 131072; AddAccountServer = 524288;
                                           UnlockAccountServer = 1048576; OfflineRescueServer = 2097152;  AddPrivilegeElevationServer = 4194304}; break }
        "Account|VaultAccount" 
                           { $AceHash = @{ GrantAccount = 1; ViewAccount = 4; EditAccount = 8; LoginAccount = 128; DeleteAccount = 64; CheckoutAccount = 65536; 
                                           UpdatePasswordAccount = 131072; WorkspaceLoginAccount = 262147; RotateAccount = 524288; FileTransferAccount = 1048576}; break }
        "Database|VaultDatabase"
                           { $AceHash = @{ GrantDatabaseAccount = 1; ViewDatabaseAccount = 4; EditDatabaseAccount = 8; DeleteDatabaseAccount = 64;
                                           CheckoutDatabaseAccount = 65536; UpdatePasswordDatabaseAccount = 131072; RotateDatabaseAccount = 524288}; break }
    }# switch -Regex ($Type)

    # for each bit (sorted) in our specified permission hash
    foreach ($bit in ($AceHash.GetEnumerator() | Sort-Object))
    {
        # if the bit seems to exist
        if (($PermissionInt -band $bit.Value) -ne 0)
        {
            # add the key to our return string
            $ReturnValue += $bit.Key + "|"
        }
    }# foreach ($bit in ($AceHash.GetEnumerator() | Sort-Object))

    # return the string, removing the trailing "|"
    return ($ReturnValue.TrimEnd("|"))
}# global:Convert-PermissionToString
#endregion
###########

###########
#region ### global:Get-PlatformRowAce # Gets RowAces for the specified platform object
###########
function global:Get-PlatformRowAce
{
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The type of object to search.")]
        [System.String]$Type,

        [Parameter(Mandatory = $true, HelpMessage = "The name of the object to search.", ParameterSetName = "Name")]
        [System.String]$Name,

        [Parameter(Mandatory = $true, HelpMessage = "The Uuid of the object to search.",ParameterSetName = "Uuid")]
        [System.String]$Uuid
    )

    # if the Name parameter was used
    if ($PSBoundParameters.ContainsKey("Name"))
    {
        # getting the uuid of the object
        $uuid = Get-PlatformObjectUuid -Type $Type -Name $Name
    }

    # setting the table variable
    [System.String]$table = ""

    Switch -Regex ($Type)
    {
        "Secret"    { $table = "DataVault"   ; break }
        "Set|Phantom|ManualBucket|SqlDynamic"
                    { $table = "Collections" ; break }
        default     { $table = $Type         ; break }
    }

    # preparing the JSONBody
    $JSONBody = @{ RowKey = $uuid ; Table = $table } | ConvertTo-Json

    # getting the RowAce information
    $RowAces = Invoke-PlatformAPI -APICall "Acl/GetRowAces" -Body $JSONBody

    # setting a new ArrayList for the return
    $RowAceObjects = New-Object System.Collections.ArrayList

    # for each rowace retrieved
    foreach ($rowace in $RowAces)
    {
        # ignore any global root entries
        if ($rowace.Type -eq "GlobalRoot" -or $rowace.PrincipalName -eq "Technical Support Access")
        {
            continue
        }

        # creating the PlatformPermission object
        $platformpermission = [PlatformPermission]::new($Type, $rowace.Grant, `
                              $rowace.GrantStr)

        # creating the PlatformRowAce object
        $obj = [PlatformRowAce]::new($rowace.PrincipalType, $rowace.Principal, `
               $rowace.PrincipalName, $rowace.AceID, $platformpermission)

        # adding the PlatformRowAce object to our ArrayList
        $RowAceObjects.Add($obj) | Out-Null
    }# foreach ($rowace in $RowAces)

    # returning the RowAceObjects
    return $RowAceObjects
}# function global:Get-PlatformRowAce
#endregion
###########

###########
#region ### global:Get-PlatformCollectionRowAce # Gets RowAces for the specified platform Collection object
###########
function global:Get-PlatformCollectionRowAce
{
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The type of object to search.")]
        [System.String]$Type,

        [Parameter(Mandatory = $true, HelpMessage = "The name of the object to search.", ParameterSetName = "Name")]
        [System.String]$Name,

        [Parameter(Mandatory = $true, HelpMessage = "The Uuid of the object to search.",ParameterSetName = "Uuid")]
        [System.String]$Uuid
    )

    # if the Name parameter was used
    if ($PSBoundParameters.ContainsKey("Name"))
    {
        $collectiontype = ""
        Switch -Regex ($Type)
        {
            "Secret|DataVault" { $collectiontype = "Set"; break }
        }

        # getting the uuid of the object
        $uuid = Get-PlatformObjectUuid -Type $collectiontype -Name $Name
    }

    # setting the table variable
    [System.String]$table = ""

    Switch ($Type)
    {
        "Secret"    { $table = "DataVault"   ; break }
        "Set"       { $table = "Collections" ; break }
        default     { $table = $Type         ; break }
    }

    # preparing the JSONBody
    $JSONBody = @{ RowKey = $uuid ; Table = $table } | ConvertTo-Json

    # getting the RowAce information
    $CollectionAces = Invoke-PlatformAPI -APICall "Acl/GetCollectionAces" -Body $JSONBody

    # setting a new ArrayList for the return
    $CollectionAceObjects = New-Object System.Collections.ArrayList

    # for each rowace retrieved
    foreach ($collectionace in $CollectionAces)
    {
        # ignore any global root entries
        if ($collectionace.Type -eq "GlobalRoot" -or $rowace.PrincipalName -eq "Technical Support Access")
        {
            continue
        }

        # creating the PlatformPermission object
        $platformpermission = [PlatformPermission]::new($Type, $collectionace.Grant, `
                              $collectionace.GrantStr)

        # creating the PlatformRowAce object
        $obj = [PlatformRowAce]::new($collectionace.PrincipalType, $collectionace.Principal, `
               $collectionace.PrincipalName, $collectionace.AceID, $platformpermission)

        # adding the PlatformRowAce object to our ArrayList
        $CollectionAceObjects.Add($obj) | Out-Null
    }# foreach ($collectionace in $CollectionAces)

    # returning the RowAceObjects
    return $CollectionAceObjects
}# function global:Get-PlatformCollectionRowAce
#endregion
###########

###########
#region ### global:Get-PlatformSecret # Gets a PlatformSecret object from the tenant
###########
function global:Get-PlatformSecret
{
    [CmdletBinding(DefaultParameterSetName="All")]
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The name of the secret to search.",ParameterSetName = "Name")]
        [System.String]$Name,

        [Parameter(Mandatory = $true, HelpMessage = "The Uuid of the secret to search.",ParameterSetName = "Uuid")]
        [System.String]$Uuid
    )

    # base query
    $query = "SELECT * FROM DataVault"

    # if the All set was not used
    if ($PSCmdlet.ParameterSetName -ne "All")
    {
        # arraylist for extra options
        $extras = New-Object System.Collections.ArrayList

        # appending the WHERE 
        $query += " WHERE "

        # setting up the extra conditionals
        if ($PSBoundParameters.ContainsKey("Name")) { $extras.Add(("SecretName = '{0}'" -f $Name)) | Out-Null }
        if ($PSBoundParameters.ContainsKey("Uuid")) { $extras.Add(("ID = '{0}'"         -f $Uuid)) | Out-Null }

        # join them together with " AND " and append it to the query
        $query += ($extras -join " AND ")
    }# if ($PSCmdlet.ParameterSetName -ne "All")

    Write-Verbose ("SQLQuery: [{0}]" -f $query)

    # make the query
    $sqlquery = Query-VaultRedRock -SqlQuery $query

    # new ArrayList to hold multiple entries
    $secrets = New-Object System.Collections.ArrayList

    # if the query isn't null
    if ($sqlquery -ne $null)
    {
        # for each secret in the query
        foreach ($secret in $sqlquery)
        {
            # Counter for the secret objects
            $p++; Write-Progress -Activity "Processing Secrets into Objects" -Status ("{0} out of {1} Complete" -f $p,$sqlquery.Count) -PercentComplete ($p/($sqlquery | Measure-Object | Select-Object -ExpandProperty Count)*100)
            
            # creating the PlatformSecret object
            $obj = [PlatformSecret]::new($secret)

            $secrets.Add($obj) | Out-Null
        }# foreach ($secret in $query)
    }# if ($sqlquery -ne $null)

    # returning the secrets
    return $secrets
}# lobal:Get-PlatformSecret
#endregion
###########

###########
#region ### global:Get-PlatformWorkflowApprover # Queries a user or role for their Workflow Approver format
###########
function global:Get-PlatformWorkflowApprover
{
    [CmdletBinding(DefaultParameterSetName="Role")]
    param
    (
		[Parameter(Mandatory = $true, HelpMessage = "The user to query.", ParameterSetName="User")]
		[System.String]$User,

        [Parameter(Mandatory = $true, HelpMessage = "The role to query.", ParameterSetName="Role")]
        [System.String]$Role

    )

    # User was selected
    if ($PSBoundParameters.ContainsKey("User"))
    {
        # prepare the SQL query
        $query = ('SELECT DsUsers.DirectoryServiceUuid, DsUsers.DisplayName, DsUsers.DistinguishedName, DsUsers.EMail, DsUsers.Enabled, DsUsers.InternalName, DsUsers.Locked, DsUsers.ObjectType, DsUsers.ObjectType AS Type, DsUsers.ServiceInstance, DsUsers.ServiceInstanceLocalized, DsUsers.ServiceType, DsUsers.Status, DsUsers.StatusEnum, DsUsers.SystemName, User.ID AS Guid, User.Username AS Name, User.Username AS Principal FROM DsUsers JOIN User ON DsUsers.InternalName = User.ID WHERE User.Username = "{0}"' -f $user)

        # make the SQL query
        $approver = Query-VaultRedRock -SQLQuery $query

        # adding a property of PType, setting it same as the ObjectType
        $approver | Add-Member -MemberType NoteProperty -Name PType -Value $sqlquery.ObjectType
    }# if ($PSBoundParameters.ContainsKey("User"))
    else # A role was queried
    {
        if ($role -eq "sysadmin" -or $role -eq "System Administrator")
        {
            # prepare the SQL query
            $query = ('SELECT Role.Description,Role.DirectoryServiceUuid,Role.ID AS _ID,Role.ID AS Guid,Role.Name,Role.Name AS Principal,Role.ReadOnly,Role.RoleType FROM Role WHERE Role.Name = "System Administrator"')
        }
        else
        {
            # prepare the SQL query
            $query = ('SELECT Role.Description,Role.DirectoryServiceUuid,Role.ID AS _ID,Role.ID AS Guid,Role.Name,Role.Name AS Principal,Role.ReadOnly,Role.RoleType FROM Role WHERE Role.Name = "{0}"' -f $role)
        }
       
        # make the SQL query
        $approver = Query-VaultRedRock -SQLQuery $query

        # adding relevant Workflow properties
        $approver | Add-Member -MemberType NoteProperty -Name Type       -Value "Role"
        $approver | Add-Member -MemberType NoteProperty -Name PType      -Value "Role"
        $approver | Add-Member -MemberType NoteProperty -Name ObjectType -Value "Role"

        # adding extra stuff if this is the sysadmin user
        if ($role -eq "sysadmin" -or $role -eq "System Administrator")
        {
            # prepare the SQL query
            $approver | Add-Member -MemberType NoteProperty -Name OptionsSelector -Value $true
        }# if ($role -eq "sysadmin" -or $role -eq "System Administrator")
    }# else # A role was queried

    return $approver
}# function global:Get-PlatformWorkflowApprover
#endregion
###########

###########
#region ### global:Get-PlatformSecretWorkflowApprovers # Gets all Workflow Approvers for a Secret
###########
function global:Get-PlatformSecretWorkflowApprovers
{
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The name of the secret to search.",ParameterSetName = "Name")]
        [System.String]$Name,

        [Parameter(Mandatory = $true, HelpMessage = "The Uuid of the secret to search.",ParameterSetName = "Uuid")]
        [System.String]$Uuid
    )

    # if the Name parameter was used
    if ($PSBoundParameters.ContainsKey("Name"))
    {
        # getting the uuid of the object
        $uuid = Get-PlatformObjectUuid -Type Secret -Name $Name
    }

    # new ArrayList for storing our special workflow approver objects
    $WorkflowApprovers = New-Object System.Collections.ArrayList

    # getting the original approvers by API call
    $approvers = Invoke-PlatformAPI -APICall ServerManage/GetSecretApprovers -Body (@{ ID = $uuid } | ConvertTo-Json)

    # for each approver found in the WorkflowApproversList
    foreach ($approver in $approvers.WorkflowApproversList)
    {        
        # if the approver contains the NoManagerAction AND the BackupApprover Properties
        if ((($approver | Get-Member -MemberType NoteProperty).Name).Contains("NoManagerAction") -and `
            (($approver | Get-Member -MemberType NoteProperty).Name).Contains("BackupApprover"))
        {
            # then this is a specified backup approver
            $backup = $approver.BackupApprover

            # search for that approver that is listed in the $approver.BackupApprover property
            if ($backup.ObjectType -eq "Role")
            {
                $approver = Get-PlatformWorkflowApprover -Role $backup.Name
            }
            else
            {
                $approver = Get-PlatformWorkflowApprover -User $backup.Name
            }
            
            # create our new PlatformWorkflowApprover object with the isBackup property set to true
            $obj = [PlatformWorkflowApprover]::new($approver, $true)
        }
        # otherwise if the NoManagerAction exists and it contains either "approve" or "deny"
        elseif (((($approver | Get-Member -MemberType NoteProperty).Name).Contains("NoManagerAction")) -and `
                ($approver.NoManagerAction -eq "approve" -or ($approver.NoManagerAction -eq "deny")))
        {
            # create our new PlatformWorkflowApprover object with the isBackup property set to true
            $obj = [PlatformWorkflowApprover]::new($approver, $true)
        }
        else # otherwise, it was a listed approver, and we can just
        {
            # create our new PlatformWorkflowApprover object with the isBackup property set to false
            $obj = [PlatformWorkflowApprover]::new($approver, $false)
        }

        # adding it to our ArrayList
        $WorkflowApprovers.Add($obj) | Out-Null
    }# foreach ($approver in $approvers.WorkflowApproversList)

    # returning the ArrayList
    return $WorkflowApprovers
}# function global:Get-PlatformSecretWorkflowApprovers
#endregion
###########

###########
#region ### global:Get-PlatformSet # Gets a Platform Set object
###########
function global:Get-PlatformSet
{
    [CmdletBinding(DefaultParameterSetName="All")]
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The type of Set to search.", ParameterSetName = "Type")]
        [System.String]$Type,

        [Parameter(Mandatory = $true, HelpMessage = "The name of the Set to search.", ParameterSetName = "Name")]
        [Parameter(Mandatory = $false, HelpMessage = "The name of the Set to search.", ParameterSetName = "Type")]
        [System.String]$Name,

        [Parameter(Mandatory = $true, HelpMessage = "The Uuid of the Set to search.",ParameterSetName = "Uuid")]
        [Parameter(Mandatory = $false, HelpMessage = "The name of the Set to search.", ParameterSetName = "Type")]
        [System.String]$Uuid
    )

    # setting the base query
    $query = "Select * FROM Sets"

    # arraylist for extra options
    $extras = New-Object System.Collections.ArrayList

    # if the All set was not used
    if ($PSCmdlet.ParameterSetName -ne "All")
    {
        # appending the WHERE 
        $query += " WHERE "

        # setting up the extra conditionals
        if ($PSBoundParameters.ContainsKey("Type")) { $extras.Add(("ObjectType = '{0}'" -f $Type)) | Out-Null }
        if ($PSBoundParameters.ContainsKey("Name")) { $extras.Add(("Name = '{0}'"       -f $Name)) | Out-Null }
        if ($PSBoundParameters.ContainsKey("Uuid")) { $extras.Add(("ID = '{0}'"         -f $Uuid)) | Out-Null }

        # join them together with " AND " and append it to the query
        $query += ($extras -join " AND ")
    }# if ($PSCmdlet.ParameterSetName -ne "All")

    Write-Verbose ("SQLQuery: [{0}]" -f $query)

    # making the query
    $sqlquery = Query-VaultRedRock -SQLQuery $query

    # ArrayList to hold objects
    $queries = New-Object System.Collections.ArrayList
    
    # if the query isn't null
    if ($sqlquery -ne $null)
    {
        foreach ($q in $sqlquery)
        {
            # Counter for the secret objects
            $p++; Write-Progress -Activity "Processing Sets into Objects" -Status ("{0} out of {1} Complete" -f $p,$sqlquery.Count) -PercentComplete ($p/($sqlquery | Measure-Object | Select-Object -ExpandProperty Count)*100)
            
            Write-Verbose ("Working with [{0}] Set [{1}]" -f $q.Name, $q.ObjectType)
            # create a new Platform Set object
            $set = [PlatformSet]::new($q)

            # if the Set is a Manual Set (not a Folder or Dynamic Set)
            if ($set.SetType -eq "ManualBucket")
            {
                # get the Uuids of the members
                $set.GetMembers()
            }

            # determin the potential owner of the Set
            $set.determineOwner()

            $queries.Add($set) | Out-Null
        }# foreach ($q in $query)
    }# if ($query -ne $null)
    else
    {
        return $false
    }
    
    #return $set
    return $queries
}# function global:Get-PlatformSet
#endregion
###########

###########
#region ### global:Verify-PlatformCredentials # Verifies the password is health for the specified account
###########
function global:Verify-PlatformCredentials
{
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The Uuid of the Account to check.",ParameterSetName = "Uuid")]
        [System.String]$Uuid
    )

    $response = Invoke-PlatformAPI -APICall ServerManage/CheckAccountHealth -Body (@{ ID = $Uuid } | ConvertTo-Json)

    if ($response -eq "OK")
    {
        [System.Boolean]$responseAnswer = $true
    }
    else
    {
        [System.Boolean]$responseAnswer = $false
    }
    
    return $responseAnswer
}# function global:Verify-PlatformCredentials
#endregion
###########

###########
#region ### global:TEMPLATE # TEMPLATE
###########
#function global:Invoke-TEMPLATE
#{
#}# function global:Invoke-TEMPLATE
#endregion
###########

#######################################
#endregion ############################
#######################################

#######################################
#region ### CLASSES ###################
#######################################

# class for holding Permission information including converting it to
# a human readable format
class PlatformPermission
{
    [System.String]$Type        # the type of permission (Secret, Account, etc.)
    [System.Int64]$GrantInt     # the Int-based number for the permission mask
    [System.String]$GrantBinary # the binary string of the the permission mask
    [System.String]$GrantString # the human readable permission mask

    PlatformPermission ([System.String]$t, [System.Int64]$gi, [System.String]$gb)
    {
        $this.Type        = $t
        $this.GrantInt    = $gi
        $this.GrantBinary = $gb
        $this.GrantString = Convert-PermissionToString -Type $t -PermissionInt $gi
    }# PlatformPermission ([System.String]$t, [System.Int64]$gi, [System.String]$gb)
}# class PlatformPermission

# class for holding RowAce information
class PlatformRowAce
{
    [System.String]$PrincipalType           # the principal type
    [System.String]$PrincipalUuid           # the uuid of the prinicpal
    [System.String]$PrincipalName           # the name of the principal
    [System.String]$AceID                   # the uuid of this RowAce
    [PlatformPermission]$PlatformPermission # the platformpermission object

    PlatformRowAce([System.String]$pt, [System.String]$puuid, [System.String]$pn, `
                   [System.String]$aid, [PlatformPermission]$pp)
    {
        $this.PrincipalType      = $pt
        $this.PrincipalUuid      = $puuid
        $this.PrincipalName      = $pn
        $this.AceId              = $aid
        $this.PlatformPermission = $pp
    }# PlatformRowAce([System.String]$pt, [System.String]$puuid, [System.String]$pn, `
}# class PlatformRowAce

# class for holding Secret information
class PlatformSecret
{
    [System.String]$Name                           # the name of the Secret
    [System.String]$Type                           # the type of Secret
    [System.String]$ParentPath                     # the Path of the Secret
    [System.String]$Description                    # the description 
    [System.String]$ID                             # the ID of the Secret
    [System.String]$FolderId                       # the FolderID of the Secret
    [System.DateTime]$whenCreated                  # when the Secret was created
    [System.DateTime]$whenModified                 # when the Secret was last modified
    [System.DateTime]$lastRetrieved                # when the Secret was last retrieved
    [System.String]$SecretText                     # (Text Secrets) The contents of the Text Secret
    [System.String]$SecretFileName                 # (File Secrets) The file name of the Secret
    [System.String]$SecretFileSize                 # (File Secrets) The file size of the Secret
    [System.String]$SecretFilePath                 # (File Secrets) The download FilePath for this Secret
    [PlatformRowAce[]]$RowAces                     # The RowAces (Permissions) of this Secret
    [PlatformWorkflowApprover[]]$WorkflowApprovers # the workflow approvers for this Secret

    PlatformSecret ($secretinfo)
    {
        $this.Name = $secretinfo.SecretName
        $this.Type = $secretinfo.Type
        $this.ParentPath = $secretinfo.ParentPath
        $this.Description = $secretinfo.Description
        $this.ID = $secretinfo.ID
        $this.FolderId = $secretinfo.FolderId
        $this.whenCreated = $secretinfo.whenCreated
        
        # if the secret has been updated
        if ($secretinfo.WhenContentsReplaced -ne $null)
        {
            # also update the whenModified property
            $this.whenModified = $secretinfo.WhenContentsReplaced
        }

        # getting when the secret was last accessed
        $lastquery = Query-VaultRedRock -SQLQuery ('SELECT DataVault.ID, DataVault.SecretName, Event.WhenOccurred FROM DataVault JOIN Event ON DataVault.ID = Event.DataVaultItemID WHERE (Event.EventType IN ("Cloud.Server.DataVault.DataVaultDownload") OR Event.EventType IN ("Cloud.Server.DataVault.DataVaultViewSecret"))  AND Event.WhenOccurred < Datefunc("now") AND DataVault.ID = "{0}" ORDER BY WhenOccurred DESC LIMIT 1'	-f $this.ID)

        if ($lastquery -ne $null)
        {
            $this.lastRetrieved = $lastquery.whenOccurred
        }

        # if the ParentPath is blank (root folder)
        if ([System.String]::IsNullOrEmpty($this.ParentPath))
        {
            $this.ParentPath = "."
        }

        # if this is a File secret, fill in the relevant file parts
        if ($this.Type -eq "File")
        {
            $this.SecretFileName = $secretinfo.SecretFileName
            $this.SecretFileSize = $secretinfo.SecretFileSize
        }

        # getting the RowAces for this secret
        $this.RowAces = Get-PlatformRowAce -Type Secret -Uuid $this.ID

        # getting the WorkflowApprovers for this secret
        $this.WorkflowApprovers = Get-PlatformSecretWorkflowApprovers -Uuid $this.ID
    }# PlatformSecret ($secretinfo)

    # method to retrieve secret content
    RetrieveSecret()
    {
        Switch ($this.Type)
        {
            "Text" # Text secrets will add the Secret Contets to the SecretText property
            {
                $this.SecretText = Invoke-PlatformAPI -APICall ServerManage/RetrieveSecretContents -Body (@{ ID = $this.ID } | ConvertTo-Json) `
                    | Select-Object -ExpandProperty SecretText
                break
            }
            "File" # File secrets will prepare the FileDownloadUrl for the Export
            {
                $this.SecretFilePath = Invoke-PlatformAPI -APICall ServerManage/RequestSecretDownloadUrl -Body (@{ secretID = $this.ID } | ConvertTo-Json) `
                    | Select-Object -ExpandProperty Location
                break
            }
        }# Switch ($this.Type)
    }# RetrieveSecret()

    # method to export secret content to files
    ExportSecret()
    {
        Switch ($this.Type)
        {
            "Text" # Text secrets will be created as a .txt file
            {
                $this.SecretText | Out-File -FilePath ("{0}\{1}.txt" -f $this.ParentPath, $this.Name)
                break
            }
            "File" # File secrets will be created as their current file name
            {
                Invoke-RestMethod -Method Get -Uri $this.SecretFilePath -OutFile ("{0}\{1}" -f $this.ParentPath, $this.SecretFileName) @global:SessionInformation
                break
            }
        }# Switch ($this.Type)
    }# ExportSecret()
}# class PlatformSecret

# class to hold Workflow Approvers
class PlatformWorkflowApprover
{
    [System.Boolean]$isBackUp
    [System.String]$NoManagerAction
    [System.String]$DisplayName
    [System.String]$ObjectType
    [System.String]$DistinguishedName
    [System.String]$DirectoryServiceUuid
    [System.String]$SystemName
    [System.String]$ServiceInstance
    [System.String]$PType
    [System.Boolean]$Locked
    [System.String]$InternalName
    [System.String]$StatusEnum
    [System.String]$ServiceInstanceLocalized
    [System.String]$ServiceType
    [System.String]$Type
    [System.String]$Name
    [System.String]$Email
    [System.String]$Status
    [System.Boolean]$Enabled
    [System.String]$Principal
    [System.String]$Guid
    [System.Boolean]$OptionsSelector # extra fields for default sysadmin role
    [System.String]$RoleType
    [System.String]$_ID
    [System.Boolean]$ReadOnly
    [System.String]$Description

    PlatformWorkflowApprover($approver, $isBackup)
    {
        # setting if this is a backup (Requestor's Manager option)
        $this.isBackUp = $isBackup

        # adding the properties that exist
        foreach ($property in (($approver | Get-Member -MemberType NoteProperty).Name | Where-Object {$_ -ne "Type-generated-field"}))
        {
            $this.$property = $approver.$property
        }
    }# PlatformWorkflowApprover($approver, $isBackup)
}# class PlatformWorkflowApprover

# class to hold Sets
class PlatformSet
{
    [System.String]$SetType
    [System.String]$ObjectType
    [System.String]$Name
    [System.String]$ID
    [System.String]$Description
    [System.DateTime]$whenCreated
    [PlatformRowAce[]]$PermissionRowAces             # permissions of the Set object itself
    [PlatformRowAce[]]$MemberPermissionRowAces       # permissions of the members for this Set object
    [System.Collections.ArrayList]$MembersUuid = @{} # the Uuids of the members
    [System.Collections.ArrayList]$SetMembers  = @{} # the members of this set
    [System.String]$PotentialOwner                   # a guess as to who possibly owns this set

    PlatformSet($set)
    {
        $this.SetType = $set.CollectionType
        $this.ObjectType = $set.ObjectType
        $this.Name = $set.Name
        $this.ID = $set.ID
        $this.Description = $set.Description

        if ($set.whenCreated -ne $null)
        {
            $this.whenCreated = $set.whenCreated
        }

        # getting the RowAces for this Set
        $this.PermissionRowAces = Get-PlatformRowAce -Type $this.SetType -Uuid $this.ID

        # if this isn't a Dynamic Set
        if ($this.SetType -ne "SqlDynamic")
        {
            # getting the RowAces for the member permissions
        $this.MemberPermissionRowAces = Get-PlatformCollectionRowAce -Type $this.ObjectType -Uuid $this.ID
        }
    }# PlatformSet($set)

    getMembers()
    {
        # getting the set members
        $m = Invoke-PlatformAPI -APICall Collection/GetMembers -Body (@{ID = $this.ID} | ConvertTo-Json)
        
        # if there are more than 0 members
        if ($m.Count -gt 0)
        {
            # Adding the Uuids to the Members property
            $this.MembersUuid.AddRange(($m | Select-Object -ExpandProperty Key))

            # for each item in the query
            foreach ($i in $m)
            {
                $obj = $null
                
                # getting the object based on the Uuid
                Switch ($i.Table)
                {
                    "DataVault"    {$obj = Query-VaultRedRock -SQLQuery ("SELECT ID AS Uuid,SecretName AS Name FROM DataVault WHERE ID = '{0}'" -f $i.Key); break }
                    "VaultAccount" {$obj = Query-VaultRedRock -SQLQuery ("SELECT ID As Uuid,(Name || '\' || User) AS Name FROM VaultAccount WHERE ID = '{0}'" -f $i.Key); break }
                }
                
                $this.SetMembers.Add(([SetMember]::new($obj.Name,$i.Table,$obj.Uuid))) | Out-Null
            }# foreach ($i in $m)
        }# if ($m.Count -gt 0)
    }# getMembers()

    # helps determine who might own this set
    determineOwner()
    {
        # get all RowAces where the PrincipalType is User and has all permissions on this Set object
        $owner = $this.PermissionRowAces | Where-Object {$_.PrincipalType -eq "User" -and ($_.PlatformPermission.GrantInt -eq 253 -or $_.PlatformPermission.GrantInt -eq 65789)}

        Switch ($owner.Count)
        {
            1       { $this.PotentialOwner = $owner.PrincipalName ; break }
            0       { $this.PotentialOwner = "No owners found"    ; break }
            default { $this.PotentialOwner = "Multiple potential owners found" ; break }
        }# Switch ($owner.Count)
    }# determineOwner()
}# class PlatformSet

# class to hold SetMembers
class SetMember
{
    [System.String]$Name
    [System.String]$Type
    [System.String]$Uuid

    SetMember([System.String]$n, [System.String]$t, [System.String]$u)
    {
        $this.Name = $n
        $this.Type = $t
        $this.Uuid = $u
    }
}# class SetMember

# class to hold Accounts
class PlatformAccount
{
    [System.String]$AccountType
    [System.String]$SourceName
    [System.String]$SourceID
    [System.String]$Name
    [System.String]$Username
    [System.Boolean]$isManaged
    [System.String]$Password
    [System.String]$Description
    [PlatformRowAce[]]$RowAces                     # The RowAces (Permissions) of this Account
    [PlatformWorkflowApprover[]]$WorkflowApprovers # the workflow approvers for this Account

    PlatformAccount($account)
    {
    }# PlatformAccount($account)

    getPassword()
    {
    }
}# class PlatformAccount

# class to hold a custom PlatformError
class PlatformAPIException : System.Exception
{
    [System.String]$APICall
    [System.String]$Payload
    [System.String]$ErrorMessage
    [PSCustomObject]$Response

    PlatformAPIException([System.String]$message) : base ($message) {}

    PlatformAPIException() {}
}
#######################################
#endregion ############################
#######################################

#######################################
#region ### PREPARE ###################
#######################################

# checking for required modules
Check-Module Centrify.Platform.PowerShell

# check if there is an existing $PlatformConnection from the Platform PowerShell module
if ($PlatformConnection -eq $null)
{
    Write-Host ("There is no existing `$PlatformConnection. Please use Connect-CentrifyPlatform to connect to your Centrify tenant. Exiting.")
    Exit 2 # EXITCODE 2 : No Platform Connection
}
else
{
    ## setting Splat information based on how the user is logged in
    # if the $PlatformConnection has an Authorization Key in the header, then it is an OAUTH2 confidential client user
    if ($PlatformConnection.Session.Headers.Keys.Contains("Authorization"))
    {
        $global:SessionInformation = @{ Headers = $PlatformConnection.Session.Headers }
    }
    else # otherwise it is an interactive user
    {
        $global:SessionInformation = @{ WebSession = $PlatformConnection.Session }
    }

}

#######################################
#endregion ############################
#######################################