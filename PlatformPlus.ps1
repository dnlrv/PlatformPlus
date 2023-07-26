#######################################
#region ### MAJOR FUNCTIONS ###########
#######################################

###########
#region ### Verify-PlatformConnection # Check to ensure you are connected to the tenant before proceeding.
###########
function global:Verify-PlatformConnection
{
    <#
    .SYNOPSIS
    This function verifies you have an active connection to a Delinea Platform Tenant.

    .DESCRIPTION
    This function verifies you have an active connection to a Delinea Platform Tenant. It checks for the existance of a $PlatformConnection 
    variable to first check if a connection has been made, then it makes a Security/whoami RestAPI call to ensure the connection is active and valid.
    This function will store a date any only check if the last attempt was made more than 5 minutes ago. If the last verify attempt occured
    less than 5 minutes ago, the check is skipped and a valid connection is assumed. This is done to prevent an overbundence of whoami calls to the 
    Platform.

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function only throws an error if there is a problem with the connection.

    .EXAMPLE
    C:\PS> Verify-PlatformConnection
    This function will not return anything if there is a valid connection. It will throw an exception if there is no connection, or an 
    expired connection.
    #>

    if ($PlatformConnection -eq $null)
    {
        throw ("There is no existing `$PlatformConnection. Please use Connect-DelineaPlatform to connect to your Delinea tenant. Exiting.")
    }
    else
    {
        Try
        {
            # check to see if Lastwhoami is available
            if ($global:LastWhoamicheck)
            {
                # if it is, check to see if the current time is less than 5 minute from its previous whoami check
                if ($(Get-Date).AddMinutes(-5) -lt $global:LastWhoamicheck)
                {
                    # if it has been less than 5 minutes, assume we're still connected
                    return
                }
            }# if ($global:LastWhoamicheck)
            
            $uri = ("https://{0}/Security/whoami" -f $global:PlatformConnection.PodFqdn)

            # calling Security/whoami
            $WhoamiResponse = Invoke-RestMethod -Method Post -Uri $uri @global:SessionInformation
           
            # if the response was successful
            if ($WhoamiResponse.Success)
            {
                # setting the last whoami check to reduce frequent whoami calls
                $global:LastWhoamicheck = (Get-Date)
                return
            }
            else
            {
                throw ("There is no active, valid Tenant connection. Please use Connect-DelineaPlatform to re-connect to your Delinea tenant. Exiting.")
            }
        }# Try
        Catch
        {
            throw ("There is no active, valid Tenant connection. Please use Connect-DelineaPlatform to re-connect to your Delinea tenant. Exiting.")
        }
    }# else
}# function global:Verify-PlatformConnection
#endregion
###########

###########
#region ### global:Invoke-PlatformAPI # Invokes RestAPI using either the interactive session or the bearer token
###########
function global:Invoke-PlatformAPI
{
    <#
    .SYNOPSIS
    This function will provide an easy way to interact with any RestAPI endpoint in a Delinea PAS tenant.

    .DESCRIPTION
    This function will provide an easy way to interact with any RestAPI endpoint in a Delinea PAS tenant. This function requires an existing, valid $PlatformConnection
    to exist. At a minimum, the APICall parameter is required. 

    .PARAMETER APICall
    Specify the RestAPI endpoint to target. For example "Security/whoami" or "ServerManage/UpdateResource".

    .PARAMETER Body
    Specify the JSON body payload for the RestAPI endpoint.

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function outputs as PSCustomObject with the requested data if the RestAPI call was successful.

    .EXAMPLE
    C:\PS> Invoke-PlatfromAPI -APICall Security/whoami
    This will attempt to reach the Security/whoami RestAPI endpoint to the currently connected PAS tenant. If there is a valid connection, basic 
    information about the connected user will be returned as output.

    .EXAMPLE
    C:\PS> Invoke-PlatformAPI -APICall UserMgmt/ChangeUserAttributes -Body ( @{CmaRedirectedUserUuid=$normalid;ID=$adminid} | ConvertTo-Json)
    This will attempt to set MFA redirection on a user recognized by the PAS tenant. The body in this example is a PowerShell HastTable converted into a JSON block.
    The $normalid variable contains the UUID of the user to redirect to, and the $adminid is the UUID of the user who needs the redirect.

    .EXAMPLE
    C:\US> Invoke-PlatformAPI -APICall Collection/GetMembers -Body '{"ID":"aaaaaaaa-0000-0000-0000-eeeeeeeeeeee"}'
    This will attempt to get the members of a Set via that Set's UUID. In this example, the JSON Body payload is already in JSON format.
    #>
    param
    (
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Specify the API call to make.")]
        [System.String]$APICall,

        [Parameter(Position = 1, Mandatory = $false, HelpMessage = "Specify the JSON Body payload.")]
        [System.String]$Body
    )

    # verifying an active platform connection
    Verify-PlatformConnection

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
    <#
    .SYNOPSIS
    This function makes a direct SQL query to the SQL tables of the connected Delinea PAS tenant.

    .DESCRIPTION
    This function makes a direct SQL query to the SQL tables of the connected Delinea PAS tenant. Most SELECT SQL queries statements will work to query data.

    .PARAMETER SQLQuery
    The SQL Query to run. Most SELECT queries will work, as well as most JOIN, CASE, WHERE, AS, COUNT, etc statements.

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function outputs a PSCustomObject with the requested data.

    .EXAMPLE
    C:\PS> Query-VaultRedRock -SQLQuery "SELECT * FROM Sets"
    This query will return all rows and all property fields from the Sets table.

    .EXAMPLE
    C:\PS> Query-VaultRedRock -SQLQuery "SELECT COUNT(*) FROM Servers"
    This query will return a count of all the rows in the Servers table.

    .EXAMPLE
    C:\PS> Query-VaultRedRock -SQLQuery "SELECT Name,User AS AccountName FROM VaultAccount LIMIT 10"
    This query will return the Name property and the User property (renamed AS AccountName) from the VaultAccount table and limiting those results to 10 rows.
    #>
    param
    (
		[Parameter(Position = 0, Mandatory = $true, HelpMessage = "The SQL query to execute.")]
		[System.String]$SQLQuery
    )

    # verifying an active platform connection
    Verify-PlatformConnection

    # Set Arguments
	$Arguments = @{}
	#$Arguments.PageNumber 	= 1     
	#$Arguments.PageSize 	= 10000
	#$Arguments.Limit	 	= 10000 # removing this as it caps results to 10k
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
#region ### global:Set-PlatformConnection # Changes the PlatformConnection information to another connected tenant.
###########
function global:Set-PlatformConnection
{
    <#
    .SYNOPSIS
    This function will change the currently connected tenant to another actively connected tenant.

    .DESCRIPTION
    This function will change the currently connected tenant to another actively connected tenant. This function is only needed if you are working with two or
    more PAS tenants. For example, if you are working on mycompanydev.my.centrify.net and also on mycompanyprod.my.centrify.net, this function can help
    you switch connections between the two without having to reauthenticate to each one during the switch. Each connection must still initially be completed
    once via the Connect-DelineaPlatform function.

    .PARAMETER PodFqdn
    Specify the tenant's URL to switch to. For example, mycompany.my.centrify.net

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This script only returns $true on a successful switch, or $false if the specified PodFqdn was not found.

    .EXAMPLE
    C:\PS> Set-PlatformConnection -PodFqdn mycompanyprod.my.centrify.net
    This will switch your existing $PlatformConnection and $SessionInformation variables to the specified tenant. In this
    example, the login for mycopanyprod.my.centrify.net must have already been completed via the Connect-DelineaPlatform cmdlet.
    #>
    param
    (
		[Parameter(Position = 0, Mandatory = $true, HelpMessage = "The PodFqdn to switch to for authentication.")]
		[System.String]$PodFqdn
    )

    # if the $PlatformConnections contains the podFqdn in it's list
    if ($thisconnection = $global:PlatformConnections | Where-Object {$_.PodFqdn -eq $PodFqdn})
    {
        # change the PlatformConnection and SessionInformation to the requested tenant
        $global:SessionInformation = $thisconnection.SessionInformation
        $global:PlatformConnection = $thisconnection.PlatformConnection
        return $true
    }# if ($thisconnection = $global:PlatformConnections | Where-Object {$_.PodFqdn -eq $PodFqdn})
    else
    {
        return $false
    }
}# function global:Set-PlatformConnection
#endregion
###########

###########
#region ### global:Search-PlatformDirectory # Searches existing directories for principals or roles and returns the Name and ID by like searches
###########
function global:Search-PlatformDirectory
{
    <#
    .SYNOPSIS
    This function will retrieve the UUID of the specified principal from all reachable tenant directories.

    .DESCRIPTION
    This function will retrieve the UUID of the specified principal from all reachable tenant directories. The searches made
    by principal is a like search, so any matching query will be returned. For example, searching for -Role "System" will
    return any Role with "System" in the name.

    .PARAMETER User
    Search for a user by their User Principal Name. For example, "person@domain.com"

    .PARAMETER Group
    Search for a group by their Group and domain. For example, "WidgetAdmins@domain.com"

    .PARAMETER Role
    Search for a role by the Role name. For example, "System"

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function outputs a PSCustomObject with the Name of the principal and the UUID.

    .EXAMPLE
    C:\PS> Search-PlatformDirectory -User "person@domain.com"
    Searches all reachable tenant directories (AD, Federated, etc.) to find a person@domain.com and if successful, return the 
    tenant's UUID for this user.

    .EXAMPLE
    C:\PS> Search-PlatformDirectory -Group "WidgetAdmins@domain.com"
    Searches all reachable tenant directories (AD, Federated, etc.) to find the group WidgetAdmins@domain.com and if successful,
    return the tenant's UUID for this group.
    #>
    param
    (
		[Parameter(Mandatory = $true, HelpMessage = "Specify the User to find from DirectoryServices.",ParameterSetName = "User")]
		[System.Object]$User,

		[Parameter(Mandatory = $true, HelpMessage = "Specify the Group to find from DirectoryServices.",ParameterSetName = "Group")]
		[System.Object]$Group,

		[Parameter(Mandatory = $true, HelpMessage = "Specify the Role to find from DirectoryServices.",ParameterSetName = "Role")]
		[System.Object]$Role
    )

    # verifying an active platform connection
    Verify-PlatformConnection

    # building the query from parameter set
    Switch ($PSCmdlet.ParameterSetName)
    {
        "User"  { $query = ("SELECT InternalName AS ID,SystemName AS Name FROM DSUsers WHERE SystemName LIKE '%{0}%'" -f $User); break }
        "Role"  { $query = ("SELECT ID,Name FROM Role WHERE Name LIKE '%{0}%'" -f ($Role -replace "'","''")); break }
        "Group" { $query = ("SELECT InternalName AS ID,SystemName AS Name FROM DSGroups WHERE SystemName LIKE '%{0}%'" -f $Group); break }
    }

    Write-Verbose ("SQLQuery: [{0}]" -f $query)

    # make the query
    $sqlquery = Query-VaultRedRock -SqlQuery $query

    # new ArrayList to hold multiple entries
    $principals = New-Object System.Collections.ArrayList

    # if the query isn't null
    if ($sqlquery -ne $null)
    {
        # for each secret in the query
        foreach ($principal in $sqlquery)
        {
            # Counter for the principal objects
            $p++; Write-Progress -Activity "Processing Principals into Objects" -Status ("{0} out of {1} Complete" -f $p,$sqlquery.Count) -PercentComplete ($p/($sqlquery | Measure-Object | Select-Object -ExpandProperty Count)*100)
            
            # creating the PlatformPrincipal object
            $obj = [PlatformPrincipal]::new($principal.Name, $principal.ID)

            $principals.Add($obj) | Out-Null
        }# foreach ($principal in $sqlquery)
    }# if ($sqlquery -ne $null)

    return $principals
}# function global:Search-PlatformDirectory
#endregion
###########

###########
#region ### global:Get-PlatformPrincipal # Searches existing directories for principals or roles and returns the Name and ID by exact searches
###########
function global:Get-PlatformPrincipal
{
    <#
    .SYNOPSIS
    This function will retrieve the UUID of the specified principal from all reachable tenant directories by exact match.

    .DESCRIPTION
    This function will retrieve the UUID of the specified principal from all reachable tenant directories by exact match. This
    function will only principals that exactly match by name of what is searched, no partial searches.

    .PARAMETER User
    Search for a user by their User Principal Name. For example, "person@domain.com"

    .PARAMETER Group
    Search for a group by their Group and domain. For example, "WidgetAdmins@domain.com"

    .PARAMETER Role
    Search for a role by the Role name. For example, "System"

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function outputs a PSCustomObject with the requested data.

    .EXAMPLE
    C:\PS> Get-PlatformPrincipal -User "person@domain.com"
    Searches all reachable tenant directories (AD, Federated, etc.) to find a person@domain.com and if successful, return the 
    tenant's UUID for this user.

    .EXAMPLE
    C:\PS> Get-PlatformPrincipal -Group "WidgetAdmins@domain.com"
    Searches all reachable tenant directories (AD, Federated, etc.) to find the group WidgetAdmins@domain.com and if successful,
    return the tenant's UUID for this group.
    #>
    param
    (
		[Parameter(Mandatory = $true, HelpMessage = "Specify the User to find from DirectoryServices.",ParameterSetName = "User")]
		[System.Object]$User,

		[Parameter(Mandatory = $true, HelpMessage = "Specify the Group to find from DirectoryServices.",ParameterSetName = "Group")]
		[System.Object]$Group,

		[Parameter(Mandatory = $true, HelpMessage = "Specify the Role to find from DirectoryServices.",ParameterSetName = "Role")]
		[System.Object]$Role
    )

    # verifying an active platform connection
    Verify-PlatformConnection

    # building the query from parameter set
    Switch ($PSCmdlet.ParameterSetName)
    {
        "User"  { $query = ("SELECT InternalName AS ID,SystemName AS Name FROM DSUsers WHERE SystemName = '{0}'" -f $User); break }
        "Role"  { $query = ("SELECT ID,Name FROM Role WHERE Name = '{0}'" -f ($Role -replace "'","''")); break }
        "Group" { $query = ("SELECT InternalName AS ID,SystemName AS Name FROM DSGroups WHERE SystemName LIKE '%{0}%'" -f $Group); break }
    }

    Write-Verbose ("SQLQuery: [{0}]" -f $query)

    # make the query
    $sqlquery = Query-VaultRedRock -SqlQuery $query

    # new ArrayList to hold multiple entries
    $principals = New-Object System.Collections.ArrayList

    # if the query isn't null
    if ($sqlquery -ne $null)
    {
        # for each secret in the query
        foreach ($principal in $sqlquery)
        {
            # Counter for the principal objects
            $p++; Write-Progress -Activity "Processing Principals into Objects" -Status ("{0} out of {1} Complete" -f $p,$sqlquery.Count) -PercentComplete ($p/($sqlquery | Measure-Object | Select-Object -ExpandProperty Count)*100)
            
            # creating the PlatformPrincipal object
            $obj = [PlatformPrincipal]::new($principal.Name, $principal.ID)

            $principals.Add($obj) | Out-Null
        }# foreach ($principal in $sqlquery)
    }# if ($sqlquery -ne $null)

    return $principals
}# function global:Get-PlatformPrincipal
#endregion
###########

###########
#region ### global:Get-PlatformSecret # Gets a PlatformSecret object from the tenant
###########
function global:Get-PlatformSecret
{
    <#
    .SYNOPSIS
    Gets a Secret object from the Delinea Platform.

    .DESCRIPTION
    Gets a Secret object from the Delinea Platform. This returns a PlatformSecret class object containing properties about
    the Secret object, and methods to potentially retreive the Secret contents as well. By default, Get-PlatformSecret without
    any parameters will get all Secret objects in the Platform. 
    
    The additional methods are the following:

    .RetrieveSecret()
      - For Text Secrets, this will retreive the contents of the Text Secret and store it in the SecretText property.
      - For File Secrets, this will prepare the File Download URL to be used with the .ExportSecret() method.

    .ExportSecret()
      - For Text Secrets, this will export the contents of the SecretText property as a text file into the ParentPath directory.
      - For File Secrets, this will download the file from the Platform into the ParentPath directory.

    If the directory or file does not exist during ExportSecret(), the directory and file will be created. If the file
    already exists, then the file will be renamed and appended with a random 8 character string to avoid file name conflicts.
    
    .PARAMETER Name
    Get a Platform Secret by it's Secret Name.

    .PARAMETER Uuid
    Get a Platform Secret by it's UUID.

    .PARAMETER Type
    Get a Platform Secret by it's Type, either File or Text.

    .PARAMETER Limit
    Limits the number of potential Secret objects returned.

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function outputs a PlatformSecret class object.

    .EXAMPLE
    C:\PS> Get-PlatformSecret
    Gets all Secret objects from the Delinea Platform.

    .EXAMPLE
    C:\PS> Get-PlatformSecret -Limit 10
    Gets 10 Secret objects from the Delinea Platform.

    .EXAMPLE
    C:\PS> Get-PlatformSecret -Name "License Keys"
    Gets all Secret objects with the Secret Name "License Keys".

    .EXAMPLE
    C:\PS> Get-PlatformSecret -Type File
    Gets all File Secret objects.

    .EXAMPLE
    C:\PS> Get-PlatformSecret -Uuid "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    Get a Secret object with the specified UUID.
    #>
    [CmdletBinding(DefaultParameterSetName="All")]
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The name of the secret to search.",ParameterSetName = "Name")]
        [System.String]$Name,

        [Parameter(Mandatory = $true, HelpMessage = "The Uuid of the secret to search.",ParameterSetName = "Uuid")]
        [System.String]$Uuid,

        [Parameter(Mandatory = $true, HelpMessage = "The type of the secret to search.",ParameterSetName = "Type")]
        [ValidateSet("Text","File")]
        [System.String]$Type,

        [Parameter(Mandatory = $false, HelpMessage = "Limits the number of results.")]
        [System.Int32]$Limit
    )

    # verifying an active platform connection
    Verify-PlatformConnection

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
        if ($PSBoundParameters.ContainsKey("Type")) { $extras.ADD(("Type = '{0}'"       -f $Type)) | Out-Null }

        # join them together with " AND " and append it to the query
        $query += ($extras -join " AND ")
    }# if ($PSCmdlet.ParameterSetName -ne "All")

    # if Limit was used, append it to the query
    if ($PSBoundParameters.ContainsKey("Limit")) { $query += (" LIMIT {0}" -f $Limit) }

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
            if ($secret -eq $null) { continue }
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
#region ### global:Get-PlatformSet # Gets a Platform Set object
###########
function global:Get-PlatformSet
{
    <#
    .SYNOPSIS
    Gets a Set object from the Delinea Platform.

    .DESCRIPTION
    Gets a Set object from the Delinea Platform. This returns a PlatformSet class object containing properties about
    the Set object. By default, Get-PlatformSet without any parameters will get all Set objects in the Platform. 

    .PARAMETER Type
    Gets only Sets of this type. Currently only "System","Database","Account", or "Secret" is supported.

    .PARAMETER Name
    Gets only Sets with this name.

    .PARAMETER Uuid
    Gets only Sets with this UUID.

    .PARAMETER Limit
    Limits the number of potential Set objects returned.

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function outputs a PlatformSet class object.

    .EXAMPLE
    C:\PS> Get-PlatformSet
    Gets all Set objects from the Delinea Platform.

    .EXAMPLE
    C:\PS> Get-PlatformSet -Limit 10
    Gets 10 Set objects from the Delinea Platform.

    .EXAMPLE
    C:\PS> Get-PlatformSet -Name "Widget Systems"
    Gets all Secret objects with the Set Name "Widget Systems".

    .EXAMPLE
    C:\PS> Get-PlatformSet -Type "Account"
    Get all Account Sets from the Delinea Platform.

    .EXAMPLE
    C:\PS> Get-PlatformSecret -Uuid "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    Get a Secret object with the specified UUID.
    #>
    [CmdletBinding(DefaultParameterSetName="All")]
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The type of Set to search.", ParameterSetName = "Type")]
        [ValidateSet("System","Database","Account","Secret")]
        [System.String]$Type,

        [Parameter(Mandatory = $true, HelpMessage = "The name of the Set to search.", ParameterSetName = "Name")]
        [Parameter(Mandatory = $false, HelpMessage = "The name of the Set to search.", ParameterSetName = "Type")]
        [System.String]$Name,

        [Parameter(Mandatory = $true, HelpMessage = "The Uuid of the Set to search.",ParameterSetName = "Uuid")]
        [Parameter(Mandatory = $false, HelpMessage = "The name of the Set to search.", ParameterSetName = "Type")]
        [System.String]$Uuid,

        [Parameter(Mandatory = $false, HelpMessage = "Limits the number of results.")]
        [System.Int32]$Limit
    )

    # verifying an active platform connection
    Verify-PlatformConnection

    # setting the base query
    $query = "Select * FROM Sets"

    # arraylist for extra options
    $extras = New-Object System.Collections.ArrayList

    # if the All set was not used
    if ($PSCmdlet.ParameterSetName -ne "All")
    {
        # placeholder to translate type names
        [System.String] $newtype = $null

        # switch to translate backend naming convention
        Switch ($Type)
        {
            "System"   { $newtype = "Server" ; break }
            "Database" { $newtype = "VaultDatabase" ; break }
            "Account"  { $newtype = "VaultAccount" ; break }
            "Secret"   { $newtype = "DataVault" ; break }
            default    { }
        }# Switch ($Type)

        # appending the WHERE 
        $query += " WHERE "

        # setting up the extra conditionals
        if ($PSBoundParameters.ContainsKey("Type")) { $extras.Add(("ObjectType = '{0}'" -f $newtype)) | Out-Null }
        if ($PSBoundParameters.ContainsKey("Name")) { $extras.Add(("Name = '{0}'"       -f $Name))    | Out-Null }
        if ($PSBoundParameters.ContainsKey("Uuid")) { $extras.Add(("ID = '{0}'"         -f $Uuid))    | Out-Null }

        # join them together with " AND " and append it to the query
        $query += ($extras -join " AND ")
    }# if ($PSCmdlet.ParameterSetName -ne "All")

    # if Limit was used, append it to the query
    if ($PSBoundParameters.ContainsKey("Limit")) { $query += (" LIMIT {0}" -f $Limit) }

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

            # if the Set is a Manual Set or a Folder (not a Dynamic Set)
            if ($set.SetType -eq "ManualBucket" -or $set.SetType -eq "Phantom")
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
#region ### global:Get-PlatformAccount # Gets a Platform Account object
###########
function global:Get-PlatformAccount
{
    <#
    .SYNOPSIS
    Gets an Account object from the Delinea Platform.

    .DESCRIPTION
    Gets an Account object from the Delinea Platform. This returns a PlatformAccount class object containing properties about
    the Account object. By default, Get-PlatformAccount without any parameters will get all Account objects in the Platform. 
    In addition, the PlatformAccount class also contains methods to help interact with that Account.

    The additional methods are the following:

    .CheckInPassword()
      - Checks in a password that has been checked out by the CheckOutPassword() method.
    
    .CheckOutPassword()
      - Checks out the password to this Account.
    
    .ManageAccount()
      - Sets this Account to be managed by the Platform.

    .UnmanageAccount()
      - Sets this Account to be un-managed by the Platform.

    .UpdatePassword([System.String]$newpassword)
      - Updates the password to this Account.
    
    .VerifyPassword()
      - Verifies if this password on this Account is correct.

    .PARAMETER Type
    Gets only Accounts of this type. Currently only "Local","Domain","Database", or "Cloud" is supported.

    .PARAMETER SourceName
    Gets only Accounts with the name of the Parent object that hosts this account. For local accounts, this would
    be the hostname of the system the account exists on. For domain accounts, this is the name of the domain.

    .PARAMETER UserName
    Gets only Accounts with this as the username.

    .PARAMETER Uuid
    Gets only Accounts with this UUID.

    .PARAMETER Limit
    Limits the number of potential Account objects returned.

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function outputs a PlatformAccount class object.

    .EXAMPLE
    C:\PS> Get-PlatformAccount
    Gets all Account objects from the Delinea Platform.

    .EXAMPLE
    C:\PS> Get-PlatformAccount -Limit 10
    Gets 10 Account objects from the Delinea Platform.

    .EXAMPLE
    C:\PS> Get-PlatformAccount -Type Domain
    Get all domain-based Accounts.

    .EXAMPLE
    C:\PS> Get-PlatformAccount -Username "root"
    Gets all Account objects with the username, "root".

    .EXAMPLE
    C:\PS> Get-PlatformAccount -SourceName "LINUXSERVER01.DOMAIN.COM"
    Get all Account objects who's source (parent) object is LINUXSERVER01.DOMAIN.COM.

    .EXAMPLE
    C:\PS> Get-PlatformAccount -Uuid "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    Get an Account object with the specified UUID.
    #>
    [CmdletBinding(DefaultParameterSetName="All")]
    param
    (
        [Parameter(Mandatory = $false, HelpMessage = "The type of Account to search.", ParameterSetName = "Type")]
        [ValidateSet("Local","Domain","Database","Cloud")]
        [System.String]$Type,

        [Parameter(Mandatory = $false, HelpMessage = "The name of the Source of the Account to search.", ParameterSetName = "Source")]
        [System.String]$SourceName,

        [Parameter(Mandatory = $false, HelpMessage = "The name of the Account to search.", ParameterSetName = "UserName")]
        [System.String]$UserName,

        [Parameter(Mandatory = $false, HelpMessage = "The Uuid of the Account to search.",ParameterSetName = "Uuid")]
        [System.String]$Uuid,

        [Parameter(Mandatory = $false, HelpMessage = "A limit on number of objects to query.")]
        [System.Int32]$Limit
    )

    # verifying an active platform connection
    Verify-PlatformConnection

    # setting the base query
    $query = "Select * FROM VaultAccount"

    # arraylist for extra options
    $extras = New-Object System.Collections.ArrayList

    # if the All set was not used
    if ($PSCmdlet.ParameterSetName -ne "All")
    {
        # appending the WHERE 
        $query += " WHERE "

        # setting up the extra conditionals
        if ($PSBoundParameters.ContainsKey("Type"))
        {
            Switch ($Type)
            {
                "Cloud"    { $extras.Add("CloudProviderID IS NOT NULL") | Out-Null ; break }
                "Domain"   { $extras.Add("DomainID IS NOT NULL") | Out-Null ; break }
                "Database" { $extras.Add("DatabaseID IS NOT NULL") | Out-Null ; break }
                "Local"    { $extras.Add("Host IS NOT NULL") | Out-Null ; break }
            }
        }# if ($PSBoundParameters.ContainsKey("Type"))
        
        if ($PSBoundParameters.ContainsKey("SourceName")) { $extras.Add(("Name = '{0}'" -f $SourceName)) | Out-Null }
        if ($PSBoundParameters.ContainsKey("UserName"))   { $extras.Add(("User = '{0}'" -f $UserName))   | Out-Null }
        if ($PSBoundParameters.ContainsKey("Uuid"))       { $extras.Add(("ID = '{0}'"   -f $Uuid))       | Out-Null }

        # join them together with " AND " and append it to the query
        $query += ($extras -join " AND ")
    }# if ($PSCmdlet.ParameterSetName -ne "All")

    # if Limit was used, append it to the query
    if ($PSBoundParameters.ContainsKey("Limit")) { $query += (" LIMIT {0}" -f $Limit) }

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
            $p++; Write-Progress -Activity "Processing Accounts into Objects" -Status ("{0} out of {1} Complete" -f $p,$sqlquery.Count) -PercentComplete ($p/($sqlquery | Measure-Object | Select-Object -ExpandProperty Count)*100)
            
            Write-Verbose ("Working with Account [{0}\{1}]" -f $q.Name, $q.User)

            # minor placeholder to hold account type in case of all call
            [System.String]$accounttype = $null

            if ($q.CloudProviderID -ne $null) { $accounttype = "Cloud"    }
            if ($q.DomainID -ne $null)        { $accounttype = "Domain"   }
            if ($q.DatabaseID -ne $null)      { $accounttype = "Database" }
            if ($q.Host -ne $null)            { $accounttype = "Local"    }

            # create a new Platform Account object
            $account = [PlatformAccount]::new($q, $accounttype)

            $queries.Add($account) | Out-Null
        }# foreach ($q in $query)
    }# if ($query -ne $null)
    else
    {
        return $false
    }
    
    #return $queries
    return $queries
}# function global:Get-PlatformAccount
#endregion
###########

###########
#region ### global:Verify-PlatformCredentials # Verifies the password is health for the specified account
###########
function global:Verify-PlatformCredentials
{
    <#
    .SYNOPSIS
    Verifies an Account object's password as known by the Platform.

    .DESCRIPTION
    This function will verify if the specified account's password, as it is known by the Platform is correct.
    This will cause the Platform to reach out to the Account's parent object in an attempt to validate the password.
    Will return $true if it is correct, or $false if it is incorrect or cannot validate for any reason.

    .PARAMETER Uuid
    The Uuid of the Account to validate.

    .EXAMPLE
    C:\PS> Verify-PlatformCredentials -Uuid "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    Verifies the password of the Account with the spcified Uuid.
    #>
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The Uuid of the Account to check.",ParameterSetName = "Uuid")]
        [System.String]$Uuid
    )

    # verifying an active platform connection
    Verify-PlatformConnection

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
#region ### global:Get-PlatformVault # Gets a Platform Vault object
###########
function global:Get-PlatformVault
{
    <#
    .SYNOPSIS
    Gets a Vault object from the Delinea Platform.

    .DESCRIPTION
    Gets a Vault object from the Delinea Platform. This returns a PlatformVault class object containing properties about
    the Vault object. By default, Get-PlatformVault without any parameters will get all Vault objects in the Platform. 

    .PARAMETER Type
    Gets only Vaults of this type. Currently only "SecretServer" is supported.

    .PARAMETER VaultName
    Gets only Vaults with this name.

    .PARAMETER Uuid
    Gets only Vaults with this UUID.

    .PARAMETER Limit
    Limits the number of potential Vault objects returned.

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function outputs a PlatformVault class object.

    .EXAMPLE
    C:\PS> Get-PlatformVault
    Gets all Vault objects from the Delinea Platform.

    .EXAMPLE
    C:\PS> Get-PlatformVault -Limit 10
    Gets 10 Vault objects from the Delinea Platform.

    .EXAMPLE
    C:\PS> Get-PlatformVault -Name "Company SecretServer"
    Gets all Vault objects with the Name "Company SecretServer".

    .EXAMPLE
    C:\PS> Get-PlatformVault -Type "SecretServer"
    Get all Secret Server Vault objects from the Delinea Platform.

    .EXAMPLE
    C:\PS> Get-PlatformVault -Uuid "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    Get all Vault objects with the specified UUID.
    #>
    [CmdletBinding(DefaultParameterSetName="All")]
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The type of Vault to search.", ParameterSetName = "Type")]
        [ValidateSet("SecretServer")]
        [System.String]$Type,

        [Parameter(Mandatory = $true, HelpMessage = "The name of the Vault to search.", ParameterSetName = "Name")]
        [Parameter(Mandatory = $false, HelpMessage = "The name of the Vault to search.", ParameterSetName = "Type")]
        [System.String]$VaultName,

        [Parameter(Mandatory = $true, HelpMessage = "The Uuid of the Vault to search.",ParameterSetName = "Uuid")]
        [Parameter(Mandatory = $false, HelpMessage = "The name of the Vault to search.", ParameterSetName = "Type")]
        [System.String]$Uuid,

        [Parameter(Mandatory = $false, HelpMessage = "A limit on number of objects to query.")]
        [System.Int32]$Limit
    )

    # verifying an active platform connection
    Verify-PlatformConnection

    # setting the base query
    $query = "SELECT ID, Type as VaultType, Name as VaultName, Url, UserName, SyncInterval, LastSync FROM Vault"

    # arraylist for extra options
    $extras = New-Object System.Collections.ArrayList

    # if the All set was not used
    if ($PSCmdlet.ParameterSetName -ne "All")
    {
        # appending the WHERE 
        $query += " WHERE "

        # setting up the extra conditionals
        if ($PSBoundParameters.ContainsKey("Type"))
        {
            Switch ($Type) # Only one type for now, but more may show up in the future
            {
                "SecretServer" { $extras.Add(("Type = '{0}'" -f $Type)) | Out-Null ; break }
            }
        }# if ($PSBoundParameters.ContainsKey("Type"))
        
        if ($PSBoundParameters.ContainsKey("VaultName"))  { $extras.Add(("Name = '{0}'" -f $VaultName)) | Out-Null }
        if ($PSBoundParameters.ContainsKey("Uuid"))       { $extras.Add(("ID = '{0}'"   -f $Uuid))       | Out-Null }

        # join them together with " AND " and append it to the query
        $query += ($extras -join " AND ")
    }# if ($PSCmdlet.ParameterSetName -ne "All")

    # if Limit was used, append it to the query
    if ($PSBoundParameters.ContainsKey("Limit")) { $query += (" LIMIT {0}" -f $Limit) }

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
            Write-Verbose ("Working with Vault [{0}]" -f $q.VaultName )

            # create a new Platform Vault object
            $vault = [PlatformVault]::new($q)

            $queries.Add($vault) | Out-Null
        }# foreach ($q in $query)
    }# if ($query -ne $null)
    else
    {
        return $false
    }
    
    #return $queries
    return $queries
}# function global:Get-PlatformVault
#endregion
###########

###########
#region ### global:Get-PlatformSystem # Gets a Platform System object
###########
function global:Get-PlatformSystem
{
    <#
    .SYNOPSIS
    Gets a System object from the Delinea Platform.

    .DESCRIPTION
    Gets a System object from the Delinea Platform. This returns a PlatformSystem class object containing properties about
    the System object. By default, Get-PlatformSystem without any parameters will get all System objects in the Platform. 
    In addition, the PlatformSystem class also contains methods to help interact with that System.

    The additional methods are the following:

    .getAccounts()
      - Retrieves any local Account objects that are registered to this System.

    .PARAMETER Name
    Gets only Systems with this name.

    .PARAMETER FQDN
    Gets only Systems with this FQDN.

    .PARAMETER Uuid
    Gets only Systems with this UUID.

    .PARAMETER Limit
    Limits the number of potential Set objects returned.

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function outputs a PlatformSystem class object.

    .EXAMPLE
    C:\PS> Get-PlatformSystem
    Gets all System objects from the Delinea Platform.

    .EXAMPLE
    C:\PS> Get-PlatformSystem -Limit 10
    Gets 10 System objects from the Delinea Platform.

    .EXAMPLE
    C:\PS> Get-PlatformSystem -Name "CFYADMIN"
    Gets all System objects with the Name "CFYADMIN".

    .EXAMPLE
    C:\PS> Get-PlatformSystem -FQDN "LINUX01.DOMAIN.COM"
    Gets all System objects with the FQDN "LINUX01.DOMAIN.COM"

    .EXAMPLE
    C:\PS> Get-PlatformSystem -Uuid "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    Get a Secret object with the specified UUID.
    #>
    [CmdletBinding(DefaultParameterSetName="All")]
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The Hostname of the System to search.", ParameterSetName = "Name")]
        [System.String]$Name,

        [Parameter(Mandatory = $true, HelpMessage = "The FQDN of the System to search.", ParameterSetName = "FQDN")]
        [System.String]$FQDN,

        [Parameter(Mandatory = $true, HelpMessage = "The Uuid of the System to search.",ParameterSetName = "Uuid")]
        [System.String]$Uuid,

        [Parameter(Mandatory = $false, HelpMessage = "A limit on number of objects to query.")]
        [System.Int32]$Limit
    )

    # verifying an active platform connection
    Verify-PlatformConnection

    # setting the base query
    $query = "Select * FROM Server"

    # arraylist for extra options
    $extras = New-Object System.Collections.ArrayList

    # if the All set was not used
    if ($PSCmdlet.ParameterSetName -ne "All")
    {
        # appending the WHERE 
        $query += " WHERE "
        
        if ($PSBoundParameters.ContainsKey("Name")) { $extras.Add(("Name = '{0}'" -f $Name)) | Out-Null }
        if ($PSBoundParameters.ContainsKey("FQDN")) { $extras.Add(("FQDN = '{0}'" -f $FQDN)) | Out-Null }
        if ($PSBoundParameters.ContainsKey("Uuid")) { $extras.Add(("ID = '{0}'"   -f $Uuid)) | Out-Null }

        # join them together with " AND " and append it to the query
        $query += ($extras -join " AND ")
    }# if ($PSCmdlet.ParameterSetName -ne "All")

    # if Limit was used, append it to the query
    if ($PSBoundParameters.ContainsKey("Limit")) { $query += (" LIMIT {0}" -f $Limit) }

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
            $p++; Write-Progress -Activity "Processing Systems into Objects" -Status ("{0} out of {1} Complete" -f $p,$sqlquery.Count) -PercentComplete ($p/($sqlquery | Measure-Object | Select-Object -ExpandProperty Count)*100)
            
            Write-Verbose ("Working with System [{0}]" -f $q.Name)

            # create a new Platform System object
            $system = [PlatformSystem]::new($q)

            $queries.Add($system) | Out-Null
        }# foreach ($q in $query)
    }# if ($sqlquery -ne $null)
    else
    {
        return $false
    }
    
    #return $queries
    return $queries
}# function global:Get-PlatformSystem
#endregion
###########

###########
#region ### global:Get-PlatformRole # Gets Platform Role objects, along with the role's Members and Assigned Adminisrtative Rights
###########
function global:Get-PlatformRole
{
    <#
    .SYNOPSIS
    Gets a Role object from the Delinea Platform.

    .DESCRIPTION
    Gets a Role object from the Delinea Platform. This returns a PlatformRole class object containing properties about
    the Role object. By default, Get-PlatformRole without any parameters will get all Role objects in the Platform. 

    .PARAMETER Name
    Gets only Roles with this name.

    .PARAMETER Limit
    Limits the number of potential Role objects returned.

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function outputs a PlatformRole class object.

    .EXAMPLE
    C:\PS> Get-PlatformRole
    Gets all Role objects from the Delinea Platform.

    .EXAMPLE
    C:\PS> Get-PlatformRole -Limit 10
    Gets 10 Role objects from the Delinea Platform.

    .EXAMPLE
    C:\PS> Get-PlatformRole -Name "Infrastructure Team"
    Gets all Role objects with the Name "Infrastructure Team".
    #>
    [CmdletBinding(DefaultParameterSetName="All")]
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The Uuid of the Role to search.", ParameterSetName = "Name")]
        [System.String]$Name,

        [Parameter(Mandatory = $false, HelpMessage = "A limit on number of objects to query.")]
        [System.Int32]$Limit
    )

    # verify an active platform connection
    Verify-PlatformConnection

    # set the base query
    $query = "Select * FROM Role"

    # arraylist for extra options
    $extras = New-Object System.Collections.ArrayList

    # if the All set was not used
    if ($PSCmdlet.ParameterSetName -ne "All")
    {
        # appending the WHERE 
        $query += " WHERE "
        
        if ($PSBoundParameters.ContainsKey("Name")) { $extras.Add(("Name = '{0}'" -f $Name)) | Out-Null }
        # if ($PSBoundParameters.ContainsKey("SuppressPrincipalsList")) { $extras.Add(("SuppressPrincipalsList = '{0}'" -f $FQDN)) | Out-Null }

        # join them together with " AND " and append it to the query
        $query += ($extras -join " AND ")
    }# if ($PSCmdlet.ParameterSetName -ne "All")

    # if Limit was used, append it to the query
    if ($PSBoundParameters.ContainsKey("Limit")) { $query += (" LIMIT {0}" -f $Limit) }

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
            $p++; Write-Progress -Activity "Processing Roles into Objects" -Status ("{0} out of {1} Complete" -f $p,$sqlquery.Count) -PercentComplete ($p/($sqlquery | Measure-Object | Select-Object -ExpandProperty Count)*100)
            
            Write-Verbose ("Working with Role [{0}]" -f $q.Name)

            # create a new Platform System object
            $role = [PlatformRole]::new($q)

            $queries.Add($role) | Out-Null
        }# foreach ($q in $query)
    }# if ($sqlquery -ne $null)
    else
    {
        return $false
    }
    #return $queries
    return $queries
}# function global:Get-PlatformRole
#endregion
###########

###########
#region ### global:Get-PlatformMetrics # Gets counts of objects in the tenant
###########
function global:Get-PlatformMetrics
{
    # Sysinfo version
    Write-Host ("Getting Version metrics ... ") -NoNewline
    $Version = Invoke-PlatformAPI -APICall Sysinfo/Version
    Write-Host ("Done!") -ForegroundColor Green

    # Servers
    Write-Host ("Getting Server metrics ... ") -NoNewline
    $Servers = Query-VaultRedRock -SQLQuery "SELECT ComputerClass, ComputerClassDisplayName, FQDN, HealthStatus, HealthStatusError, ID, LastHealthCheck, LastState, Name, OperatingSystem FROM Server"
    Write-Host ("Done!") -ForegroundColor Green

    # Accounts
    Write-Host ("Getting Account metrics ... ") -NoNewline
    # This is written as it is because the parent object type was never contined in a single column
    $Accounts = Query-VaultRedRock -SQLQuery "SELECT (CASE WHEN DomainID != '' THEN DomainID WHEN Host != '' THEN Host WHEN DatabaseID != '' THEN DatabaseID WHEN DeviceID != '' THEN DeviceID WHEN KmipId != '' THEN KmipId WHEN VaultId != '' THEN VaultId WHEN VaultSecretId != '' THEN VaultSecretId ELSE 'Other' END) AS ParentID, (CASE WHEN DomainID != '' THEN 'DomainID' WHEN Host != '' THEN 'Host' WHEN DatabaseID != '' THEN 'DatabaseID' WHEN DeviceID != '' THEN 'DeviceID' WHEN KmipId != '' THEN 'KmipId' WHEN VaultId != '' THEN 'VaultId' WHEN VaultSecretId != '' THEN 'VaultSecretId' ELSE 'Other' END) AS ParentType,FQDN,HealthError,Healthy,ID,LastChange,LastHealthCheck,MissingPassword,Name,NeedsPasswordReset,User,UserDisplayName FROM VaultAccount"
    Write-Host ("Done!") -ForegroundColor Green

    # Secrets
    Write-Host ("Getting Secret metrics ... ") -NoNewline
    $Secrets = Query-VaultRedRock -SQLQuery "SELECT SecretFileName,WhenCreated,SecretFileSize,ID,ParentPath,FolderId,Description,SecretName,Type FROM DataVault"
    Write-Host ("Done!") -ForegroundColor Green

    # Sets
    Write-Host ("Getting Set metrics ... ") -NoNewline
    $Sets = Query-VaultRedRock -SQLQuery "SELECT ObjectType,Name,WhenCreated,ID,ParentPath,CollectionType,Description FROM Sets"
    Write-Host ("Done!") -ForegroundColor Green

    # Domains
    Write-Host ("Getting Domain metrics ... ") -NoNewline
    $Domains = Query-VaultRedRock -SQLQuery "SELECT ID,LastHealthCheck,LastState,Name FROM VaultDomain"
    Write-Host ("Done!") -ForegroundColor Green

    # Privilege Elevation Commands
    Write-Host ("Getting Privileged Elevation Command metrics ... ") -NoNewline
    $Commands = Query-VaultRedRock -SQLQuery "SELECT Name,DisplayName,ID,CommandPattern,RunAsUser,RunAsGroup,Description FROM PrivilegeElevationCommand"
    Write-Host ("Done!") -ForegroundColor Green

    # WebApps
    Write-Host ("Getting Applications metrics ... ") -NoNewline
    $Apps = Query-VaultRedRock -SQLQuery "SELECT Name,Category,DisplayName,ID,Description,AppType,State FROM Application"
    Write-Host ("Done!") -ForegroundColor Green

    # SSH Keys
    Write-Host ("Getting SSH Key metrics ... ") -NoNewline
    $SSHKeys = Query-VaultRedRock -SQLQuery "SELECT Comment,Created,CreatedBy,ID,IsManaged,LastUpdated,KeyType,Name,Revision,State FROM SSHKeys"
    Write-Host ("Done!") -ForegroundColor Green

    # CentrifyClients
    Write-Host ("Getting Centrify Client metrics ... ") -NoNewline
    $CentrifyClients = Query-VaultRedRock -SQLQuery "SELECT ID,JoinDate,LastUpdate,Name,ResourceID,ResourceName FROM CentrifyClients"
    Write-Host ("Done!") -ForegroundColor Green

    # Roles
    Write-Host ("Getting Role metrics ... ") -NoNewline
    $Roles = Query-VaultRedRock -SQLQuery "SELECT Name,ID,Description FROM Role"
    Write-Host ("Done!") -ForegroundColor Green

    # Connectors
    Write-Host ("Getting Connector metrics ... ") -NoNewline
    $Connectors = Query-VaultRedRock -SQLQuery "SELECT DnsHostName,LastPingAttempted,ID,Version FROM Proxy"
    Write-Host ("Done!") -ForegroundColor Green

    # CloudProviders TOADD

    # Policies TOADD

    # creating the PlatformData object
    $data = [PlatformData]::new($Servers,$Accounts,$Secrets,$Sets,$Domains,$Commands,$Apps,$CentrifyClients,$Roles,$Connectors)

    # creating the PlatformMetric object
    $metric = [PlatformMetric]::new($data,$Version)
    
    return $metric

}# function global:Get-PlatformMetrics
#endregion
###########

###########
#region ### global:New-MigrationReadyAccount # TEMPLATE
###########
function global:New-MigrationReadyAccount
{
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The PlatformAccount object to prepare for migration.")]
        [PSCustomObject[]]$PlatformAccount
    )

    $MigrationReadyAccounts = New-Object System.Collections.ArrayList

    foreach ($account in $PlatformAccount)
    {
        $obj = [MigrationReadyAccount]::new($account)
        $MigrationReadyAccounts.Add($obj) | Out-Null
    }# foreach ($account in $PlatformAccount)

    return $MigrationReadyAccounts
}# function global:New-MigrationReadyAccount
#endregion
###########

###########
#region ### global:ConvertFrom-JsonToPlatformSet # Converts stored json data back into a PlatformSet object with class methods
###########
function global:ConvertFrom-JsonToPlatformSet
{
    <#
    .SYNOPSIS
    Converts JSON-formatted PlatformSet data back into a PlatformSet object. Returns an ArrayList of PlatformSet class objects.

    .DESCRIPTION
    This function will take JSON data that was created from a PlatformSet class object, and recreate that PlatformSet
    class object that has all available methods for a PlatformSet object. This is returned as an ArrayList of PlatformSet
    class objects.

    .PARAMETER JSONSets
    Provides the JSON-formatted data for PlatformSets.

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function outputs an ArrayList of PlatformSet class objects.

    .EXAMPLE
    C:\PS> ConvertFrom-JsonToPlatformSet -JSONSets $JsonSets
    Converts JSON-formatted PlatformSet data into a PlatformSet class object.
    #>
    [CmdletBinding(DefaultParameterSetName="All")]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "The PlatformSet data to convert to a PlatformSet object.")]
        [PSCustomObject[]]$JSONSets
    )

    # a new ArrayList to return
    $NewPlatformSets = New-Object System.Collections.ArrayList

    # for each set object in our JSON data
    foreach ($platformset in $JSONSets)
    {
        # new empty PlatformSet object
        $obj = New-Object PlatformSet

        # copying information over
        $obj.SetType        = $platformset.SetType
        $obj.ObjectType     = $platformset.ObjectType
        $obj.Name           = $platformset.Name
        $obj.ID             = $platformset.ID
        $obj.whenCreated    = $platformset.whenCreated
        $obj.ParentPath     = $platformset.ParentPath
        $obj.PotentialOwner = $platformset.PotentialOwner

        # new ArrayList for the PermissionRowAces property
        $rowaces = New-Object System.Collections.ArrayList

        # for each PermissionRowAce in our PlatformSet object
        foreach ($permissionrowace in $platformset.PermissionRowAces)
        {
            # create a new PlatformRowAce object from that rowace data
            $pra = [PlatformRowAce]::new($permissionrowace)

            # add it to the PermissionRowAces ArrayList
            $rowaces.Add($pra) | Out-Null
        }# foreach ($permissionrowace in $platformset.PermissionRowAces)

        # add these permission row aces to our PlatformSet object
        $obj.PermissionRowAces = $rowaces

        # new ArrayList for the PermissionRowAces property
        $memberrowaces = New-Object System.Collections.ArrayList

        # for each MemberPermissionRowAce in our PlatformSet object
        foreach ($memberrowace in $platformset.MemberPermissionRowAces)
        {
            # create a new PlatformRowAce object from that rowace data
            $pra = [PlatformRowAce]::new($memberrowace)
            
            # add it to the MemberPermissionRowAces ArrayList
            $memberrowaces.Add($pra) | Out-Null
        }# foreach ($memberrowace in $platformset.MemberPermissionRowAces)

        # add these permission row aces to our PlatformSet object
        $obj.MemberPermissionRowAces = $memberrowaces

        # get the members of this Set
        $obj.getMembers()

        # add this object to our return ArrayList
        $NewPlatformSets.Add($obj) | Out-Null
    }# foreach ($platformset in $JSONSets)

    # return the ArrayList
    return $NewPlatformSets
}# function global:ConvertFrom-JsonToPlatformSet
#endregion
###########

###########
#region ### global:ConvertFrom-JsonToPlatformAccount # Converts stored json data back into a PlatformAccount object with class methods
###########
function global:ConvertFrom-JsonToPlatformAccount
{
    <#
    .SYNOPSIS
    Converts JSON-formatted PlatformAccount data back into a PlatformAccount object. Returns an ArrayList of PlatformAccount class objects.

    .DESCRIPTION
    This function will take JSON data that was created from a PlatformAccount class object, and recreate that PlatformAccount
    class object that has all available methods for a PlatformAccount object. This is returned as an ArrayList of PlatformAccount
    class objects.

    .PARAMETER JSONAccount
    Provides the JSON-formatted data for PlatformAccount.

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function outputs an ArrayList of PlatformAccount class objects.

    .EXAMPLE
    C:\PS> ConvertFrom-JsonToPlatformAccount -JSONAccounts $JsonAccounts
    Converts JSON-formatted PlatformAccount data into a PlatformAccount class object.
    #>
    [CmdletBinding(DefaultParameterSetName="All")]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "The PlatformAccount data to convert to a PlatformAccount object.")]
        [PSCustomObject[]]$JSONAccounts
    )

    # a new ArrayList to return
    $NewPlatformAccounts = New-Object System.Collections.ArrayList

    # for each set object in our JSON data
    foreach ($platformaccount in $JSONAccounts)
    {
        # new empty PlatformSet object
        $obj = New-Object PlatformAccount

        # copying information over
        $obj.AccountType     = $platformaccount.AccountType
        $obj.ComputerClass   = $platformaccount.ComputerClass
        $obj.SourceName      = $platformaccount.SourceName
        $obj.SourceType      = $platformaccount.SourceType
        $obj.SourceID        = $platformaccount.SourceID
        $obj.Username        = $platformaccount.Username
        $obj.ID              = $platformaccount.ID
        $obj.isManaged       = $platformaccount.isManaged
        $obj.Healthy         = $platformaccount.Healthy
        $obj.LastHealthCheck = $platformaccount.LastHealthCheck
        $obj.Password        = $platformaccount.Password
        $obj.Description     = $platformaccount.Description
        $obj.WorkflowEnabled = $platformaccount.WorkflowEnabled
        $obj.SSName          = $platformaccount.SSName
        $obj.LastCheckOut    = $platformaccount.LastCheckOut
        $obj.CheckOutID      = $platformaccount.CheckOutID

        # new PlatformVault object
        $vault = [PlatformVault]::new($platformaccount.Vault)

        # adding that to this object
        $obj.Vault = $vault

        # new ArrayList for the PermissionRowAces property
        $rowaces = New-Object System.Collections.ArrayList

        # for each PermissionRowAce in our PlatformAccount object
        foreach ($permissionrowace in $platformaccount.PermissionRowAces)
        {
            # create a new PlatformRowAce object from that rowace data
            $pra = [PlatformRowAce]::new($permissionrowace)

            # add it to the PermissionRowAces ArrayList
            $rowaces.Add($pra) | Out-Null
        }# foreach ($permissionrowace in $platformaccount.PermissionRowAces)

        # add these permission row aces to our PlatformAccount object
        $obj.PermissionRowAces = $rowaces

        # new ArrayList for the WorkflowApprovers property
        $approvers = New-Object System.Collections.ArrayList

        # for each approver in our PlatformAccount object
        foreach ($approver in $platformaccount.WorkflowApprovers)
        {
            $aprv = [PlatformWorkflowApprover]::new($approver, $approver.isBackUp)

            # add it to the approvers ArrayList
            $approvers.Add($aprv) | Out-Null
        }# foreach ($approver in $platformaccount.WorkflowApprovers)

        # add these approvers to our PlatformAccount object
        $obj.WorkflowApprovers = $approvers
        
        # add this object to our return ArrayList
        $NewPlatformAccounts.Add($obj) | Out-Null
    }# foreach ($platformaccount in $JSONAccounts)

    # return the ArrayList
    return $NewPlatformAccounts
}# function global:ConvertFrom-JsonToPlatformAccount
#endregion
###########

###########
#region ### global:ConvertFrom-JsonToMigratedCredential # Converts stored json data back into a MigratedCredential object with class methods
###########
function global:ConvertFrom-JsonToMigratedCredential
{
    <#
    .SYNOPSIS
    Converts JSON-formatted MigratedCredential data back into a MigratedCredential object. Returns an ArrayList of MigratedCredential class objects.

    .DESCRIPTION
    This function will take JSON data that was created from a MigratedCredential class object, and recreate that MigratedCredential
    class object that has all available methods for a MigratedCredential object. This is returned as an ArrayList of MigratedCredential
    class objects.

    .PARAMETER JSONMigratedCredentials
    Provides the JSON-formatted data for MigratedCredentials.

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function outputs an ArrayList of MigratedCredential class objects.

    .EXAMPLE
    C:\PS> ConvertFrom-JsonToMigratedCredential -JSONMigratedCredentials $JsonMigratedCredentials
    Converts JSON-formatted MigratedCredential data into a MigratedCredential class object.
    #>
    [CmdletBinding(DefaultParameterSetName="All")]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "The MigratedCredential data to convert to a MigratedCredential object.")]
        [PSCustomObject[]]$JSONMigratedCredentials
    )

    # a new ArrayList to return
    $NewMigratedCredentials = New-Object System.Collections.ArrayList

    # for each set object in our JSON data
    foreach ($jsonmc in $JSONMigratedCredentials)
    {
        # new empty PlatformSet object
        $obj = New-Object MigratedCredential

        # copying information over
        $obj.SecretTemplate    = $jsonmc.SecretTemplate
        $obj.SecretName        = $jsonmc.SecretName
        $obj.Target            = $jsonmc.Target
        $obj.Username          = $jsonmc.Username
        $obj.Password          = $jsonmc.Password
        $obj.Folder            = $jsonmc.Folder
        $obj.hasConflicts      = $jsonmc.hasConflicts
        $obj.PASDataType       = $jsonmc.PASDataType
        $obj.PASUUID           = $jsonmc.PASUUID

        # getting set information
        $obj.memberofSets      = ConvertFrom-JsonToPlatformSet -JSONSets $jsonmc.memberofSets

        # setting an array for the three permission classes
        $permissionproperties = "Permissions","SetPermissions","FolderPermissions"

        # for each of those permissions
        foreach ($permissionproperty in $permissionproperties)
        {
            # temporary ArrayList for 
            $Permissions = New-Object System.Collections.ArrayList

            # for each permission in that property
            foreach ($permission in $jsonmc.$permissionproperty)
            {
                # recreate the Permission class
                $perms = [Permission]::new($permission)

                # add it to our temp ArrayList
                $Permissions.Add($perms) | Out-Null
            }# foreach ($permission in $jsonmc.$permissionproperty)

            # add the temp ArrayList to our property
            $obj.$permissionproperty = $Permissions
        }# foreach ($permissionproperty in $permissionproperties)

        # adding remaining permissions
        $obj.Slugs          = $jsonmc.Slugs
        # TODO: recreate this properly.
        $obj.OriginalObject = $jsonmc.OriginalObject

        $NewMigratedCredentials.Add($obj) | Out-Null
    }# foreach ($jsonmc in $JSONMigratedCredentials)

    # return the ArrayList
    return $NewMigratedCredentials
}# function ConvertFrom-JsonToMigratedCredential
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
#region ### SUB FUNCTIONS #############
#######################################

###########
#region ### global:Are-SetMembersInOtherSets # Finds if a Set's members also appear in other Sets
###########
function global:Are-SetMembersInOtherSets
{
    param
    (
        [Parameter(Mandatory=$true, HelpMessage = "The Platform Set to check to see if all the members are unique.")]
        [PSObject]$Set,

        [Parameter(Mandatory=$false, HelpMessage = "Print where the duplicates exist.")]
        [Switch]$ShowMe
    )

    # if the Set has no members
    if ($Set.MembersUuid.Count -eq 0)
    {
        Write-Host ("Set has no members.")
        return $false
    }

    # nulling out any previous TenantSets
    $TenantSets = $null

    # get all sets with this set typ
    $TenantSets = Query-VaultRedRock -SQLQuery ("SELECT ID,Name AS SetName FROM Sets WHERE CollectionType = 'ManualBucket' AND ObjectType = '{0}'" -f $Set.ObjectType)

    # uuidbank for all uuids in all of these set types
    $UuidBank = New-Object System.Collections.ArrayList

    # for each set in all the sets with this set type
    foreach ($TenantSet in $TenantSets)
    {
        # get the members of this set
        $setmemberuuids = Invoke-PlatformAPI -APICall Collection/GetMembers -Body (@{ID=$TenantSet.ID}|ConvertTo-Json) | Select-Object -ExpandProperty Key

        # add the set members as a new property on this object
        $TenantSet | Add-Member -MemberType NoteProperty -Name SetMembers -Value $setmemberuuids

        # add all those uuids to our uuidbank
        $UuidBank.AddRange(@($setmemberuuids)) | Out-Null
    }
    
    # starting with a default of having no duplicates
    [System.Boolean]$hasDuplicates = $false

    # get all uuids that appear more than once in our uuidbank
    $2ormore = $UuidBank | Group-Object | Where-Object {$_.Count -gt 1}

    # for each set member in our original passed set
    foreach ($setmember in ($TenantSets | Where-Object {$_.ID -eq $Set.ID} | Select-Object -ExpandProperty SetMembers))
    {
        # if our 2ormore list contains that set member
        if ($2ormore.Name -contains $setmember)
        {
            # set hasDuplicates to true
            $hasDuplicates = $true
        }
    }# foreach ($setmember in ($TenantSets | Where-Object {$_.ID -eq $Set.ID} | Select-Object -ExpandProperty SetMembers))

    # if ShowMe is present and there are duplicates
    if ($ShowMe.IsPresent -and $hasDuplicates -eq $true)
    {
        Write-Host ("The Set [{0}] has the following member duplicates:" -f $Set.Name)

        # for each setmember in the set
        foreach ($setmember in $Set.SetMembers)
        {
            # if the uuid field is blank, skip it
            if ([System.String]::IsNullOrEmpty($setmember.Uuid))
            {
                continue
            }

            Write-Host ("- The member [{0}] also appears in the following Sets:" -f $setmember.Name)

            # show the sets where this member is also a member of other sets
            $AlsoAMemberOf = $TenantSets | Where-Object {$_.SetMembers -contains $setmember.Uuid}

            # display that information
            foreach ($memberset in $AlsoAMemberOf)
            {
                Write-host ("  - Set [{0}]" -f $memberset.SetName)
            }
        }# foreach ($setmember in $Set.SetMembers)
    }#if ($ShowMe.IsPresent -and $hasDuplicates -eq $true)
    elseif ($ShowMe.IsPresent)
    {
        Write-Host ("No duplicate membership was found.")
    }

    return $hasDuplicates
}# function global:Are-SetMembersInOtherSets
#endregion
###########

###########
#region ### global:Get-PlatformUniqueSets # TEMPLATE
###########
function global:Get-PlatformUniqueSets
{
    param
    (
        [Parameter(Mandatory=$true, HelpMessage = "The Platform Sets to check to see if all the members are unique.")]
        [PlatformSet[]]$Sets
    )

    $UniqueSets = New-Object System.Collections.ArrayList

    foreach ($set in $Sets)
    {
        # if the set has members in other sets, 
        if ((Are-SetMembersInOtherSets -Set $set) -eq $false)
        {
            $UniqueSets.Add($set) | Out-Null
        }
    }# foreach ($set in $Sets)

    return $UniqueSets
}# function global:Get-PlatformUniqueSets
#endregion
###########

###########
#region ### global:Get-PlatformBearerToken # Gets Platform Bearer Token information. Derived from Centrify.Platform.PowerShell.
###########
function global:Get-PlatformBearerToken
{
    param(
        [Parameter(Mandatory=$true, HelpMessage = "Specify the URL to connect to.")]
        [System.String]$Url,
        
        [Parameter(Mandatory=$true, HelpMessage = "Specify the OAuth2 Client name.")]
		[System.String]$Client,	

        [Parameter(Mandatory=$true, HelpMessage = "Specify the OAuth2 Scope name.")]
		[System.String]$Scope,	

        [Parameter(Mandatory=$true, HelpMessage = "Specify the OAuth2 Secret.")]
		[System.String]$Secret		
    )

    # Setup variable for connection
	$Uri = ("https://{0}/oauth2/token/{1}" -f $Url, $Client)
	$ContentType = "application/x-www-form-urlencoded" 
	$Header = @{ "X-CENTRIFY-NATIVE-CLIENT" = "True"; "Authorization" = ("Basic {0}" -f $Secret) }
	Write-Host ("Connecting to Delinea Platform (https://{0}) using OAuth2 Client Credentials flow" -f $Url)
			
    # Format body
    $Body = ("grant_type=client_credentials&scope={0}" -f  $Scope)
	
	# Debug informations
	Write-Debug ("Uri= {0}" -f $Uri)
	Write-Debug ("Header= {0}" -f $Header)
	Write-Debug ("Body= {0}" -f $Body)
    		
	# Connect using OAuth2 Client
	$WebResponse = Invoke-WebRequest -UseBasicParsing -Method Post -SessionVariable PASSession -Uri $Uri -Body $Body -ContentType $ContentType -Headers $Header
    $WebResponseResult = $WebResponse.Content | ConvertFrom-Json
    if ([System.String]::IsNullOrEmpty($WebResponseResult.access_token))
    {
        Throw "OAuth2 Client authentication error."
    }
	else
    {
        # Return Bearer Token from successfull login
        return $WebResponseResult.access_token
    }
}# function global:Get-PlatformBearerToken
#endregion
###########

###########
#region ### global:Connect-DelineaPlatform # Connects the user to a Delinea PAS tenant. Derived from Centrify.Platform.PowerShell.
###########
function global:Connect-DelineaPlatform
{
	param
	(
		[Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify the URL to use for the connection (e.g. oceanlab.my.centrify.com).")]
		[System.String]$Url,
		
		[Parameter(Mandatory = $true, ParameterSetName = "Interactive", HelpMessage = "Specify the User login to use for the connection (e.g. CloudAdmin@oceanlab.my.centrify.com).")]
		[System.String]$User,

		[Parameter(Mandatory = $true, ParameterSetName = "OAuth2", HelpMessage = "Specify the OAuth2 Client ID to use to obtain a Bearer Token.")]
        [System.String]$Client,

		[Parameter(Mandatory = $true, ParameterSetName = "OAuth2", HelpMessage = "Specify the OAuth2 Scope Name to claim a Bearer Token for.")]
        [System.String]$Scope,

		[Parameter(Mandatory = $true, ParameterSetName = "OAuth2", HelpMessage = "Specify the OAuth2 Secret to use for the ClientID.")]
        [System.String]$Secret,

        [Parameter(Mandatory = $false, ParameterSetName = "Base64", HelpMessage = "Encode Base64 Secret to use for OAuth2.")]
        [Switch]$EncodeSecret
	)
	
	# Debug preference
	if ($PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent)
	{
		# Debug continue without waiting for confirmation
		$DebugPreference = "Continue"
	}
	else 
	{
		# Debug message are turned off
		$DebugPreference = "SilentlyContinue"
	}
	
	try
	{	
		# Set Security Protocol for RestAPI (must use TLS 1.2)
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # Delete any existing connexion cache
        $Global:PlatformConnection = [Void]$null

        if ($EncodeSecret.IsPresent)
        {
             # Get Confidential Client name and password
             $Client = Read-Host "Confidential Client name"
             $SecureString = Read-Host "Password" -AsSecureString
             $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString))
             # Return Base64 encoded secret
             $AuthenticationString = ("{0}:{1}" -f $Client, $Password)
             return ("Secret: {0}" -f [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($AuthenticationString)))
        }

		if (-not [System.String]::IsNullOrEmpty($Client))
        {
            # Check if URL provided has "https://" in front, if so, remove it.
            if ($Url.ToLower().Substring(0,8) -eq "https://")
            {
                $Url = $Url.Substring(8)
            }
            
            # Get Bearer Token from OAuth2 Client App
			$BearerToken = Get-PlatformBearerToken -Url $Url -Client $Client -Secret $Secret -Scope $Scope

            # Validate Bearer Token and obtain Session details
            $Uri = ("https://{0}/Security/Whoami" -f $Url)
			$ContentType = "application/json" 
			$Header = @{ "X-CENTRIFY-NATIVE-CLIENT" = "1"; "Authorization" = ("Bearer {0}" -f $BearerToken) }
			Write-Debug ("Connecting to Delinea Platform (https://{0}) using Bearer Token" -f $Url)
			
			# Debug informations
			Write-Debug ("Uri= {0}" -f $Uri)
			Write-Debug ("BearerToken={0}" -f $BearerToken)
			
			# Format Json query
			$Json = @{} | ConvertTo-Json
			
			# Connect using Certificate
			$WebResponse = Invoke-WebRequest -UseBasicParsing -Method Post -SessionVariable PASSession -Uri $Uri -Body $Json -ContentType $ContentType -Headers $Header
            $WebResponseResult = $WebResponse.Content | ConvertFrom-Json
            if ($WebResponseResult.Success)
		    {
				# Get Connection details
				$Connection = $WebResponseResult.Result
				
				# Force URL into PodFqdn to retain URL when performing MachineCertificate authentication
				$Connection | Add-Member -MemberType NoteProperty -Name CustomerId -Value $Connection.TenantId
				$Connection | Add-Member -MemberType NoteProperty -Name PodFqdn -Value $Url
				
				# Add session to the Connection
				$Connection | Add-Member -MemberType NoteProperty -Name Session -Value $PASSession

				# Set Connection as global
				$Global:PlatformConnection = $Connection

                # setting the splat
                $global:SessionInformation = @{ Headers = $PlatformConnection.Session.Headers }

                # if the $PlatformConnections variable does not contain this Connection, add it
                if (-Not ($PlatformConnections | Where-Object {$_.PodFqdn -eq $Connection.PodFqdn}))
                {
                    # add a new PlatformConnection object and add it to our $PlatformConnectionsList
                    $obj = [PlatformConnection]::new($Connection.PodFqdn,$Connection,$global:SessionInformation)
                    $global:PlatformConnections.Add($obj) | Out-Null
                }
				
				# Return information values to confirm connection success
				return ($Connection | Select-Object -Property CustomerId, User, PodFqdn | Format-List)
            }
            else
            {
                Throw "Invalid Bearer Token."
            }
        }	
        else
		{
			# Check if URL provided has "https://" in front, if so, remove it.
            if ($Url.ToLower().Substring(0,8) -eq "https://")
            {
                $Url = $Url.Substring(8)
            }
            # Setup variable for interactive connection using MFA
			$Uri = ("https://{0}/Security/StartAuthentication" -f $Url)
			$ContentType = "application/json" 
			$Header = @{ "X-CENTRIFY-NATIVE-CLIENT" = "1" }
			Write-Host ("Connecting to Delinea Platform (https://{0}) as {1}`n" -f $Url, $User)
			
			# Debug informations
			Write-Debug ("Uri= {0}" -f $Uri)
			Write-Debug ("Login= {0}" -f $UserName)
			
			# Format Json query
			$Auth = @{}
			$Auth.TenantId = $Url.Split('.')[0]
			$Auth.User = $User
            $Auth.Version = "1.0"
			$Json = $Auth | ConvertTo-Json
			
			# Initiate connection
			$InitialResponse = Invoke-WebRequest -UseBasicParsing -Method Post -SessionVariable PASSession -Uri $Uri -Body $Json -ContentType $ContentType -Headers $Header

    		# Getting Authentication challenges from initial Response
            $InitialResponseResult = $InitialResponse.Content | ConvertFrom-Json
		    if ($InitialResponseResult.Success)
		    {
			    Write-Debug ("InitialResponse=`n{0}" -f $InitialResponseResult)
                # Go through all challenges
                foreach ($Challenge in $InitialResponseResult.Result.Challenges)
                {
                    # Go through all available mechanisms
                    if ($Challenge.Mechanisms.Count -gt 1)
                    {
                        Write-Host "`n[Available mechanisms]"
                        # More than one mechanism available
                        $MechanismIndex = 1
                        foreach ($Mechanism in $Challenge.Mechanisms)
                        {
                            # Show Mechanism
                            Write-Host ("{0} - {1}" -f $MechanismIndex++, $Mechanism.PromptSelectMech)
                        }
                        
                        # Prompt for Mechanism selection
                        $Selection = Read-Host -Prompt "Please select a mechanism [1]"
                        # Default selection
                        if ([System.String]::IsNullOrEmpty($Selection))
                        {
                            # Default selection is 1
                            $Selection = 1
                        }
                        # Validate selection
                        if ($Selection -gt $Challenge.Mechanisms.Count)
                        {
                            # Selection must be in range
                            Throw "Invalid selection. Authentication challenge aborted." 
                        }
                    }
                    elseif($Challenge.Mechanisms.Count -eq 1)
                    {
                        # Force selection to unique mechanism
                        $Selection = 1
                    }
                    else
                    {
                        # Unknown error
                        Throw "Invalid number of mechanisms received. Authentication challenge aborted."
                    }

                    # Select chosen Mechanism and prepare answer
                    $ChosenMechanism = $Challenge.Mechanisms[$Selection - 1]

			        # Format Json query
			        $Auth = @{}
			        $Auth.TenantId = $InitialResponseResult.Result.TenantId
			        $Auth.SessionId = $InitialResponseResult.Result.SessionId
                    $Auth.MechanismId = $ChosenMechanism.MechanismId
                    
                    # Decide for Prompt or Out-of-bounds Auth
                    switch($ChosenMechanism.AnswerType)
                    {
                        "Text" # Prompt User for answer
                        {
                            $Auth.Action = "Answer"
                            # Prompt for User answer using SecureString to mask typing
                            $SecureString = Read-Host $ChosenMechanism.PromptMechChosen -AsSecureString
                            $Auth.Answer = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString))
                        }
                        
                        "StartTextOob" # Out-of-bounds Authentication (User need to take action other than through typed answer)
                        {
                            $Auth.Action = "StartOOB"
                            # Notify User for further actions
                            Write-Host $ChosenMechanism.PromptMechChosen
                        }
                    }
	                $Json = $Auth | ConvertTo-Json
                    
                    # Send Challenge answer
			        $Uri = ("https://{0}/Security/AdvanceAuthentication" -f $Url)
			        $ContentType = "application/json" 
			        $Header = @{ "X-CENTRIFY-NATIVE-CLIENT" = "1" }
			
			        # Send answer
			        $WebResponse = Invoke-WebRequest -UseBasicParsing -Method Post -SessionVariable PASSession -Uri $Uri -Body $Json -ContentType $ContentType -Headers $Header
            		
                    # Get Response
                    $WebResponseResult = $WebResponse.Content | ConvertFrom-Json
                    if ($WebResponseResult.Success)
		            {
                        # Evaluate Summary response
                        if($WebResponseResult.Result.Summary -eq "OobPending")
                        {
                            $Answer = Read-Host "Enter code or press <enter> to finish authentication"
                            # Send Poll message to Delinea Identity Platform after pressing enter key
			                $Uri = ("https://{0}/Security/AdvanceAuthentication" -f $Url)
			                $ContentType = "application/json" 
			                $Header = @{ "X-CENTRIFY-NATIVE-CLIENT" = "1" }
			
			                # Format Json query
			                $Auth = @{}
			                $Auth.TenantId = $Url.Split('.')[0]
			                $Auth.SessionId = $InitialResponseResult.Result.SessionId
                            $Auth.MechanismId = $ChosenMechanism.MechanismId
                            
                            # Either send entered code or poll service for answer
                            if ([System.String]::IsNullOrEmpty($Answer))
                            {
                                $Auth.Action = "Poll"
                            }
                            else
                            {
                                $Auth.Action = "Answer"
                                $Auth.Answer = $Answer
                            }
			                $Json = $Auth | ConvertTo-Json
			
                            # Send Poll message or Answer
			                $WebResponse = Invoke-WebRequest -UseBasicParsing -Method Post -SessionVariable PASSession -Uri $Uri -Body $Json -ContentType $ContentType -Headers $Header
                            $WebResponseResult = $WebResponse.Content | ConvertFrom-Json
                            if ($WebResponseResult.Result.Summary -ne "LoginSuccess")
                            {
                                Throw "Failed to receive challenge answer or answer is incorrect. Authentication challenge aborted."
                            }
                        }

                        # If summary return LoginSuccess at any step, we can proceed with session
                        if ($WebResponseResult.Result.Summary -eq "LoginSuccess")
		                {
                            # Get Session Token from successfull login
			                Write-Debug ("WebResponse=`n{0}" -f $WebResponseResult)
			                # Validate that a valid .ASPXAUTH cookie has been returned for the PASConnection
			                $CookieUri = ("https://{0}" -f $Url)
			                $ASPXAuth = $PASSession.Cookies.GetCookies($CookieUri) | Where-Object { $_.Name -eq ".ASPXAUTH" }
			
			                if ([System.String]::IsNullOrEmpty($ASPXAuth))
			                {
				                # .ASPXAuth cookie value is empty
				                Throw ("Failed to get a .ASPXAuth cookie for Url {0}. Verify Url and try again." -f $CookieUri)
			                }
			                else
			                {
				                # Get Connection details
				                $Connection = $WebResponseResult.Result
				
				                # Add session to the Connection
				                $Connection | Add-Member -MemberType NoteProperty -Name Session -Value $PASSession

				                # Set Connection as global
				                $Global:PlatformConnection = $Connection

                                # setting the splat for variable connection 
                                $global:SessionInformation = @{ WebSession = $PlatformConnection.Session }

                                # if the $PlatformConnections variable does not contain this Connection, add it
                                if (-Not ($PlatformConnections | Where-Object {$_.PodFqdn -eq $Connection.PodFqdn}))
                                {
                                    # add a new PlatformConnection object and add it to our $PlatformConnectionsList
                                    $obj = [PlatformConnection]::new($Connection.PodFqdn,$Connection,$global:SessionInformation)
                                    $global:PlatformConnections.Add($obj) | Out-Null
                                }
				
				                # Return information values to confirm connection success
				                return ($Connection | Select-Object -Property CustomerId, User, PodFqdn | Format-List)
			                }# else
                        }# if ($WebResponseResult.Result.Summary -eq "LoginSuccess")
		            }# if ($WebResponseResult.Success)
		            else
		            {
                        # Unsuccesful connection
			            Throw $WebResponseResult.Message
		            }
                }# foreach ($Challenge in $InitialResponseResult.Result.Challenges)
		    }# if ($InitialResponseResult.Success)
		    else
		    {
			    # Unsuccesful connection
			    Throw $InitialResponseResult.Message
		    }
		}# else
	}# try
	catch
	{
		Throw $_.Exception
	}
}# function global:Connect-DelineaPlatform
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
        "Secret|DataVault" { $AceHash = @{ Grant = 1; View = 4; Edit  = 8; Delete = 64; Retrieve = 65536} ; break } # Grant,View,Edit,Delete,Retrieve
        "Set"              { $AceHash = @{ Grant    = 1; View    = 4; Edit    = 8; Delete    = 64} ; break } #Grant,View,Edit,Delete
        "ManualBucket|SqlDynamic"    
                           { $AceHash = @{ Grant    = 1; View    = 4; Edit     = 8; Delete    = 64} ; break }
        "Phantom"          { $AceHash = @{ Grant = 1; View = 4; Edit  = 8; Delete = 64; Add = 65536} ; break } # Grant,View,Edit,Delete,Add
        "Server"           { $AceHash = @{ Grant = 1; View = 4; Edit  = 8; Delete = 64; AgentAuth = 65536; 
                                           ManageSession = 128; RequestZoneRole = 131072; AddAccount = 524288;
                                           UnlockAccount = 1048576; OfflineRescue = 2097152;  ManagePrivilegeElevationAssignment = 4194304}; break }
        "Domain"           { $AceHash = @{ GrantAccount = 1; ViewAccount = 4; EditAccount = 8; DeleteAccount = 64; LoginAccount = 128; CheckoutAccount = 65536; 
                                           UpdatePasswordAccount = 131072; RotateAccount = 524288; FileTransferAccount = 1048576}; break }
        "Cloud"            { $AceHash = @{ GrantCloudAccount = 1; ViewCloudAccount = 4; EditVaultAccount = 8; DeleteCloudAccount = 64; UseAccessKey = 128;
                                           RetrieveCloudAccount = 65536} ; break }
        "Local|Account|VaultAccount" # Owner,View,Manage,Delete,Login,Naked,UpdatePassword,FileTransfer,UserPortalLogin 262276
                           { $AceHash = @{ Owner = 1; View = 4; Manage = 8; Delete = 64; Login = 128;  Naked = 65536; 
                                           UpdatePassword = 131072; UserPortalLogin = 262144; RotatePassword = 524288; FileTransfer = 1048576}; break }
        "Database|VaultDatabase"
                           { $AceHash = @{ GrantDatabaseAccount = 1; ViewDatabaseAccount = 4; EditDatabaseAccount = 8; DeleteDatabaseAccount = 64;
                                           CheckoutDatabaseAccount = 65536; UpdatePasswordDatabaseAccount = 131072; RotateDatabaseAccount = 524288}; break }
        "Subscriptions"    { $AceHash = @{ Grant = 1; View = 4; Edit = 8; Delete = 64} ; break } #Grant,View,Edit,Delete
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
        "Secret"    { $table = "DataVault"    ; break }
        "Set|Phantom|ManualBucket|SqlDynamic"
                    { $table = "Collections"  ; break }
        "Domain|Database|Local|Cloud"
                    { $table = "VaultAccount" ; break }
        "Server"    { $table = "Server"       ; break }
        default     { $table = $Type          ; break }
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

        # if the type is Super (from default global roles with read permissions)
        if ($rowace.Type -eq "Super")
        {
            # set the Grant to 4 instead of "Read"
            [System.Int64]$rowace.Grant = 4
        }

        Try
        {
            # creating the PlatformPermission object
            $platformpermission = [PlatformPermission]::new($Type, $rowace.Grant, $rowace.GrantStr)

            # creating the PlatformRowAce object
            $obj = [PlatformRowAce]::new($rowace.PrincipalType, $rowace.Principal, `
            $rowace.PrincipalName, $rowace.Inherited, $platformpermission)
        }# Try
        Catch
        {
            # setting our custom Exception object and stuff for further review
            $LastRowAceError = [PlatformRowAceException]::new("A PlatformRowAce error has occured. Check `$LastRowAceError for more information")
            $LastRowAceError.RowAce = $rowace
            $LastRowAceError.PlatformPermission = $platformpermission
            $LastRowAceError.ErrorMessage = $_.Exception.Message
            $global:LastRowAceError = $LastRowAceError
            Throw $_.Exception
        }# Catch

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

        Try
        {
            # creating the PlatformPermission object
            $platformpermission = [PlatformPermission]::new($Type, $collectionace.Grant, $collectionace.GrantStr)

            # creating the PlatformRowAce object
            $obj = [PlatformRowAce]::new($collectionace.PrincipalType, $collectionace.Principal, `
            $collectionace.PrincipalName, $collectionace.Inherited, $platformpermission)
        }# Try
        Catch
        {
            # setting our custom Exception object and stuff for further review
            $LastRowAceError = [PlatformRowAceException]::new("A PlatformRowAce error has occured. Check `$LastRowAceError for more information")
            $LastRowAceError.RowAce = $collectionace
            $LastRowAceError.PlatformPermission = $platformpermission
            $LastRowAceError.ErrorMessage = $_.Exception.Message
            $global:LastRowAceError = $LastRowAceError
            Throw $_.Exception
        }# Catch

        $CollectionAceObjects.Add($obj) | Out-Null
    }# foreach ($collectionace in $CollectionAces)

    # returning the RowAceObjects
    return $CollectionAceObjects
}# function global:Get-PlatformCollectionRowAce
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
#region ### global:Prepare-WorkflowApprovers # Prepares Workflow Approvers
###########
function global:Prepare-WorkflowApprovers
{
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The Workflow Approvers converted from.")]
        $Approvers
    )

    # setting a new ArrayList object
    $WorkflowApprovers = New-Object System.Collections.ArrayList

    # for each workflow approver
    foreach ($approver in $Approvers)
    {        
        # if the approver contains the NoManagerAction AND the BackupApprover Properties
        #if ((($approver | Get-Member -MemberType NoteProperty).Name).Contains("NoManagerAction") -and `
        #    (($approver | Get-Member -MemberType NoteProperty).Name).Contains("BackupApprover"))
        if ($approver.NoManagerAction -ne $null -and $approver.BackupApprover -ne $null)
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
        #elseif (((($approver | Get-Member -MemberType NoteProperty).Name).Contains("NoManagerAction")) -and `
        #        ($approver.NoManagerAction -eq "approve" -or ($approver.NoManagerAction -eq "deny")))
        elseif ($approver.NoManagerAction -eq "approve" -or ($approver.NoManagerAction -eq "deny"))
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
}# function global:Prepare-WorkflowApprovers
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

    # getting the original approvers by API call
    $approvers = Invoke-PlatformAPI -APICall ServerManage/GetSecretApprovers -Body (@{ ID = $uuid } | ConvertTo-Json)

    # preparing the workflow approver list
    $WorkflowApprovers = Prepare-WorkflowApprovers -Approvers ($approvers.WorkflowApproversList)
    
    # returning the ArrayList
    return $WorkflowApprovers
}# function global:Get-PlatformSecretWorkflowApprovers
#endregion
###########

###########
#region ### global:Get-PlatformZoneRoleWorkflowRoles # NOT USED UNTIL ZoneRoleWorkflow/GetRoles is FIXED
###########
function global:Get-PlatformZoneRoleWorkflowRoles
{
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The Uuid of the system to search.",ParameterSetName = "Uuid")]
        [System.String]$Uuid
    )

    
    # getting the zone roles by API call
    $zoneroles = Invoke-PlatformAPI -APICall ZoneRoleWorkflow/GetRoles -Body (@{ ResourceId = $uuid } | ConvertTo-Json)

    # preparing the zone roles
    $ZoneRoleWorkflowRoles = Prepare-ZoneRoles -Roles ($zoneroles.Roles)

    return $ZoneRoleWorkflowRoles
}# function global:Get-PlatformZoneRoleWorkflowRoles
#endregion
###########

###########
#region ### global:Prepare-ZoneRoles # NOT USED UNTIL ZoneRoleWorkflow/GetRoles is FIXED
###########
function global:Prepare-ZoneRoles
{
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The JSON roles to prepare.")]
        $Roles
    )

     # setting a new ArrayList object
     $ZoneRoles = New-Object System.Collections.ArrayList

     # for each zone role
     foreach ($role in $Roles)
     {        
        # create our new PlatformZoneRoleWorkflowRole object
        $obj = [PlatformZoneRoleWorkflowRole]::new($role)
 
         # adding it to our ArrayList
         $ZoneRoles.Add($obj) | Out-Null
     }# foreach ($role in $Roles)
 
     # returning the ArrayList
     return $ZoneRoles
}# function global:Prepare-ZoneRoles
#endregion
###########

###########
#region ### global:ConvertTo-SecretServerPermissions # TEMPLATE
###########
function global:ConvertTo-SecretServerPermission
{
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "Type")]
        [ValidateSet("Self","Set","Folder")]
        $Type,

        [Parameter(Mandatory = $true, HelpMessage = "Name")]
        $Name,

        [Parameter(Mandatory = $true, HelpMessage = "The JSON roles to prepare.")]
        $RowAce
    )

    if ($RowAce.PlatformPermission.GrantString -match "(Grant|Owner)")
    {
        $perms = "Owner"
    }
    elseif ($RowAce.PlatformPermission.GrantString -match '(Checkout|Retrieve|Naked)')
    {
        $perms = "View"
    }
    elseif ($RowAce.PlatformPermission.GrantString -like "*Edit*")
    {
        $perms = "Edit"
    }
    else
    {
        $perms = "List"
    }

    $permission = [Permission]::new($Type,$Name,$RowAce.PrincipalType,$RowAce.PrincipalName,$RowAce.isInherited,$perms,$RowAce.PlatformPermission.GrantString)
    
    return $permission

}# function global:ConvertTo-SecretServerPermissions
#endregion
###########

###########
#region ### global:ConvertTo-DataVaultCredential # TEMPLATE
###########
function global:ConvertTo-DataVaultCredential
{
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "Username")]
        [System.String]$Username,

        [Parameter(Mandatory = $false, HelpMessage = "Password")]
        [System.String]$Password,

        [Parameter(Mandatory = $true, HelpMessage = "Target")]
        [System.String]$Target,

        [Parameter(Mandatory = $true, HelpMessage = "Secret Template")]
        [System.String]$SecretTemplate,

        [Parameter(Mandatory = $true, HelpMessage = "ID of the PAS Secret")]
        [System.String]$ID,

        [Parameter(Mandatory = $true, HelpMessage = "RowAces")]
        [PSTypeName('PlatformRowAce')]$RowAces,

        [Parameter(Mandatory = $false, HelpMessage = "Slugs")]
        [System.Collections.Hashtable]$Slugs
    )

    $permissions = New-Object System.Collections.ArrayList

    foreach ($rowace in $rowaces)
    {
        $permissions.Add((ConvertTo-SecretServerPermission -Type self -Name ("{0}\{1}" -f $Target, $Username) -RowAce $rowace)) | Out-Null
    }

    $obj = [DataVaultCredential]::new($Username, $Password, $Target, $SecretTemplate, $permissions, $ID, $Slugs)

    return $obj

}# function global:ConvertTo-DataVaultCredential
#endregion
###########

###########
#region ### global:ConvertTo-MigratedCredential # TEMPLATE
###########
function global:ConvertTo-MigratedCredential
{
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "DVC",ParameterSetName="DataVaultCredential")]
        [PSTypeName('DataVaultCredential')]$DataVaultCredentials,

        [Parameter(Mandatory = $true, HelpMessage = "PA",ParameterSetName="PlatformAccount")]
        [PSTypeName('PlatformAccount')]$PlatformAccounts
    )

    $returnedobjects = New-Object System.Collections.ArrayList

    if ($PSBoundParameters.ContainsKey('DataVaultCredentials'))
    {
        foreach ($dvc in $DataVaultCredentials)
        {
            $obj = [MigratedCredential]::new($dvc)
            $returnedobjects.Add($obj) | Out-Null
        }
    }
    elseif ($PSBoundParameters.ContainsKey('PlatformAccounts'))
    {
        foreach ($pa in $PlatformAccounts)
        {
            $obj = [MigratedCredential]::new($pa)
            $returnedobjects.Add($obj) | Out-Null
        }
    }

    return $returnedobjects
}# function global:ConvertTo-MigratedCredential
#endregion
###########

###########
#region ### global:Prepare-PlatformSetBank # TEMPLATE
###########
function global:Prepare-PlatformSetBank
{
    <#
    .SYNOPSIS
    Gets Sets from the Platform with their members for storage and use later.

    .DESCRIPTION
    This cmdlet will retrieve the IDs of all Set objects in the tenant, then get the member IDs of all
    set objects to be used in the $SetBank global variable 

    .PARAMETER Multithreaded
    Performs the gets using multithreading, which may improve get times.

    .INPUTS
    None. You can't redirect or pipe input to this function.

    .OUTPUTS
    This function sets a global variable $SetBank that contains all Set information.

    .EXAMPLE
    C:\PS> Prepare-PlatformSetBank
    Gets all Set IDs and member IDs from the Platform and sets it in $SetBank.

    .EXAMPLE
    C:\PS> Prepare-PlatformSetBank -Multithreaded
    Gets all Set IDs and member IDs from the Platform and sets it in $SetBank. May perform faster
    because of multithreading. Might be a quicker option for Platforms with larger numbers of sets.

    .EXAMPLE
    #>
    [CmdletBinding(DefaultParameterSetName="All")]
    param
    (
        [Parameter(Mandatory = $false, HelpMessage = "Use multithreading.")]
        [Switch]$Multithreaded,

        [Parameter(Mandatory = $false, HelpMessage = "Export the SetBank.",ParameterSetName="Export")]
        [Switch]$Export,

        [Parameter(Mandatory = $false, HelpMessage = "Load the SetBank from a local file.",ParameterSetName="Load")]
        [Switch]$Load
    )

    if ($Export.IsPresent)
    {
        $global:SetBank | Export-Clixml .\PlatformSetBank.xml
        return
    }

    if ($Load.IsPresent)
    {
        $global:SetBank = Import-Clixml .\PlatformSetBank.xml
        return
    }

    $SetIds = Query-VaultRedRock -SQLQuery "Select ID from Sets WHERE CollectionType = 'ManualBucket'" | Select-Object -ExpandProperty ID
    $SetBank = New-Object System.Collections.ArrayList
    
    if ($Multithreaded.IsPresent)
    {
        [runspacefactory]::CreateRunspacePool()
        $RunspacePool = [runspacefactory]::CreateRunspacePool(1,12)
        $RunspacePool.Open()

        $Jobs = New-Object System.Collections.ArrayList

        foreach ($setid in $SetIds)
        {
            $PowerShell = [PowerShell]::Create()
            $PowerShell.RunspacePool = $RunspacePool

            # Counter for the secret objects
            $p++; Write-Progress -Activity "Processing Sets" -Status ("{0} out of {1} Complete" -f $p,$SetIds.Count) -PercentComplete ($p/($SetIds | Measure-Object | Select-Object -ExpandProperty Count)*100)
            

            # this works to pass PlatformPlus into 
            [void]$PowerShell.AddScript((Get-Content ".\PlatformPlus.ps1" -Raw))
            [void]$PowerShell.AddScript(
            {

            Param
            (
                $PlatformConnection,
                $SessionInformation,
                $SetID
            )
            $global:PlatformConnection = $PlatformConnection
            $global:SessionInformation = $SessionInformation

            $obj = [SetBankMember]::new($setid)

            $members = Invoke-PlatformAPI -APICall Collection/GetMembers -Body (@{ID=$setid} | ConvertTo-Json)

            foreach ($member in $members.Key)
            {
                $obj.addMemberID($member)
            }

            return $obj

            })# [void]$PowerShell.AddScript(
            [void]$PowerShell.AddParameter('PlatformConnection',$global:PlatformConnection)
            [void]$PowerShell.AddParameter('SessionInformation',$global:SessionInformation)
            [void]$PowerShell.AddParameter('SetID',$setid)

            $JobObject = @{}
            $JobObject.Runspace   = $PowerShell.BeginInvoke()
            $JobObject.PowerShell = $PowerShell

            $Jobs.Add($JobObject) | Out-Null
        }# foreach ($setid in $SetIds)

        foreach ($job in $jobs)
        {
            $SetBank.Add($job.powershell.EndInvoke($job.RunSpace)) | Out-Null
            $job.PowerShell.Dispose()
        }
    }# if ($Multithreaded.IsPresent)
    else
    {
        foreach ($setid in $SetIds)
        {
            # Counter for the secret objects
            $p++; Write-Progress -Activity "Processing Sets" -Status ("{0} out of {1} Complete" -f $p,$SetIds.Count) -PercentComplete ($p/($SetIds | Measure-Object | Select-Object -ExpandProperty Count)*100)
            
            $obj = [SetBankMember]::new($setid)

            $members = Invoke-PlatformAPI -APICall Collection/GetMembers -Body (@{ID=$setid} | ConvertTo-Json)

            foreach ($member in $members.Key)
            {
                $obj.addMemberID($member)
            }

            $SetBank.Add($obj) | Out-Null
        }# foreach ($setid in $SetIds)
    }# else

    $global:SetBank = $SetBank
}# function global:Prepare-PlatformSetBank
#endregion
###########

###########
#region ### global:Get-PlatformSetDiagram # Initial work for a way to display Set information in a more visual manner
###########
function global:Get-PlatformSetDiagram
{
    # verify an active platform connection
    Verify-PlatformConnection

    # set query
    $sets = Query-VaultRedRock -SQLQuery "SELECT Name,ID,ObjectType,CollectionType FROM Sets LIMIT 50"

    # Get Set Bank
    if ($global:SetBank -eq $null)
    {
        Prepare-PlatformSetBank -Multithreaded
    }

    $DiagramSets = New-Object System.Collections.ArrayList

    foreach ($set in $sets)
    {
        Write-Host ("Set [{0}]" -f $set.Name)
        $obj = [DiagramSet]::new($set.Name,$set.ObjectType)

        $members = ($global:SetBank | Where-Object {$_.SetID -eq $set.ID}).MemberIDs

        Switch($set.ObjectType)
        {
            "DataVault"    { $query = "SELECT SecretName AS Name FROM DataVault WHERE ID = "; break }
            "Server"       { $query = "SELECT FQDN AS Name FROM Server WHERE ID = "; break }
            "VaultAccount" { $query = "SELECT User AS Name FROM VaultAccount WHERE ID = "; break }
            default { $query = $null }
        }# Switch($set.ObjectType)

        if ($query -eq $null)
        {
            continue
        }

        foreach ($member in $members)
        {
            Write-Host ("member [{0}]" -f $member)

            $newquery = $query + ("'{0}'" -f $member)

            $name = Query-VaultRedRock -SQLQuery $newquery | Select-Object -ExpandProperty Name

            $obj.AddMember($name) | Out-Null
        }

        $DiagramSets.Add($obj) | Out-Null
    }# foreach ($set in $sets)

    return $DiagramSets
}# function global:Get-PlatformSetDiagram
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

#
class PlatformMetric
{
    [PSCustomObject]$ServersCountTotal
    [PSCustomObject]$AccountsCountTotal
    [PSCustomObject]$SecretsCountTotal
    [PSCustomObject]$SetsCountTotal
    [PSCustomObject]$DomainCountTotal
    [PSCustomObject]$CommandCountTotal
    [PSCustomObject]$AppCountTotal
    [PSCustomObject]$CentrifyClientCountTotal
    [PSCustomObject]$RoleCountTotal
    [PSCustomObject]$ConnectorCountTotal
    [PlatformData]$PlatformData
    [PSCustomObject]$Version

    PlatformMetric($pd,$v)
    {
        $this.PlatformData = $pd
        $this.Version = $v

        # server metrics
        $this.addCount("OperatingSystem","Servers","ServerCountBy_OS")
        $this.addCount("ComputerClass","Servers","ServerCountBy_ComputerClass")
        $this.addCount("LastState","Servers","ServerCountBy_LastState")
        $this.addCount("HealthStatus","Servers","ServerCountBy_HealthStatus")
        $this.ServersCountTotal = $this.PlatformData.Servers.Count

        # account metrics
        $this.addCount("Healthy","Accounts","AccountCountBy_Health")
        $this.AccountsCountTotal = $this.PlatformData.Accounts.Count
        
        # secret metrics
        $this.addCount("Type","Secrets","SecretsCountBy_Type")
        $this.SecretsCountTotal = $this.PlatformData.Secrets.Count

        # set metrics
        $this.addCount("ObjectType","Sets","SetsCountBy_ObjectType")
        $this.addCount("CollectionType","Sets","SetsCountBy_CollectionType")
        $this.SetsCountTotal = $this.PlatformData.Sets.Count

        # domain metrics
        $this.addCount("LastState","Domains","DomainsCountBy_LastState")
        $this.DomainCountTotal = $this.PlatformData.Sets.Count

        # command metrics
        $this.CommandCountTotal = $this.PlatformData.Commands.Count

        # app metrics
        $this.addCount("State","Apps","AppsCountBy_State")
        $this.addCount("AppType","Apps","AppsCountBy_AppType")
        $this.addCount("Category","Apps","AppsCountBy_Category")
        $this.AppCountTotal = $this.PlatformData.Apps.Count

        # centrifyclient metrics
        $this.CentrifyClientCountTotal = $this.PlatformData.CentrifyClients.Count

        # role metrics
        $this.RoleCountTotal = $this.PlatformData.Roles.Count

        # connector metrics
        $this.addCount("Version","Connectors","ConnectorsCountBy_Version")
        $this.ConnectorCountTotal = $this.PlatformData.Connectors.Count
    }

    addCount($property, $obj, $counttext)
    {
        # count by property
        foreach ($i in ($this.PlatformData.$obj | Select-Object -ExpandProperty $property -Unique))
        {
            $this | Add-Member -MemberType NoteProperty -Name ("{0}_{1}" -f $counttext, ($i -replace " ","_")) -Value ($this.PlatformData.$obj | Where-Object {$_.$property -eq $i} | Measure-Object | Select-Object -ExpandProperty Count)
        }
    }# addCount($property, $obj, $counttext)

    [PSCustomObject]printCount()
    {
        return $this | Select-Object -Property * -ExcludeProperty PlatformData,Version
    }

    [System.Double]getTotalFileSize()
    {
        $filesecrets = $this.PlatformData.Secrets | Where-Object {$_.Type -eq "File"}

        [System.Double]$filesizetotal = 0

        foreach ($filesecret in $filesecrets)
        {
            [System.Double]$size = $filesecret.SecretFileSize -replace '\s[A-Z]+',''
            
            Switch -Regex (($filesecret.SecretFileSize -replace '^[\d\.]+\s([\w]+)$','$1'))
            {
                '^B$'  { $filesizetotal += $size; break }
                '^KB$' { $filesizetotal += ($size * 1024); break }
                '^MB$' { $filesizetotal += ($size * 1048576); break }
                '^GB$' { $filesizetotal += ($size * 1073741824); break }
                '^TB$' { $filesizetotal += ($size * 1099511627776); break }
            }
        }# foreach ($filesecret in $filesecrets)
        return $filesizetotal
    }# [System.Double]getTotalFileSize()

}# class PlatformMetric

# class for holding Platform metrics
class PlatformData
{
    [PSCustomObject]$Servers
    [PSCustomObject]$Accounts
    [PSCustomObject]$Secrets
    [PSCustomObject]$Sets
    [PSCustomObject]$Domains
    [PSCustomObject]$Commands
    [PSCustomObject]$Apps
    [PSCustomObject]$CentrifyClients
    [PSCustomObject]$Roles
    [PSCustomObject]$Connectors
    
    PlatformData($s,$a,$sec,$set,$d,$c,$ap,$cc,$r,$con)
    {
        $this.Servers = $s
        $this.Accounts = $a
        $this.Secrets = $sec
        $this.Sets = $set
        $this.Domains = $d
        $this.Commands = $c
        $this.Apps = $ap
        $this.CentrifyClients = $cc
        $this.Roles = $r
        $this.Connectors = $con
    }# PlatformData($s,$a,$sec,$set,$d,$c,$ap,$cc,$r,$con)
}# class PlatformData

# class for holding Permission information including converting it to
# a human readable format
class PlatformPermission
{
    [System.String]$Type        # the type of permission (Secret, Account, etc.)
    [System.Int64]$GrantInt     # the Int-based number for the permission mask
    [System.String]$GrantBinary # the binary string of the the permission mask
    [System.String]$GrantString # the human readable permission mask

    PlatformPermission ([PSCustomObject]$pp)
    {
        $this.Type = $pp.Type
        $this.GrantInt = $pp.GrantInt
        $this.GrantBinary = $pp.GrantBinary
        $this.GrantString = Convert-PermissionToString -Type $pp.Type -PermissionInt ([System.Convert]::ToInt64($pp.GrantBinary,2))
    }# PlatformPermission ([PSCustomObject]$pp)

    PlatformPermission ([System.String]$t, [System.Int64]$gi, [System.String]$gb)
    {
        $this.Type        = $t
        $this.GrantInt    = $gi
        $this.GrantBinary = $gb
        $this.GrantString = Convert-PermissionToString -Type $t -PermissionInt ([System.Convert]::ToInt64($gb,2))
    }# PlatformPermission ([System.String]$t, [System.Int64]$gi, [System.String]$gb)
}# class PlatformPermission

# class for holding RowAce information
class PlatformRowAce
{
    [System.String]$PrincipalType           # the principal type
    [System.String]$PrincipalUuid           # the uuid of the prinicpal
    [System.String]$PrincipalName           # the name of the principal
    [System.Boolean]$isInherited            # determines if this permission is inherited
    [PlatformPermission]$PlatformPermission # the platformpermission object

    PlatformRowAce([PSCustomObject]$pra)
    {
        $this.PrincipalType      = $pra.PrincipalType
        $this.PrincipalUuid      = $pra.PrincipalUuid
        $this.PrincipalName      = $pra.PrincipalName
        $this.isInherited        = $pra.isInherited
        $this.PlatformPermission = [PlatformPermission]::new($pra.PlatformPermission)
   }# PlatformRowAce([PSCustomObject]$pra)

    PlatformRowAce([System.String]$pt, [System.String]$puuid, [System.String]$pn, `
                   [System.Boolean]$ii, [PlatformPermission]$pp)
    {
        $this.PrincipalType      = $pt
        $this.PrincipalUuid      = $puuid
        $this.PrincipalName      = $pn
        $this.isInherited        = $ii
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
    [System.Boolean]$WorkflowEnabled               # is Workflow enabled
    [PlatformWorkflowApprover[]]$WorkflowApprovers # the Workflow Approvers for this Secret

    PlatformSecret ($secretinfo)
    {
        $this.Name = $secretinfo.SecretName
        $this.Type = $secretinfo.Type
        $this.ParentPath = $secretinfo.ParentPath
        $this.Description = $secretinfo.Description
        $this.ID = $secretinfo.ID
        $this.FolderId = $secretinfo.FolderId
        $this.WorkflowEnabled = $secretinfo.WorkflowEnabled

        if ($secretinfo.whenCreated -ne $null)
        {
            $this.whenCreated = $secretinfo.whenCreated
        }
        
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

        # if Workflow is enabled
        if ($this.WorkflowEnabled)
        {
            # get the WorkflowApprovers for this secret
            $this.WorkflowApprovers = Get-PlatformSecretWorkflowApprovers -Uuid $this.ID
        }
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
        # if the directory doesn't exist and it is not the Root PAS directory
        if ((-Not (Test-Path -Path $this.ParentPath)) -and $this.ParentPath -ne ".")
        {
            # create directory
            New-Item -Path $this.ParentPath -ItemType Directory | Out-Null
        }

        Switch ($this.Type)
        {
            "Text" # Text secrets will be created as a .txt file
            {
                # if the File does not already exists
                if (-Not (Test-Path -Path ("{0}\{1}" -f $this.ParentPath, $this.Name)))
                {
                    # create it
                    $this.SecretText | Out-File -FilePath ("{0}\{1}.txt" -f $this.ParentPath, $this.Name)
                }
                
                break
            }# "Text" # Text secrets will be created as a .txt file
            "File" # File secrets will be created as their current file name
            {
                $filename      = $this.SecretFileName.Split(".")[0]
                $fileextension = $this.SecretFileName.Split(".")[1]

                # if the file already exists
                if ((Test-Path -Path ("{0}\{1}" -f $this.ParentPath, $this.SecretFileName)))
                {
                    # append the filename 
                    $fullfilename = ("{0}_{1}.{2}" -f $filename, (-join ((65..90) + (97..122) | Get-Random -Count 8 | ForEach-Object{[char]$_})).ToUpper(), $fileextension)
                }
                else
                {
                    $fullfilename = $this.SecretFileName
                }

                # create the file
                Invoke-RestMethod -Method Get -Uri $this.SecretFilePath -OutFile ("{0}\{1}" -f $this.ParentPath, $fullfilename) @global:SessionInformation
                break
            }# "File" # File secrets will be created as their current file name
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
    [System.String]$BackupApprover
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
    [System.String]$ParentPath
    [PlatformRowAce[]]$PermissionRowAces             # permissions of the Set object itself
    [PlatformRowAce[]]$MemberPermissionRowAces       # permissions of the members for this Set object
    [System.Collections.ArrayList]$MembersUuid = @{} # the Uuids of the members
    [System.Collections.ArrayList]$SetMembers  = @{} # the members of this set
    [System.String]$PotentialOwner                   # a guess as to who possibly owns this set

    PlatformSet() {}

    PlatformSet($set)
    {
        $this.SetType = $set.CollectionType
        $this.ObjectType = $set.ObjectType
        $this.Name = $set.Name
        $this.ID = $set.ID
        $this.Description = $set.Description
        $this.ParentPath = $set.ParentPath

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
        # getting members
        [PSObject]$m = $null

        # a little tinkering because Secret Folders ('Phantom') need a different endpoint to get members
        Switch ($this.SetType)
        {
            "Phantom" # if this SetType is a Secret Folder
            { 
                # get the members and reformat the data a bit so it matches Collection/GetMembers
                $m = Invoke-PlatformAPI -APICall ServerManage/GetSecretsAndFolders -Body (@{Parent=$this.ID} | ConvertTo-Json)
                $m = $m.Results.Entities
                $m | Add-Member -Type NoteProperty -Name Table -Value DataVault
                break
            }
            "ManualBucket" # if this SetType is a Manual Set
            {
                $m = Invoke-PlatformAPI -APICall Collection/GetMembers -Body (@{ID = $this.ID} | ConvertTo-Json)
            }
            default        { break }
        }

        # getting the set members
        if ($m -ne $null)
        {
            # Adding the Uuids to the Members property
            foreach ($u in $m)
            {
                $this.MembersUuid.Add($u.Key) | Out-Null
            }

            # for each item in the query
            foreach ($i in $m)
            {
                $obj = $null
                
                # getting the object based on the Uuid
                Switch ($i.Table)
                {
                    "DataVault"    {$obj = Query-VaultRedRock -SQLQuery ("SELECT ID AS Uuid,SecretName AS Name FROM DataVault WHERE ID = '{0}'" -f $i.Key); break }
                    "VaultAccount" {$obj = Query-VaultRedRock -SQLQuery ("SELECT ID AS Uuid,(Name || '\' || User) AS Name FROM VaultAccount WHERE ID = '{0}'" -f $i.Key); break }
                    "Server"       {$obj = Query-VaultRedRock -SQLQuery ("SELECT ID AS Uuid,Name FROM Server WHERE ID = '{0}'" -f $i.Key); break }
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

    [PSCustomObject]getPlatformObjects()
    {
        $PlatformObjects = New-Object System.Collections.ArrayList

        [System.String]$command = $null

        Switch ($this.ObjectType)
        {
            "DataVault"    { $command = 'Get-PlatformSecret'; break }
            "Server"       { $command = 'Get-PlatformSystem'; break }
            "VaultAccount" { $command = 'Get-PlatformAccount'; break }
            default        { Write-Host "This set type not supported yet."; return $false ; break }
        }

        foreach ($id in $this.MembersUuid)
        {
            Invoke-Expression -Command ('[void]$PlatformObjects.Add(({0} -Uuid {1}))' -f $command, $id)
        }

        return $PlatformObjects
    }# [PSCustomObject]getPlatformObjects()
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

# class for configured Vaults
class PlatformVault
{
    [System.String]$VaultType
    [System.String]$VaultName
    [System.String]$ID
    [System.String]$Url
    [System.String]$Username
    [System.Int32]$SyncInterval
    [System.DateTime]$LastSync

    PlatformVault($vault)
    {
        $this.VaultType = $vault.VaultType
        $this.VaultName = $vault.VaultName
        $this.ID = $vault.ID

        if ($vault.LastSync -ne $null)
        {
            $this.LastSync = $vault.LastSync
        }

        $this.SyncInterval = $vault.SyncInterval
        $this.Username = $vault.Username
        $this.Url = $vault.Url
    }
}

# class to hold Accounts
class PlatformAccount
{
    [System.String]$AccountType
    [System.String]$ComputerClass
    [System.String]$SourceName
    [System.String]$SourceType
    [System.String]$SourceID
    [System.String]$Username
    [System.String]$ID
    [System.Boolean]$isManaged
    [System.String]$Healthy
    [System.DateTime]$LastHealthCheck
    [System.String]$Password
    [System.String]$Description
    [PlatformRowAce[]]$PermissionRowAces           # The RowAces (Permissions) of this Account
    [System.Boolean]$WorkflowEnabled
    [PlatformWorkflowApprover[]]$WorkflowApprovers # the workflow approvers for this Account
    [PlatformVault]$Vault
    [System.String]$SSName
    [System.DateTime]$LastCheckOut
    [System.String]$CheckOutID

    PlatformAccount() {}

    PlatformAccount($account, [System.String]$t)
    {
       
        $this.AccountType = $t
        $this.ComputerClass = $account.ComputerClass
        $this.SourceName = $account.Name

        # the tenant holds the source object's ID in different columns
        Switch ($this.AccountType)
        {
            "Database" { $this.SourceID = $account.DatabaseID; $this.SourceType = "DatabaseId"; break }
            "Domain"   { $this.SourceID = $account.DomainID; $this.SourceType = "DomainId"; break }
            "Local"    { $this.SourceID = $account.Host; $this.SourceType = "Host"; break }
            "Cloud"    { $this.SourceID = $account.CloudProviderID; $this.SourceType = "CloudProviderId"; break }
        }

        # accounting for null
        if ($account.LastHealthCheck -ne $null)
        {
            $this.LastHealthCheck = $account.LastHealthCheck
        }

        $this.Username = $account.User
        $this.ID = $account.ID
        $this.isManaged = $account.IsManaged
        $this.Healthy = $account.Healthy
        $this.Description = $account.Description
        $this.SSName = ("{0}\{1}" -f $this.SourceName, $this.Username)

        # Populate the Vault property if Account is imported from a Vault
        if ($account.VaultId -ne $null)
        {
            $this.Vault = (Get-PlatformVault -Uuid $account.VaultId)
        } # if ($null -ne $account.VaultId)
        
        # getting the RowAces for this Set
        $this.PermissionRowAces = Get-PlatformRowAce -Type $this.AccountType -Uuid $this.ID

        # getting the WorkflowApprovers for this secret
        $this.WorkflowEnabled = $account.WorkflowEnabled
        
        # getting the WorkflowApprovers for this Account
        if ($this.WorkflowEnabled)
        {
            $this.WorkflowApprovers = Prepare-WorkflowApprovers -Approvers ($account.WorkflowApproversList | ConvertFrom-Json)
        }

    }# PlatformAccount($account)

    [System.Boolean] CheckOutPassword()
    {
        # if checkout is successful
        if ($checkout = Invoke-PlatformAPI -APICall ServerManage/CheckoutPassword -Body (@{ID = $this.ID} | ConvertTo-Json))
        {   
            # set these checkout fields
            $this.Password = $checkout.Password
            $this.CheckOutID = $checkout.COID
            $this.LastCheckOut = (Get-Date)
        }# if ($checkout = Invoke-PlatformAPI -APICall ServerManage/CheckoutPassword -Body (@{ID = $this.ID} | ConvertTo-Json))
        else
        {
            return $false
        }
        return $true
    }# [System.Boolean] CheckOutPassword()

    [System.Boolean] CheckInPassword()
    {
        # if CheckOutID isn't null
        if ($this.CheckOutID -ne $null)
        {
            # if checkin is successful
            if ($checkin = Invoke-PlatformAPI -APICall ServerManage/CheckinPassword -Body (@{ID = $this.CheckOutID} | ConvertTo-Json))
            {
                $this.Password   = $null
                $this.CheckOutID = $null
            }
            else
            {
                return $false
            }
        }# if ($this.CheckOutID -ne $null)
        else
        {
            return $false
        }
        return $true 
    }# [System.Boolean] CheckInPassword()

    [System.Boolean] UnmanageAccount()
    {
        # if the account was successfully unmanaged
        if ($manageaccount = Invoke-PlatformAPI ServerManage/UpdateAccount -Body (@{ID=$this.ID;User=$this.Username;$this.SourceType=$this.SourceID;IsManaged=$false}|ConvertTo-Json))
        {
            $this.isManaged = $false
            return $true
        }
        return $false
    }# [System.Boolean] UnmanageAccount()

    [System.Boolean] ManageAccount()
    {
        # if the account was successfully managed
        if ($manageaccount = Invoke-PlatformAPI ServerManage/UpdateAccount -Body (@{ID=$this.ID;User=$this.Username;$this.SourceType=$this.SourceID;IsManaged=$true}|ConvertTo-Json))
        {
            $this.isManaged = $true
            return $true
        }
        return $false
    }# [System.Boolean] ManageAccount()

    [System.Boolean] VerifyPassword()
    {
        Write-Debug ("Starting Password Health Check for {0}" -f $this.Username)
        $result = Invoke-PlatformAPI -APICall ServerManage/CheckAccountHealth -Body (@{"ID"=$this.ID} | ConvertTo-Json)
        $this.Healthy = $result
        Write-Debug ("Password Health: {0}" -f $result)

        # if the VerifyCredentials comes back okay, return true
        if ($result -eq "OK")
        {
            return $true
        }
        else
        {
            return $false
        }
    }# VerifyPassword()

    [System.Boolean] UpdatePassword()
    {
        # if the account was successfully managed
        if ($updatepassword = Invoke-PlatformAPI ServerManage/UpdatePassword -Body (@{ID=$this.ID;Password=$this.Password}|ConvertTo-Json))
        {
            return $true
        }
        return $false
    }# [System.Boolean] ManageAccount()

    [System.Boolean] UpdatePassword($password)
    {
        # if the account was successfully managed
        if ($updatepassword = Invoke-PlatformAPI ServerManage/UpdatePassword -Body (@{ID=$this.ID;Password=$password}|ConvertTo-Json))
        {
            return $true
        }
        return $false
    }# [System.Boolean] ManageAccount()
}# class PlatformAccount

# class to hold Systems
class PlatformSystem 
{
    [System.String]$Name
    [System.String]$Description
    [System.String]$FQDN
    [System.String]$ComputerClass
    [System.String]$SessionType
    [System.String]$ID
    [System.String]$ProxyUser
    [System.Boolean]$ProxyUserIsManaged
    [System.Int32]$ActiveCheckouts
    [System.Boolean]$DomainOperationsEnabled
    [System.String]$DomainName
    [System.String]$DomainId
    [System.String]$ZoneStatus
    [System.Boolean]$ZoneRoleWorkflowEnabled
    [System.Boolean]$UseDomainWorkflowRoles
    [PlatformZoneRoleWorkflowRole[]]$ZoneRoleWorkflowRoles
    [System.Boolean]$UseDomainWorkflowApprovers
    [PlatformWorkflowApprover[]]$ZoneRoleWorkflowApprovers
    [System.String]$AgentVersion
    [System.String]$OperatingSystem
    [System.Boolean]$Reachable
    [System.String]$HealthStatus
    [System.String]$LastState
    [System.String]$HealthStatusError
    [System.String]$ReachableError
    [System.DateTime]$LastHealthCheck
    [PlatformRowAce[]]$PermissionRowAces
    [PlatformAccount[]]$PlatformAccounts

    PlatformSystem($system)
    {
        $this.Name = $system.Name
        $this.Description = $system.Description
        $this.FQDN = $system.FQDN
        $this.ComputerClass = $system.ComputerClass
        $this.SessionType = $system.SessionType
        $this.ID = $system.ID
        $this.ProxyUser = $system.ProxyUser
        $this.ProxyUserIsManaged = $system.ProxyUserIsManaged
        $this.DomainOperationsEnabled = $system.DomainOperationsEnabled
        $this.DomainName = $system.DomainName
        $this.DomainId = $system.DomainId
        $this.ZoneStatus = $system.ZoneStatus
        $this.UseDomainWorkflowRoles = $system.UseDomainWorkflowRoles
        $this.UseDomainWorkflowApprovers = $system.UseDomainWorkflowApprovers
        $this.ZoneRoleWorkflowEnabled = $system.ZoneRoleWorkflowEnabled
        $this.AgentVersion = $system.AgentVersion
        $this.OperatingSystem = $system.OperatingSystem
        $this.Reachable = $system.Reachable
        $this.LastState = $system.LastState
        $this.HealthStatusError = $system.HealthStatusError
        $this.ReachableError = $system.ReachableError
        
        # accounting for null
        if ($system.LastHealthCheck -ne $null)
        {
            $this.LastHealthCheck = $system.LastHealthCheck
        }
        
        # getting the RowAces for this System
        $this.PermissionRowAces = Get-PlatformRowAce -Type "SERVER" -Uuid $this.ID

        # getting the Zone Roles if enabled
        if ($this.ZoneRoleWorkflowEnabled)
        {
            # broken until the endpoint is fixed
            #$this.ZoneRoleWorkflowRoles = Get-PlatformZoneRoleWorkflowRoles -Uuid $this.ID

            # temporary until endpoint is fixed
            if ($system.ZoneRoleWorkflowRoles -ne $null)
            {
                $collection = New-Object System.Collections.ArrayList

                foreach ($zonerole in ($system.ZoneRoleWorkflowRoles | ConvertFrom-Json))
                {
                    $obj = [PlatformZoneRoleWorkflowRole]::new($zonerole)
                    $collection.Add($obj) | Out-Null
                }

                $this.ZoneRoleWorkflowRoles = $collection
            }# if ($system.ZoneRoleWorkflowRoles -ne $null)

            # if approvers exist
            if ($system.ZoneRoleWorkflowApproversList -ne $null)
            {
                $approvers = Invoke-PlatformAPI -APICall ZoneRoleWorkflow/GetApprovers -Body (@{ResourceId = $this.ID;ScopeType="Computer"} | ConvertTo-Json)

                $this.ZoneRoleWorkflowApprovers = Prepare-WorkflowApprovers -Approvers $approvers.WorkflowApprovers
            }
        }# if ($this.ZoneRoleWorkflowEnabled)
    }# PlatformSystem($system)
    
    getAccounts()
    {
        if ($a = Get-PlatformAccount -Type Local -SourceName $this.Name)
        {
            $this.PlatformAccounts = $a
        }
    }
}# class PlatformSystem

# class to hold Roles
class PlatformRole
{
    [System.String]$ID
    [System.String]$Name
    [System.String]$RoleType
    [System.Boolean]$ReadOnly
    [System.String]$Description
    [System.String]$DirectoryServiceUuid
    [System.Collections.ArrayList]$Members = @{} # Members of the role
    [System.Collections.ArrayList]$AssignedRights = @{} # Assigned administrative rights of the role

    PlatformRole($role)
    {
        $this.ID = $role.ID
        $this.Name = $role.Name
        $this.RoleType = $role.RoleType
        $this.ReadOnly = $role.ReadOnly
        $this.Description = $role.Description
        $this.DirectoryServiceUuid = $role.DirectoryServiceUuid
        $this.getRoleMembers()
        $this.getRoleAssignedRights()
    }# PlatformRole($role)

    getRoleMembers()
    {
        # get the Role Members
        $rm = ((Invoke-PlatformAPI -APICall ("SaasManage/GetRoleMembers?name={0}" -f $this.ID)).Results.Row)
        
        # if there are more than 0 members
        if ($rm.Count -gt 0)
        {
            foreach ($r in $rm)
            {
                $this.Members.Add(([PlatformRoleMember]::new($r))) | Out-Null
            }
        }
    }# getRoleMembers()

    getRoleAssignedRights()
    {
        # get the role's assigned administrative rights
        $ar = ((Invoke-PlatformAPI -APICall ("core/GetAssignedAdministrativeRights?role={0}" -f $this.ID)).Results.Row)
        
        # if there are more than 0 assigned rights
        if ($ar.Count -gt 0)
        {
            foreach ($a in $ar)
            {
                $this.AssignedRights.Add(([PlatformRoleAssignedRights]::new($a))) | Out-Null
            }
        }
    }# getRoleAssignedRights()
}# class PlatformRole

# class to hold Role Members
class PlatformRoleMember
{
    [System.String]$Guid
    [System.String]$Name
    [System.String]$Type

    PlatformRoleMember($roleMember)
    {
        $this.Guid = $roleMember.Guid
        $this.Name = $roleMember.Name
        $this.Type = $roleMember.Type
    }# PlatformRoleMember($roleMember)
}# class PlatformRoleMember

# class to hold Role Assigned Administrative Rights
class PlatformRoleAssignedRights
{
    [System.String]$Description
    [System.String]$Path

    PlatformRoleAssignedRights($assignedRights)
    {
        $this.Description = $assignedRights.Description
        $this.Path = $assignedRights.Path
    }# PlatformRoleAssignedRights($assignedRights)
}# class PlatformRoleAssignedRights

# class to hold a PlatformZoneRoleWorkflow Role
class PlatformZoneRoleWorkflowRole
{
    [System.String]$Name
    [System.Boolean]$Unix
    [System.Boolean]$Windows
    [System.String]$ZoneDN
    [System.String]$Description
    [System.String]$ZoneCanonicalName
    [System.String]$ParentZoneDN

    PlatformZoneRoleWorkflowRole ($zoneworkflowrole)
    {
        $this.Name = $zoneworkflowrole.Name
        $this.Unix = $zoneworkflowrole.Unix
        $this.Windows = $zoneworkflowrole.Windows
        $this.ZoneDN = $zoneworkflowrole.ZoneDn
        $this.Description = $zoneworkflowrole.Description
        $this.ZoneCanonicalName = $zoneworkflowrole.ZoneCanonicalName
        $this.ParentZoneDN = $zoneworkflowrole.ParentZoneDn
    }# PlatformZoneRoleWorkflowRole ($zoneworkflowrole)
}# class PlatformZoneRoleWorkflowRole

# class to hold PlatformConnections
class PlatformConnection
{
    [System.String]$PodFqdn
    [PSCustomObject]$PlatformConnection
    [System.Collections.Hashtable]$SessionInformation

    PlatformConnection($po,$pc,$s)
    {
        $this.PodFqdn = $po
        $this.PlatformConnection = $pc
        $this.SessionInformation = $s
    }
}# class PlatformConnection

# class to hold SearchPrincipals
class PlatformPrincipal
{
    [System.String]$Name
    [System.String]$ID

    PlatformPrincipal($n,$i)
    {
        $this.Name = $n
        $this.ID = $i
    }
}# class PlatformPrincipal

# 
class SetBankMember
{
    [System.String]$SetID
    [System.Collections.ArrayList]$MemberIDs = @{}

    SetBankMember([System.String]$sid)
    {
        $this.SetID = $sid
    }

    addMemberID([System.String]$id)
    {
        $this.MemberIDs.Add($id) | Out-Null
    }
}# class SetBankMember

class DiagramSet
{
    [System.String]$SetName
    [System.String]$SetType
    [System.Collections.ArrayList]$SetMembers = @{}

    DiagramSet([System.String]$sn, [System.String]$st)
    {
        $this.SetName = $sn
        $this.SetType = $st
    }

    addMember([System.String]$n)
    {
        $this.SetMembers.Add($n) | Out-Null
    }

    [System.Collections.ArrayList] ExportData()
    {

        $data = New-Object System.Collections.ArrayList

        foreach ($member in $this.SetMembers)
        {
            $obj = New-Object PSObject

            $obj | Add-Member -MemberType NoteProperty -Name SetName -Value $this.SetName
            $obj | Add-Member -MemberType NoteProperty -Name SetType -Value $this.SetType
            $obj | Add-Member -MemberType NoteProperty -Name SetMember -Value $member

            $data.Add($obj) | Out-Null
        }# foreach ($member in $this.SetMembers)

        return $data
    }# ExportData()
}# class DiagramSet

# class to hold migrated permissions
class Permission
{
    [System.String]$PermissionType
    [System.String]$PermissionName
    [System.String]$PrincipalType
    [System.String]$PrincipalName
    [System.Boolean]$isInherited
    [System.String]$Permissions
    [System.String]$OriginalPermissions

    Permission([PSCustomObject]$p)
    {
        $this.PermissionType      = $p.PermissionType
        $this.PermissionName      = $p.PermissionName
        $this.PrincipalType       = $p.PrincipalType
        $this.PrincipalName       = $p.PrincipalName
        $this.isInherited         = $p.isInherited
        $this.Permissions         = $p.Permissions
        $this.OriginalPermissions = $p.OriginalPermissions
    }# Permission([PSCustomObject]$p)

    Permission([System.String]$pt, [System.String]$pn, [System.String]$prt, [System.String]$prn, `
               [System.String]$ii, [System.String[]]$p, [System.String[]]$op)
    {
        $this.PermissionType      = $pt
        $this.PermissionName      = $pn
        $this.PrincipalType       = $prt
        $this.PrincipalName       = $prn
        $this.isInherited         = $ii
        $this.Permissions         = $p
        $this.OriginalPermissions = $op
    }# Permission([System.String]$pt, [System.String]$pn, [System.String]$prt, [System.String]$prn, `
}# class Permission

# class to hold DataVaultCredential
class DataVaultCredential
{
    [System.String]$Username
    [System.String]$Password
    [System.String]$Target
    [System.String]$Template
    [Permission[]]$Permissions
    [System.String]$PASUUID
    [System.Collections.Hashtable]$Slugs

    DataVaultCredential([System.String]$u, [System.String]$p, [System.String]$t, `
                        [System.String]$tm, [Permission[]]$pr, [System.String]$i, `
                        [System.Collections.Hashtable]$s)
    {
        $this.Username    = $u
        $this.Password    = $p
        $this.Target      = $t
        $this.Template    = $tm
        $this.Permissions = $pr
        $this.PASUUID     = $i
        $this.Slugs       = $s
    }# DataVaultCredential([System.String]$u, [System.String]$p, [System.String]$t, `
}# class DataVaultCredential

# class to hold a MigratedCredential
class MigratedCredential
{
    [System.String]$SecretTemplate
    [System.String]$SecretName
    [System.String]$Target
    [System.String]$Username
    [System.String]$Password
    [System.String]$Folder
    [System.Boolean]$hasConflicts
    [System.String]$PASDataType
    [System.String]$PASUUID
    [System.Collections.ArrayList]$memberofSets = @{}
    [System.Collections.ArrayList]$Permissions = @{}
    [System.Collections.ArrayList]$FolderPermissions = @{}
    [System.Collections.ArrayList]$SetPermissions = @{}
    [System.Collections.Hashtable]$Slugs
    [PSObject]$OriginalObject

    MigratedCredential() {}

    MigratedCredential($obj)
    {
        if ($obj.GetType().Name -eq "PlatformAccount")      { $this.createFromPlatformAccount($obj) }
        if ($obj.GetType().Name -eq "DataVaultCredential")  { $this.createFromDataVaultCredential($obj) }
        #if ($obj.OriginalObject.ToString() -eq "PlatformAccount") { $this.createFromPlatformAccount($obj) }
        #if ($obj.OriginalObject.ToString() -eq "DataVaultCredential") { $this.createFromDataVaultCredential($obj) }
    }

    createFromPlatformAccount($pa)
    {
        # placeholder to determine target
        [System.String]$FQDN = $null

        switch ($pa.AccountType)
        {
            'Local' 
            {
                $query = Query-VaultRedRock -SQLQuery ("Select FQDN FROM Server WHERE ID = '{0}'" -f $pa.SourceID)
                if ($pa.ComputerClass -eq "Windows") { $this.SecretTemplate = "Windows Account" }
                if ($pa.ComputerClass -eq "Unix")    { $this.SecretTemplate = "Unix Account (SSH)" }
                $FQDN = $query.FQDN
                break
            }
            'Domain'
            {
                $this.SecretTemplate = "Active Directory Account"
                $FQDN = $pa.SourceName
                break
            }
            'Database'
            {
                # this requires extrachecking DatabaseClass and ID from VaultDatabase table
                $query = Query-VaultRedRock -SQLQuery ("SELECT FQDN,DatabaseClass FROM VaultDatabase WHERE ID = '{0}'" -f $pa.SourceID)
                
                switch ($query.DatabaseClass)
                {
                    'Oracle'    { $this.SecretTemplate = "Oracle Account"; break}
                    'SAPAse'    { $this.SecretTemplate = "SAP Account"; break }
                    'SQLServer' { $this.SecretTemplate = "SQL Server Account"; break }
                }

                $FQDN = $query.FQDN
                break
            }
        }# switch ($pa.AccountType)

        # setting the Secret Name
        $this.SecretName = $pa.SSName

        $this.Target = $FQDN 
        $this.Username = $pa.Username
        $this.Password = $pa.Password

        $this.PASDataType = "VaultAccount"
        $this.PASUUID = $pa.ID

        # Permissions
        foreach ($rowace in $pa.PermissionRowAces)
        {
            $this.Permissions.Add((ConvertTo-SecretServerPermission -Type self -Name $pa.SSName -RowAce $rowace)) | Out-Null
        }

        $this.OriginalObject = $pa

        $this.getSetMemberships()
    }# MigratedCredential([PlatformAccount]$pa)

    createFromDataVaultCredential($dvc)
    {
        # setting the Secret Template
        $this.SecretTemplate = $dvc.Template

        # setting the Secret Name
        $this.SecretName = ("{0}\{1}" -f $dvc.Target, $dvc.Username)

        $this.Target = $dvc.Target 
        $this.Username = $dvc.Username
        $this.Password = $dvc.Password

        $this.PASDataType = "DataVault"
        $this.PASUUID = $dvc.PASUUID

        $this.Slugs = $dvc.Slugs

        foreach ($perms in $dvc.Permissions)
        {
            $this.Permissions.Add($perms) | Out-Null
        }
        
        $this.OriginalObject = $dvc

        $this.getSetMemberships()
    }# createFromDataVaultCredential($dvc)

    setFolder([System.String]$FolderName)
    {
        $this.Folder = $FolderName
    }

    getSetMemberships()
    {
        # if the SetBank exists, uses that for faster gets
        if ($global:SetBank -ne $null)
        {
            $memberof = $global:SetBank | Where-Object {$_.MemberIDs -contains $this.PASUUID}

            foreach ($member in $memberof)
            {
                $this.memberOfSets.Add((Get-PlatformSet -Uuid $member.SetID)) | Out-Null
            }
        }# if ($global:SetBank -ne $null)
        else # otherwise query it
        {
            $queries = Query-VaultRedRock -SQLQuery ("SELECT ID,Name FROM Sets WHERE ObjectType = '{0}' AND CollectionType = 'ManualBucket'" -f $this.PASDataType)

            foreach ($query in $queries)
            {
                $isMember = Invoke-PlatformAPI -APICall Collection/IsMember -Body ( @{ID=$query.ID; Table=$this.PASDataType; Key=$this.PASUUID} | ConvertTo-Json)

                if ($isMember)
                {
                    $this.memberOfSets.Add((Get-PlatformSet -Uuid $query.ID)) | Out-Null
                }
            }
        }# else
        $this.determineConflicts()
    }# getSetMemberships()

    determineConflicts()
    {
        # if this has membership in more than 1 Set
        if ($this.memberOfSets.Count -gt 1)
        {
            $this.hasConflicts = $true
        }
        else
        {
            $this.hasConflicts = $false
        }
    }# determineConflicts()

    SetSetPermissions($PlatformSet)
    {
        foreach ($rowace in $PlatformSet.PermissionRowAces)
        {
            $obj = ConvertTo-SecretServerPermission -Type Set -Name $PlatformSet.Name -RowAce $rowace

            $this.SetPermissions.Add($obj) | Out-Null
        }
    }# SetSetPermission($PlatformSet)

    SetFolderPermissions($PlatformSet)
    {
        foreach ($rowace in $PlatformSet.PermissionRowAces)
        {
            $obj = ConvertTo-SecretServerPermission -Type Folder -Name $PlatformSet.Name -RowAce $rowace

            $this.FolderPermissions.Add($obj) | Out-Null
        }
    }# SetFolderPermissions($PlatformSet)

    [System.Boolean] UnmanageAccount()
    {
        # if the account was successfully unmanaged
        if ($manageaccount = Invoke-PlatformAPI ServerManage/UpdateAccount -Body (@{ID=$this.PASUUID;User=$this.Username;SourceType=$this.OriginalObject.SourceID;IsManaged=$false}|ConvertTo-Json))
        {
            $this.isManaged = $false
            return $true
        }
        return $false
    }# [System.Boolean] UnmanageAccount()

    [System.Boolean] CheckOutPassword()
    {
        # if checkout is successful
        if ($checkout = Invoke-PlatformAPI -APICall ServerManage/CheckoutPassword -Body (@{ID = $this.PASUUID} | ConvertTo-Json))
        {   
            # set these checkout fields
            $this.Password = $checkout.Password
        }# if ($checkout = Invoke-PlatformAPI -APICall ServerManage/CheckoutPassword -Body (@{ID = $this.PASUUID} | ConvertTo-Json))
        else
        {
            return $false
        }
        return $true
    }# [System.Boolean] CheckOutPassword()

    # method to retrieve secret content
    [System.Boolean] RetrieveTextSecret()
    {
        # if checkout is successful
        if ($retrieve = (Invoke-PlatformAPI -APICall ServerManage/RetrieveSecretContents -Body (@{ ID = $this.PASUUID } | ConvertTo-Json) | Select-Object -ExpandProperty SecretText))
        {
            $this.Password = $retrieve
        }# if ($retrieve = Invoke-PlatformAPI -APICall ServerManage/RetrieveSecretContents -Body (@{ ID = $this.PASUUID } | ConvertTo-Json) | Select-Object -ExpandProperty SecretText)
        else
        {
            return $false
        }
        return $true
    }# [System.Boolean] RetrieveTextSecret()

    # rebuilds class from json data
    reSerialize([PSObject]$mc)
    {
        foreach ($property in $mc.PSObject.Properties) 
        {
            $this.("{0}" -f $property.Name) = $property.Value
        }
    }#>

    # print Permissions 
    [System.Collections.ArrayList] exportPermissions()
    {
        $exportedpermissions = New-Object System.Collections.ArrayList

        foreach ($perms in $this.Permissions)
        {
            $exportedpermissions.Add($perms) | Out-Null
        }

        foreach ($perms in $this.FolderPermissions)
        {
            $exportedpermissions.Add($perms) | Out-Null
        }

        foreach ($perms in $this.SetPermissions)
        {
            $exportedpermissions.Add($perms) | Out-Null
        }

        return $exportedpermissions
    }# [System.Collections.ArrayList] exportPermissions()

    exportToJson()
    {
        $this | ConvertTo-Json -Depth 10 | Out-File (".\{0}-{1}.json" -f $this.Target, $this.Username)
    }
}# class MigratedCredential

# class to hold a custom PlatformError
class PlatformAPIException : System.Exception
{
    [System.String]$APICall
    [System.String]$Payload
    [System.String]$ErrorMessage
    [PSCustomObject]$Response

    PlatformAPIException([System.String]$message) : base ($message) {}

    PlatformAPIException() {}
}# class PlatformAPIException : System.Exception

# class to hold a custom RowAce error
class PlatformRowAceException : System.Exception
{
    [PSCustomObject]$RowAce
    [PlatformPermission]$PlatformPermission
    [System.String]$ErrorMessage

    PlatformRowAceException([System.String]$message) : base ($message) {}

    PlatformRowAceException() {}
}# class PlatformRowAceException : System.Exception
#######################################
#endregion ############################
#######################################

# initializing a List[PlatformConnection] if it is empty or null
if ($global:PlatformConnections -eq $null) {$global:PlatformConnections = New-Object System.Collections.Generic.List[PlatformConnection]}

# if the script is local, save it as a variable (used in Get-PlatformObjects)
if (Test-Path -Path '.\PlatformPlus.ps1')
{
    $global:PlatformPlusScript = Get-Content .\PlatformPlus.ps1 -Raw
}
else # otherwise get the contents from the github repo
{
    $global:PlatformPlusScript = (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/DelineaPS/PlatformPlus/main/PlatformPlus.ps1').Content
}