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
    switch ($Type)
    {
        "Secret" { $AceHash = @{ GrantSecret = 1; ViewSecret = 4; EditSecret = 8; DeleteSecret= 64; RetrieveSecret = 65536} ; break }
    }

    # for each bit (sorted) in our specified permission hash
    foreach ($bit in ($AceHash.GetEnumerator() | Sort-Object))
    {
        # if the bit seems to exist
        if (($PermissionInt -band $bit.Value) -ne 0)
        {
            # add the key to our return string
            $ReturnValue += $bit.Key + "|"
        }
    }

    # return the string, removing the trailing "|"
    return ($ReturnValue.TrimEnd("|"))
}
#}# global:Convert-PermissionToString
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

        [Parameter(Mandatory = $true, HelpMessage = "The name of the object to search.")]
        [System.String]$Name
    )

    # getting the uuid of the object
    $uuid = Get-PlatformObjectUuid -Type $Type -Name $Name

    # setting the table variable
    [System.String]$table = ""

    Switch ($Type)
    {
        "Secret" { $table = "DataVault" ; break }
    }

    # preparing the JSONBody
    $JSONBody = @{ RowKey = $uuid ; Table = $table } | ConvertTo-Json

    # getting the RowAce information
    $RowAces = Invoke-PlatformAPI -APICall Acl/GetRowAces -Body $JSONBody

    # setting a new ArrayList for the return
    $RowAceObjects = New-Object System.Collections.ArrayList

    # for each rowace retrieved
    foreach ($rowace in $RowAces)
    {
        # ignore any global root entries
        if ($rowace.Type -eq "GlobalRoot")
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
    }
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
    }
}# PlatformRowAce

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
