Param (
    [Parameter(Mandatory = $true)]
    [string]
    $AzureUserName,

    [string]
    $AzurePassword,

    [string]
    $AzureTenantID,

    [string]
    $AzureSubscriptionID,

    [string]
    $ODLID,

    [string]
    $DeploymentID,

    [string]
    $InstallCloudLabsShadow  
)

Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


# Disable Internet Explorer Enhanced Security Configuration
function Disable-InternetExplorerESC {
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0 -Force
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0 -Force
    Stop-Process -Name Explorer -Force
    Write-Host 'IE Enhanced Security Configuration (ESC) has been disabled.' -ForegroundColor Green
}

# Disable IE ESC
Disable-InternetExplorerESC

# Download the database backup file from the GitHub repo
Invoke-WebRequest 'https://raw.githubusercontent.com/microsoft/MCW-Migrating-SQL-databases-to-Azure/master/Hands-on%20lab/lab-files/Database/WideWorldImporters.bak' -OutFile 'C:\WideWorldImporters.bak'


# Wait a few minutes to allow the SQL Resource provider setup to start
Start-Sleep -Seconds 240.0

# Add snapins to allow use of the Invoke-SqlCmd commandlet
Add-PSSnapin SqlServerProviderSnapin100 -ErrorAction SilentlyContinue
Add-PSSnapin SqlServerCmdletSnapin100 -ErrorAction SilentlyContinue

# Define database variables
$ServerName = $env:ComputerName
$DatabaseName = 'WideWorldImporters'
$SqlMiUser = 'DemoUser'
$PasswordPlainText = 'Password.1234567890'
$PasswordSecure = ConvertTo-SecureString $PasswordPlainText -AsPlainText -Force
$PasswordSecure.MakeReadOnly()
$Creds = New-Object System.Management.Automation.PSCredential $SqlMiUser, $PasswordSecure
$Password = $Creds.GetNetworkCredential().Password

# Restore the WideWorldImporters database using the downloaded backup file
function Restore-SqlDatabase {
    $bakFileName = 'C:\' + $DatabaseName +'.bak'

    $RestoreCmd = "USE [master];
                   GO
                   RESTORE DATABASE [$DatabaseName] FROM DISK ='$bakFileName' WITH REPLACE;
                   GO"

    Invoke-SqlCmd -Query $RestoreCmd -QueryTimeout 3600 -Username $SqlMiUser -Password $Password -ServerInstance $ServerName
    Start-Sleep -Seconds 30
}

function Enable-ServiceBroker {
    $SetBrokerCmd = "USE [$DatabaseName];
                     GO
                     GRANT ALTER ON DATABASE:: $DatabaseName TO $SqlMiUser;
                     GO
                     ALTER DATABASE [$DatabaseName]
                     SET ENABLE_BROKER WITH ROLLBACK IMMEDIATE;
                     GO"

    Invoke-SqlCmd -Query $SetBrokerCmd -QueryTimeout 3600 -Username $SqlMiUser -Password $Password -ServerInstance $ServerName
}

function Config-SqlDatabaseLogin {
    $UserName = 'WorkshopUser'

    $CreateLoginCmd = "USE [master];
                       GO
                       CREATE LOGIN $UserName WITH PASSWORD = N'$Password';
                       GO"

    Invoke-SqlCmd -Query $CreateLoginCmd -QueryTimeout 3600 -Username $SqlMiUser -Password $Password -ServerInstance $ServerName

    $AddRoleCmd = "USE [master];
                   GO
                   EXEC sp_addsrvrolemember @loginame = N'$UserName', @rolename = N'sysadmin';
                   GO"

    Invoke-SqlCmd -Query $AddRoleCmd -QueryTimeout 3600 -Username $SqlMiUser -Password $Password -ServerInstance $ServerName

    $AssignUserCmd = "USE [$DatabaseName];
                      GO
                      IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$UserName')
                        BEGIN
                            CREATE USER [$UserName] FOR LOGIN [$UserName]
                            EXEC sp_addrolemember N'db_datareader', N'$UserName'
                        END;
                      GO"

    Invoke-SqlCmd -Query $AssignUserCmd -QueryTimeout 3600 -Username $SqlMiUser -Password $Password -ServerInstance $ServerName
}

# Restore the datasbase
Restore-SqlDatabase

# Restart the MSSQLSERVER service.
Stop-Service -Name 'MSSQLSERVER' -Force
Start-Service -Name 'MSSQLSERVER'


Sleep 10

$env:chocolateyUseWindowsCompression = 'true'
Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')) -Verbose
choco feature enable -n allowGlobalConfirmation
refreshenv

choco install dotnetfx -y -force

#Download the database backup file from the GitHub repo
Invoke-WebRequest 'https://raw.githubusercontent.com/microsoft/MCW-Migrating-SQL-databases-to-Azure/master/Hands-on%20lab/lab-files/Database/WideWorldImporters.bak' -OutFile 'C:\WideWorldImporters.bak'

#Download and install Data Mirgation Assistant
Invoke-WebRequest 'https://download.microsoft.com/download/C/6/3/C63D8695-CEF2-43C3-AF0A-4989507E429B/DataMigrationAssistant.msi' -OutFile 'C:\DataMigrationAssistant.msi'
Start-Process -file 'C:\DataMigrationAssistant.msi' -arg '/qn /l*v C:\dma_install.txt' -passthru | wait-process

    
    New-Item -ItemType directory -Path C:\LabFiles -force
  $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/AzureCreds.txt","C:\LabFiles\AzureCreds.txt")
    $WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/AzureCreds.ps1","C:\LabFiles\AzureCreds.ps1")


    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureUserNameValue", "$AzureUserName"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzurePasswordValue", "$AzurePassword"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureTenantIDValue", "$AzureTenantID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureSubscriptionIDValue", "$AzureSubscriptionID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "DeploymentIDValue", "$DeploymentID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
             
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureUserNameValue", "$AzureUserName"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzurePasswordValue", "$AzurePassword"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureTenantIDValue", "$AzureTenantID"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureSubscriptionIDValue", "$AzureSubscriptionID"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "DeploymentIDValue", "$DeploymentID"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"

    Copy-Item "C:\LabFiles\AzureCreds.txt" -Destination "C:\Users\Public\Desktop"


#Create C:\CloudLabs
    New-Item -ItemType directory -Path C:\CloudLabs\Validator -Force
    Invoke-WebRequest 'https://experienceazure.blob.core.windows.net/software/vm-validator/LegacyVMAgent.zip' -OutFile 'C:\CloudLabs\Validator\LegacyVMAgent.zip'
    Expand-Archive -LiteralPath 'C:\CloudLabs\Validator\LegacyVMAgent.zip' -DestinationPath 'C:\CloudLabs\Validator' -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory('C:\CloudLabs\Validator\LegacyVMAgent.zip','C:\CloudLabs\Validator')
    Set-ExecutionPolicy -ExecutionPolicy bypass -Force
    cmd.exe --% /c @echo off
    cmd.exe --% /c sc create "Spektra CloudLabs Legacy VM Agent" binpath= C:\CloudLabs\Validator\LegacyVMAgent\Spektra.CloudLabs.LegacyVMAgent.exe displayname= "Spektra CloudLabs Legacy VM Agent" start= auto
    cmd.exe --% /c sc start "Spektra CloudLabs Legacy VM Agent"



  #Download and Install edge
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile("http://go.microsoft.com/fwlink/?LinkID=2093437","C:\Packages\MicrosoftEdgeBetaEnterpriseX64.msi")
    sleep 5
    
    Start-Process msiexec.exe -Wait '/I C:\Packages\MicrosoftEdgeBetaEnterpriseX64.msi /qn' -Verbose 
    sleep 5
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("C:\Users\Public\Desktop\Azure Portal.lnk")
    $Shortcut.TargetPath = """C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"""
    $argA = """https://portal.azure.com"""
    $Shortcut.Arguments = $argA 
    $Shortcut.Save()

    #Disable Welcome page of Microsoft Edge:

    Set-Location hklm:
    Test-Path .\Software\Policies\Microsoft
    New-Item -Path .\Software\Policies\Microsoft -Name MicrosoftEdge
    New-Item -Path .\Software\Policies\Microsoft\MicrosoftEdge -Name Main
    New-ItemProperty -Path .\Software\Policies\Microsoft\MicrosoftEdge\Main -Name PreventFirstRunPage -Value "1" -Type DWORD -Force -ErrorAction SilentlyContinue | Out-Null

choco install azure-data-studio -y
Sleep 5
  
