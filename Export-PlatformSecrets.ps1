<# Export-PlatformSecrets.ps1
##
## Version: 1.0.00 BN 001 (01/21/2022) Initial release
#>

<#
.SYNOPSIS
This script obtains all the Secrets registered to a PAS tenant. It can also
retrieve and download all Secrets to the current directory.

.DESCRIPTION
This script will obtain information regarding Secrets to a connected PAS tenant. In 
addition, this script can provide two options to Retrieve the Contents of Text 
Secrets, and download File Secrets. These are separate actions by design due to
possible sensitive information that may be stored in these Secrets.

This script has several requirements:
 - An active $PlatformConnection via Connect-CentrifyPlatform
 - The PlatformPlus.ps1 script

This script will also produce two .manifest files:
 - A PlatformSecrets.manifest file - this file contains all the metadata about
   the Secrets. Can be imported back into PowerShell with ConvertFrom-Json.
 - A PrincipalList.csv file - this lists contains all the unique Principals
   that have permissions on all the Secret objects. This is useful to check
   before importing that the relevant Principal exists.

.PARAMETER RetrieveSecrets
This will cause the script to Retrieve the contents of Text Secrets and store it
in memory. For File Secrets it will prepare the special download URL, but not
store it locally until -ExportSecrets is used.

.PARAMETER ExportSecrets
This will cause the script to export the contents of Text Secrets as a text file
following the same folder hieracrhy as how it was stored in the tenant. For File
Secrets, it will download that file (using the special download URL prepared in
-Retrieve Secrets) to the same folder as how it was stored in the tenant.

.PARAMETER Version
Show version of this script.

.PARAMETER Help
Show usage for this script.

.INPUTS
None. You can't redirect or pipe input to this script.

.OUTPUTS
This script outputs files and a $PlatformSecrets object.

.EXAMPLE
C:\PS> .\Export-PlatformSecrets.ps1
This script will get all Secrets that are registered in the PAS tenant. It 
will also create the same Folder structure as it exists in the tenant.

.EXAMPLE
C:\PS> .\Export-PlatformSecrets.ps1 -RetrieveSecrets
This script will perform a RetrieveSecret action on all Text Secrets and
store the information in the $PlatformSecrets objects. For File Secrets it 
will prepare the special file download URL to download the file.

.EXAMPLE
C:\PS> .\Export-PlatformSecrets.ps1 -ExportSecrets
This script will download all File Secrets that have been prepared with the 
-RetrieveSecrets parameter. It will also create .txt files of all Text Secrets
starting in the current directory. 

.EXAMPLE
C:\PS> .\Export-PlatformSecrets.ps1 -Version
Displays the current version of the script.

.EXAMPLE
C:\PS> .\Export-PlatformSecrets.ps1 -Help
Displays what you are seeing now.
#>

#######################################
#region ### PARAMETERS ################
#######################################
[CmdletBinding(DefaultParameterSetName="Default")]
Param
(
    #region ### General Parameters ###

    ### Validators ###
    #[ValidateScript({If (-Not (Test-Path -Path ($_))) {Throw "The specified file does not exist. Please enter the name of the file."} Else { $true } })]
    #[ValidateNotNullOrEmpty()]

    [Parameter(Mandatory = $true, HelpMessage = "Retrieve contents of secrets in `$PlatformSecrets.", ParameterSetName="Retrieve")]
    [Alias("r")]
    [Switch]$RetrieveSecrets,

    [Parameter(Mandatory = $true, HelpMessage = "Display the version of the script.", ParameterSetName="Export")]
    [Alias("e")]
    [Switch]$ExportSecrets,

    [Parameter(Mandatory = $true, HelpMessage = "Display the version of the script.", ParameterSetName="Version")]
    [Alias("v")]
    [Switch]$Version,

    [Parameter(Mandatory = $true, HelpMessage = "Display extra help.", ParameterSetName="Help")]
    [Alias("?")]
    [Alias("h")]
    [Switch]$Help
    #endregion

)# Param

#######################################
#endregion ############################
#######################################

#######################################
#region ### VERSION NUMBER and HELP ###
#######################################
[System.String]$VersionNumber = (Get-Content ($MyInvocation.MyCommand).Name)[2]

# print the version number if -Version was used and exit
if ($Version.IsPresent)
{
	Write-Host ("{0} ({1})`n" -f ($MyInvocation.MyCommand).Name,$VersionNumber)
	Exit 0 # EXITCODE 0 : Successful execution
}

# 
if ($Help.IsPresent)
{
	Invoke-Expression -Command ("Get-Help .\{0} -Full" -f ($MyInvocation.MyCommand).Name)
	Exit 0 # EXITCODE 0 : Successful execution
}
#######################################
#endregion ############################
#######################################

#######################################
#region ### PREPIFY ###################
#######################################

# Setting TLS 1.2 as the standard
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ensuring required PlatformPlus.ps1 script is included
if (Test-Path -Path .\PlatformPlus.ps1)
{
    # include the PlatformPlus.ps1 script
    . .\PlatformPlus.ps1
}
else
{
    # quit as the required script was not found
    Write-Host ("The PlatformPlus.ps1 script was not found in this directory. Ensure that it is in the same directory as this script. Exiting.")
    Exit 1 # EXITCODE 1 : PlatformPlus.ps1 script not found.
}

# if -RetreiveSecrets or -ExportSecrets was used, ensure $PlatformSecrets exists and isn't $null
if ($RetrieveSecrets.IsPresent -or $ExportSecrets.IsPresent)
{
    if ($global:PlatformSecrets -eq $null)
    {
        Write-Host ("`$PlatformSecrets is `$null. Please run this script first without any parameters.")
        Exit 2 # EXITCODE 2 : $PlatformSecrets is null.
    }
}# if ($RetrieveSecrets.IsPresent -or $ExportSecrets.IsPresent)

#######################################
#endregion ############################
#######################################

#######################################
#region ### MAIN ######################
#######################################

# if -RetrieveSecrets was used
if ($RetrieveSecrets.IsPresent)
{
    Write-Host ("Total number of PlatformSecrets: [{0}]" -f $global:PlatformSecrets.Count)

	# for each secret in $PlatformSecrets
    foreach ($platformsecret in $global:PlatformSecrets)
    {
        Try # to retrieve the secret
        {
            Write-Host ("Getting Secret contents for {0} Secret: [{1}\{2}] ... " -f $platformsecret.Type, $platformsecret.ParentPath, $platformSecret.Name) -NoNewline
            $platformsecret.RetrieveSecret()
            Write-Host ("Done!") -ForegroundColor Green
        }
        Catch
        {
            Write-Host ("Error!") -ForegroundColor Red
            Write-Error $_.Exception
        }
    }# foreach ($platformsecret in $global:PlatformSecrets)

    Exit 0 # EXITCODE 0 : Successful execution
}# if ($RetrieveSecrets.IsPresent)

# if -ExportSecrets was used
if ($ExportSecrets.IsPresent)
{
    Write-Host ("Total number of PlatformSecrets: [{0}]" -f $global:PlatformSecrets.Count)

    foreach ($platformsecret in $global:PlatformSecrets)
    {
        Try # to export the secret
        {
            Write-Host ("Exporting Secret contents for {0} Secret: [{1}\{2}] ... " -f $platformsecret.Type, $platformsecret.ParentPath, $platformSecret.Name) -NoNewline
            $platformsecret.ExportSecret()
            Write-Host ("Done!") -ForegroundColor Green
        }
        Catch
        {
            Write-Host ("Error!") -ForegroundColor Red
            Write-Error $_.Exception
        }
    }# foreach ($platformsecret in $global:PlatformSecrets)

    Exit 0 # EXITCODE 0 : Successful execution
}# if ($RetrieveSecrets.IsPresent)

Write-Verbose ("Getting the DataVault objects")
# getting all DataVault (Secrets) objects, including folders.
$DataVaultObjects = Query-VaultRedRock -SQLQuery "SELECT * FROM DataVault"

Write-Verbose ("Reducing the Get to the Folders")
# getting all the folders, skipping the first one since it will be the root path
$SecretFolders = $DataVaultObjects | Select-Object -ExpandProperty ParentPath -Unique | Select-Object -Skip 1 | Sort-Object

Write-Verbose ("Verifying the path of folders...")
# making the folders
foreach ($folder in $SecretFolders)
{
    # if the folder doesn't exist
    if ((Test-Path -Path $folder) -ne $true)
    {
        Try # to make it
        {
            Write-Host ("Creating folder [{0}] ... " -f $folder) -NoNewline
            New-Item -ItemType Directory -Name $folder | Out-Null
            Write-Host ("Done!") -ForegroundColor Green
        }
        Catch
        {
            Write-Host ("Error!") -ForegroundColor Red
            Write-Error $_.Exception
        }
    }# if (Test-Path -Path $folder -eq $false)
}# foreach ($folder in $SecretFolders)

# setting an ArrayList for a final product
$PlatformSecrets = New-Object System.Collections.ArrayList

Write-Verbose ("Working with Secrets now.")
# Now getting the Secrets
foreach ($datavaultobject in $DataVaultObjects)
{
    Write-Verbose ("On Secret [{0}] in [{1}]" -f $datavaultobject.SecretName, $datavaultobject.ParentPath)
    # placeholder object
    $platformsecret = $null

    # get the Secret by Uuid
    $platformsecret = Get-PlatformSecret -Uuid $datavaultobject.ID

    $PlatformSecrets.Add($platformsecret) | Out-Null
}# foreach ($datavaultobject in $DataVaultObjects)

Write-Verbose ("Exporting PlatformSecrets.manifest file.")
# exporting JSON format PlatformSecrets.manifest
$PlatformSecrets | ConvertTo-Json -Depth 5 | Out-File .\PlatformSecrets.manifest

Write-Verbose ("Exporting PrincipalList.manifest file.")
# exporting the principal list to check on import
$PlatformSecrets.RowAces | Select-Object -ExpandProperty PrincipalName,PrincipalType | Sort-Object PrincipalName -Unique | Export-Csv .\PrincipalList.csv -NoTypeInformation

# setting $PlatformSecrets as a global variable
$global:PlatformSecrets = $PlatformSecrets

Exit 0 # EXITCODE 0 : Successful execution

#######################################
#endregion ############################
#######################################