# Disable Internet Explorer Enhanced Security Configuration
function Disable-InternetExplorerESC {
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0 -Force
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0 -Force
    Stop-Process -Name Explorer -Force
    Write-Host 'IE Enhanced Security Configuration (ESC) has been disabled.' -ForegroundColor Green
}

# Force TLS 1.2 use instead of TLS 1.0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Disable IE ESC
Disable-InternetExplorerESC

# Download the database backup file from the GitHub repo
Invoke-WebRequest 'https://raw.githubusercontent.com/microsoft/MCW-Migrating-SQL-databases-to-Azure/master/Hands-on%20lab/lab-files/Database/WideWorldImporters.bak' -OutFile 'C:\WideWorldImporters.bak'

# Download and install Data Mirgation Assistant
# Invoke-WebRequest 'https://download.microsoft.com/download/C/6/3/C63D8695-CEF2-43C3-AF0A-4989507E429B/DataMigrationAssistant.msi' -OutFile 'C:\DataMigrationAssistant.msi'
# Start-Process -file 'C:\DataMigrationAssistant.msi' -arg '/qn /l*v C:\dma_install.txt' -passthru | wait-process

# Wait a few minutes to allow the SQL Resource provider setup to start
Start-Sleep -Seconds 240.0

# Add snapins to allow use of the Invoke-SqlCmd commandlet
Add-PSSnapin SqlServerProviderSnapin100 -ErrorAction SilentlyContinue
Add-PSSnapin SqlServerCmdletSnapin100 -ErrorAction SilentlyContinue

# Define database variables
$ServerName = $env:ComputerName
$DatabaseName = 'WideWorldImporters'
$SqlMiUser = 'DemoUser'
$PasswordPlainText = 'Pass@demo1234567'
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

# Enable the Service Broker functionality on the database
Enable-ServiceBroker

# Create the WorkshopUser user
Config-SqlDatabaseLogin
