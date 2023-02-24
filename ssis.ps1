Write-Host -BackgroundColor Black -ForegroundColor Yellow "##################### IMPORTANT: SSIS LAB BULD SCRIPT ######################################################"
Write-Host -BackgroundColor Black -ForegroundColor Yellow "This script will setup and install the SSIS Lab Databases."
Write-Host -BackgroundColor Black -ForegroundColor Yellow "IMPORTANT: Please only run after the build is complete"
Write-Host -BackgroundColor Black -ForegroundColor Yellow "############################################################################################################"

###############################################################################
# Set up and install AZ and SQL Modules used by this script
###############################################################################
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

Install-Module -Name Az -Force -AllowClobber

###############################################################################
# Connect to Azure with Subscription and Tenant
###############################################################################

Write-Host -BackgroundColor Black -ForegroundColor Yellow "Connecting Powershell to your Subscription......................................."
Connect-AzAccount

Write-Host -BackgroundColor Black -ForegroundColor Yellow "Setting Enviroment Varibales....................................................."
$subscriptionID = (Get-AzContext).Subscription.id
$subscriptionName = (Get-AzContext).Subscription.Name

if(-not $subscriptionID) {   `
    $subscriptionMessage = "There is no selected Azure subscription. Please use Select-AzSubscription to select a default subscription";  `
    Write-Warning $subscriptionMessage ; return;}  `
else {   `
    $subscriptionMessage = ("Targeting Azure subscription: {0} - {1}." -f $subscriptionID, $subscriptionName)}
Write-Host -BackgroundColor Black -ForegroundColor Yellow $subscriptionMessage

if ((read-host "Please ensure this is the correct subscription. Press a to abort, any other key to continue.") -eq "a") {Return;}
Write-Host -BackgroundColor Black -ForegroundColor Yellow "Continuing to build.................................................."

###############################################################################
# Set variables for storage account RG 
##############################################################################

$labrg = "Azure-Discover-RG-870849"


###############################################################################
# Setup Storage Account
###############################################################################

# First find and setup the Storage acocunt

# Setup Storage Conext
$StorageAccount = (get-AzStorageAccount -ResourceGroupName "$labrg").StorageAccountName  | Select-object -First 1
$StorageAccountKeys = Get-AzStorageAccountKey -ResourceGroupName "$labrg" -Name $StorageAccount
$Key0 = $StorageAccountKeys | Select-Object -First 1 -ExpandProperty Value
$Context = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $Key0

#Create Container Build
If(-not (Get-AzStorageContainer -Context $Context -Name build -ErrorAction Ignore)){
    $output = New-AzStorageContainer -Context $Context -Name build
}

#Create SASUri for Build Container
$storagePolicyName = “Build-Policy”
$expiryTime = (Get-Date).AddYears(1)

If(-not (Get-AzStorageContainerStoredAccessPolicy -Context $Context -Name build)){
    New-AzStorageContainerStoredAccessPolicy -Container build -Policy $storagePolicyName -Permission rwld -ExpiryTime $expiryTime -Context $Context -StartTime(Get-Date) 
}
$SASUri = (New-AzStorageContainerSASToken -Name "build" -FullUri -Policy $storagePolicyName -Context $Context)

#Copy Files from github to Local machine

$Temp = (Get-Item -Path Env:Temp).value + "\SQLHACK"
$output = md $Temp -ErrorAction Ignore

Write-Host -BackgroundColor Black -ForegroundColor Yellow "Copying Backups to Blob storage....................................................."

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest 'https://github.com/microsoft/MCW-Migrating-SQL-databases-to-Azure/blob/main/Hands-on%20lab/lab-files/Database/WideWorldImporters.bak?raw=true' -UseBasicParsing -OutFile "$temp\WideWorldImporters.bak" | Wait-Process

# Copy Files to Blob
cd $Temp
$output = Get-ChildItem -File -Recurse -Filter "*.bak" |  Set-AzStorageBlobContent -Container "build" -Context $Context -Force

###############################################################################
# Set Variables for SQLMI RG
##############################################################################
Write-Host -BackgroundColor Black -ForegroundColor Yellow "################################# BUILD ENVIROMENT #########################################################"
Write-Host -BackgroundColor Black -ForegroundColor Yellow "Please Enter the Admin username, password and SHARED resource groups used in the Build"
Write-Host -BackgroundColor Black -ForegroundColor Yellow "############################################################################################################"

$adminUsername = "contosoadmin"
$securePassword = "197032d3-64e7-46a3-aced-1923655c17ab" | ConvertTo-SecureString -AsPlainText -Force
$adminPassword = $securePassword
$SharedRG = "SQLMI-Shared-RG"

###############################################################################
# Find Managed Instance
###############################################################################
$sqlmiFDQN = (Get-AzSqlInstance -ResourceGroupName $SharedRG).FullyQualifiedDomainName  | Select-object -First 1

if ($sqlmiFDQN -eq $null) {Write-Host -BackgroundColor Red -ForegroundColor White "Managed Instance not found. Please check build to ensure all deployments have completed and retry. Aborting" ; Return;}
Write-Host -BackgroundColor Black -ForegroundColor Yellow "Found and targeting Managed Instance: $sqlmiFDQN"

if ((read-host "Please ensure this is the correct Managed Instance. Press a to abort, any other key to continue.") -eq "a") {Return;}
Write-Host -BackgroundColor Black -ForegroundColor Yellow "Continuing to build.................................................."

###############################################################################
# Restore Databases
###############################################################################
$Credentials = New-Object PSCredential $adminUsername, $adminPassword

Write-Host -BackgroundColor Black -ForegroundColor Yellow "################################# RESTOING DATABASES #######################################################"
Write-Host -BackgroundColor Black -ForegroundColor Yellow "SSIS Databases will be restored and CLR will be enabled on the Managed Instance"
Write-Host -BackgroundColor Black -ForegroundColor Yellow "############################################################################################################"

# Set SQL MI CLR
Write-Host -BackgroundColor Black -ForegroundColor Yellow "Attempting to enable CLR on the Managed Instance $sqlmiFDQN"
$Query = "EXEC sp_configure ""CLR Enabled"", 1; RECONFIGURE WITH OVERRIDE"
Invoke-Sqlcmd -ServerInstance $sqlmiFDQN -Database "master" -Query $Query -Username $adminUsername -Password $Credentials.GetNetworkCredential().Password
Write-Host -BackgroundColor Black -ForegroundColor Yellow "Complete."

# Set SQL MI Credential
$Query = "if not exists (select 1 from sys.credentials where name = '" + $SASUri.split('?')[0,2] + "') CREATE CREDENTIAL [" + $SASUri.split('?')[0,2] + "] WITH IDENTITY='Shared Access Signature', SECRET='" + $SASUri.split('?')[1,2] + "'"
Invoke-Sqlcmd -ServerInstance $sqlmiFDQN -Database "master" -Query $Query -Username $adminUsername -Password $Credentials.GetNetworkCredential().Password

# Restore Database 2008DW
Write-Host -BackgroundColor Black -ForegroundColor Yellow "Attempting restore WideWorldImporters database on Managed Instance $sqlmiFDQN"
$blob = (Get-AzStorageBlob -Container build -Context $Context -Blob 'WideWorldImporters.bak').ICloudBlob.Uri.AbsoluteUri
$Query = "if not exists (select 1 from sysdatabases where name = 'WideWorldImporters') RESTORE DATABASE [WideWorldImporters] FROM URL = '$blob'"
Invoke-Sqlcmd -ServerInstance $sqlmiFDQN -Database "master" -Query $Query -Username $adminUsername -Password $Credentials.GetNetworkCredential().Password
Write-Host -BackgroundColor Black -ForegroundColor Yellow "Complete."
