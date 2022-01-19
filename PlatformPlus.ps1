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

    # warning if multiple Uuids are returned
    if ($uuid.Count -gt 1)
    {
        Write-Warning ("Multiple Uuids returned!")
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
#region ### global:Get-PlatformSecret # Gets a PlatformSecret object from the tenant
###########
function global:Get-PlatformSecret
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

    # getting the secret information
    $secretinfo = Query-VaultRedRock -SQLQuery ("SELECT * FROM DataVault WHERE ID = '{0}'" -f $uuid)

    # creating the PlatformSecret object
    $obj = [PlatformSecret]::new($secretinfo)

    # returning that object
    return $obj
}# lobal:Get-PlatformSecret
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
    [System.String]$Name            # the name of the Secret
    [System.String]$Type            # the type of Secret
    [System.String]$ParentPath      # the Path of the Secret
    [System.String]$Description     # the description 
    [System.String]$ID              # the ID of the Secret
    [System.String]$FolderId        # the FolderID of the Secret
    [System.DateTime]$whenCreated   # when the Secret was created
    [System.DateTime]$whenModified  # when the Secret was last modified
    [System.String]$SecretText      # (Text Secrets) The contents of the Text Secret
    [System.String]$SecretFileName  # (File Secrets) The file name of the Secret
    [System.String]$SecretFileSize  # (File Secrets) The file size of the Secret
    [System.String]$SecretFilePath  # (File Secrets) The download FilePath for this Secret
    [PlatformRowAce[]]$RowAces      # The RowAces (Permissions) of this Secret

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
