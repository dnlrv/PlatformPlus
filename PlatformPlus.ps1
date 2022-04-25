#######################################
#region ### MAJOR FUNCTIONS ###########
#######################################

###########
#region ### Verify-PlatformConnection # Check to ensure you are connected to the tenant before proceeding.
###########
function global:Verify-PlatformConnection
{
    if ($PlatformConnection -eq $null)
    {
        Write-Host ("There is no existing `$PlatformConnection. Please use Connect-DelineaPlatform to connect to your Delinea tenant. Exiting.")
        break
    }
}# function global:Verify-PlatformConnection
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
    param
    (
		[Parameter(Mandatory = $true, HelpMessage = "The SQL query to make.")]
		[System.String]$SQLQuery
    )

    # verifying an active platform connection
    Verify-PlatformConnection

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
#region ### global:Get-PlatformSet # Gets a Platform Set object
###########
function global:Get-PlatformSet
{
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
        [System.String]$Uuid
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
#region ### global:Get-PlatformAccount # Gets a Platform Account object
###########
function global:Get-PlatformAccount
{
    [CmdletBinding(DefaultParameterSetName="All")]
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The type of Account to search.", ParameterSetName = "Type")]
        [ValidateSet("Local","Domain","Database","Cloud")]
        [System.String]$Type,

        [Parameter(Mandatory = $true, HelpMessage = "The name of the Source of the Account to search.", ParameterSetName = "Source")]
        [Parameter(Mandatory = $false, HelpMessage = "The name of the Source of the Account to search.", ParameterSetName = "Type")]
        [System.String]$SourceName,

        [Parameter(Mandatory = $true, HelpMessage = "The name of the Account to search.", ParameterSetName = "Name")]
        [Parameter(Mandatory = $false, HelpMessage = "The name of the Account to search.", ParameterSetName = "Type")]
        [System.String]$UserName,

        [Parameter(Mandatory = $true, HelpMessage = "The Uuid of the Account to search.",ParameterSetName = "Uuid")]
        [Parameter(Mandatory = $false, HelpMessage = "The name of the Account to search.", ParameterSetName = "Type")]
        [System.String]$Uuid
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
        [System.String]$Uuid
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
		[Parameter(ParameterSetName = "Interactive")]
		[System.String]$Url,
		
		[Parameter(Mandatory = $true, ParameterSetName = "Interactive", HelpMessage = "Specify the User login to use for the connection (e.g. CloudAdmin@oceanlab.my.centrify.com).")]
		[System.String]$User,

		[Parameter(Mandatory = $true, ParameterSetName = "OAuth2", HelpMessage = "Specify the OAuth2 Client ID to use to obtain a Bearer Token.")]
        [System.String]$Client,

		[Parameter(Mandatory = $true, ParameterSetName = "OAuth2", HelpMessage = "Specify the OAuth2 Scope Name to claim a Bearer Token for.")]
        [System.String]$Scope,

		[Parameter(Mandatory = $true, ParameterSetName = "OAuth2", HelpMessage = "Specify the OAuth2 Secret to use for the ClientID.")]
        [System.String]$Secret
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
        "Secret|DataVault" { $AceHash = @{ GrantSecret = 1; ViewSecret = 4; EditSecret  = 8; DeleteSecret = 64; RetrieveSecret = 65536} ; break }
        "Set"              { $AceHash = @{ GrantSet    = 1; ViewSet    = 4; EditSet     = 8; DeleteSet    = 64} ; break }
        "ManualBucket|SqlDynamic"    
                           { $AceHash = @{ GrantSet    = 1; ViewSet    = 4; EditSet     = 8; DeleteSet    = 64} ; break }
        "Phantom"          { $AceHash = @{ GrantFolder = 1; ViewFolder = 4; EditFolder  = 8; DeleteFolder = 64; AddFolder = 65536} ; break }
        "Server"           { $AceHash = @{ GrantServer = 1; ViewServer = 4; EditServer  = 8; DeleteServer = 64; AgentAuthServer = 65536; 
                                           ManageSessionServer = 128; RequestZoneRoleServer = 131072; AddAccountServer = 524288;
                                           UnlockAccountServer = 1048576; OfflineRescueServer = 2097152;  AddPrivilegeElevationServer = 4194304}; break }
        "Domain"           { $AceHash = @{ GrantAccount = 1; ViewAccount = 4; EditAccount = 8; DeleteAccount = 64; LoginAccount = 128; CheckoutAccount = 65536; 
                                           UpdatePasswordAccount = 131072; RotateAccount = 524288; FileTransferAccount = 1048576}; break }
        "Cloud"            { $AceHash = @{ GrantCloudAccount = 1; ViewCloudAccount = 4; EditVaultAccount = 8; DeleteCloudAccount = 64; UseAccessKey = 128;
                                           RetrieveCloudAccount = 65536} ; break }
        "Local|Account|VaultAccount" 
                           { $AceHash = @{ GrantAccount = 1; ViewAccount = 4; EditAccount = 8; DeleteAccount = 64; LoginAccount = 128;  CheckoutAccount = 65536; 
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
        $this.LastSync = $vault.LastSync
        $this.SyncInterval = $vault.SyncInterval
        $this.Username = $vault.Username
        $this.Url = $vault.Url
    }
}

# class to hold Accounts
class PlatformAccount
{
    [System.String]$AccountType
    [System.String]$SourceName
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

    PlatformAccount($account, [System.String]$t)
    {
       
        $this.AccountType = $t
        $this.SourceName = $account.Name

        # the tenant holds the source object's ID in different columns
        Switch ($this.AccountType)
        {
            "Database" { $this.SourceID = $account.DatabaseID; break }
            "Domain"   { $this.SourceID = $account.DomainID; break }
            "Local"    { $this.SourceID = $account.Host; break }
            "Cloud"    { $this.SourceID = $account.CloudProviderID; break }
        }

        $this.Username = $account.User
        $this.ID = $account.ID
        $this.isManaged = $account.IsManaged
        $this.Healthy = $account.Healthy
        $this.LastHealthCheck = $account.LastHealthCheck
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

    getPassword()
    {
    }

    verifyPassword()
    {
        Write-Debug ("Starting Password Health Check for {0}" -f $this.Username)
        $result = Invoke-PlatformAPI -APICall ServerManage/CheckAccountHealth -Body (@{"ID"=$this.ID} | ConvertTo-Json)
        $this.Healthy = $result
        Write-Debug ("Password Health: {0}" -f $result)
    }

}# class PlatformAccount

# class to hold Systems
class PlatformSystem 
{
    [System.String]$Name
    [System.String]$Description
    [System.String]$FQDN
    [System.String]$ComputerClass
    [System.String]$ID
    [System.String]$ProxyUser
    [System.Boolean]$ProxyUserIsManaged
    [System.Int32]$ActiveCheckouts
    [System.String]$DomainId
    [System.String]$ZoneStatus
    [System.Boolean]$UseDomainWorkflowApprovers
    [System.Boolean]$ZoneRoleWorkflowEnabled
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
        $this.ID = $system.ID
        $this.ProxyUser = $system.ProxyUser
        $this.ProxyUserIsManaged = $system.ProxyUserIsManaged
        $this.ActiveCheckouts = $system.ActiveCheckouts
        $this.DomainId = $system.DomainId
        $this.ZoneStatus = $system.ZoneStatus
        $this.UseDomainWorkflowApprovers = $system.UseDomainWorkflowApprovers
        $this.ZoneRoleWorkflowEnabled = $system.ZoneRoleWorkflowEnabled
        $this.AgentVersion = $system.AgentVersion
        $this.OperatingSystem = $system.OperatingSystem
        $this.Reachable = $system.Reachable
        $this.LastState = $system.LastState
        $this.HealthStatusError = $system.HealthStatusError
        $this.ReachableError = $system.ReachableError
        $this.LastHealthCheck = $system.LastHealthCheck
        
        # getting the RowAces for this System
        $this.PermissionRowAces = Get-PlatformRowAce -Type "SERVER" -Uuid $this.ID
    }# PlatformSystem($system)

    getAccounts()
    {
        $this.PlatformAccounts = Get-PlatformAccount -Type Local -SourceName $this.Name
    }
}# class PlatformSystem

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
