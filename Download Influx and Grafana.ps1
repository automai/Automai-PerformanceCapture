#Download and Extract Grafana
[CmdletBinding()]Param(
    [Parameter(Mandatory=$false, HelpMessage = "The install location for the performance monitoring tools")]   
    $installFolder="C:\Temp",
    [Parameter(Mandatory=$false, HelpMessage = "The current date and time to be displayed in the name of the log files")]   
    $logLocation="C:\Windows\Temp",
    [Parameter(Mandatory=$false, HelpMessage = "The date format to be used for log files")]
    $dateFormat = "yyyy-MM-dd_HH-mm",
    [Parameter(Mandatory=$true, HelpMessage = "The organisation name to be displayed in Influx")]   
    $influxOrgName= "Performance",
    [Parameter(Mandatory=$true, HelpMessage = "The password for the influx admin account")]   
    $influxAdminPassword = "Password100"
)

#Fixed Variables
$DateForLogFileName = $(Get-Date -Format $dateFormat)

#Function for log file creation
Function Write-Log() {

    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true, HelpMessage = "The error message text to be placed into the log.")]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,

        [Parameter(Mandatory=$false, HelpMessage = "The error level of the event.")]
        [ValidateSet("Error","Warn","Info")]
        [string]$Level="Info",

        [Parameter(Mandatory=$false, HelpMessage = "Specify to not overwrite or overwrite the previous log file.")]
        [switch]$NoClobber
    )

    Begin
    {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        $VerbosePreference = 'Continue'
    }
    Process
    {
        # append the date to the $path variable. It will also append .log at the end
        $logLocation = $logLocation + "\performance_monitoring_install_" + $DateForLogFileName+".log"

        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
        If (!(Test-Path $logLocation)) {
            Write-Verbose "Creating $logLocation."
            New-Item $logLocation -Force -ItemType File
            }

        else {
            # Nothing to see here yet.
            }

        # Format Date for our Log File
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # Write message to error, warning, or verbose pipeline and specify $LevelText
        switch ($Level) {
            'Error' {
                Write-Error $Message
                $LevelText = 'ERROR:'
                }
            'Warn' {
                Write-Warning $Message
                $LevelText = 'WARNING:'
                }
            'Info' {
                Write-Verbose $Message
                $LevelText = 'INFO:'
                }
            }

        # Write log entry to $Path
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $logLocation -Append
    }
    End
    {
    }
}

Function Download-Grafana {
    param (
        [Parameter(Mandatory=$true)]   
        $outputFolder
    )
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "https://grafana.com/grafana/download?platform=windows"
        $downloadLink = $response.links | Where-Object {($_ -match "download") -and ($_ -match "windows") -and ($_ -match "zip")}

        if (!$null -eq $downloadLink) {
            #If the download link is populated, lets attempt a download
            $fileName = $downloadLink.href.split("/") | Select-Object -Last 1
            $output = Join-Path -Path $outputFolder -ChildPath $fileName
            Invoke-WebRequest -UseBasicParsing -Uri $downloadLink.href -OutFile $output
            if (Test-Path $output) {
                Write-Log -Message "Grafana was successfully downloaded" -Level Info
            } else {                
                Throw "There was an error downloading Grafana"
            }
            Write-Log -Message "Proceeding to decompress the grafana archive" -Level Info
            Expand-Archive -Path $output -DestinationPath $(Get-ChildItem $output).Directory -Force
            $folder = Get-ChildItem -Path $(Get-ChildItem $output).Directory | Where-Object {($_.PSIsContainer -eq $true) -and ($_.BaseName -match "grafana")}
            if ($folder) {
                Write-Log -Message "Grafana extracted successfully - ready for configuration" -Level Info
                $folderObj = [PSCustomObject]@{
                    rootFolder = $folder
                    exeLocation = Get-ChildItem $folder.FullName -Recurse | Where-Object {$_.Name -eq "grafana-server.exe"}
                }
                Write-Log -Message "Grafana executable located at $($folderObj.exeLocation.FullName)" -Level Info
                return $folderObj
            } else {                
                Throw "There was an error with the extraction of Grafana, perhaps it did not download or the download was no reliable"
            }
        } else {            
            Throw "No download link could be found"            
        }
    } catch {
        Write-Log -Message "$_" -Level Error
    }
}

#Download and Extract InfluxDB
Function Download-InfluxDB {
    param (
        [Parameter(Mandatory=$true)]
        $outputFolder
    )    
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/influxdata/influxdb/releases"
        $downloadLink = $($response.Links | Where-Object {$_ -match "amd64"} | Select-Object -First 1).href
        $configFile = "https://raw.githubusercontent.com/automai/Automai-PerformanceCapture/main/template_influx_config.json"

        if (!$null -eq $downloadLink) {
            #If the download link is populated, lets attempt a download
            $fileName = $downloadLink.split("/") | Select-Object -Last 1
            $output = Join-Path -Path $outputFolder -ChildPath $fileName
            Invoke-WebRequest -UseBasicParsing -Uri $downloadLink -OutFile $output
            if (Test-Path $output) {
                Write-Log -Message "Influx was successfully downloaded" -Level Info
            } else {                
                Throw "There was an error downloading InfluxDB"                
            }
            Write-Log -Message "Proceeding to decompress the influx archive" -Level Info
            Expand-Archive -Path $output -DestinationPath $(Get-ChildItem $output).Directory -Force
            $folder = Get-ChildItem -Path $(Get-ChildItem $output).Directory | Where-Object {($_.PSIsContainer -eq $true) -and ($_.BaseName -match "influx")}
            if ($folder) {
                Write-Log -Message "Influx extracted successfully - ready for configuration" -Level Info
                $folderObj = [PSCustomObject]@{
                    rootFolder = $folder
                    exeLocation = Get-ChildItem $folder.FullName -Recurse | Where-Object {$_.Name -eq "influxd.exe"}
                }
                Write-Log -Message "Influx executable located at $($folderObj.exeLocation.FullName)" -Level Info
                #Download config and place in the Influx location
                Write-Log -Message "Downloading Influx config file" -Level Info
                Invoke-WebRequest -UseBasicParsing -Uri $configFile -OutFile "$($folder.FullName)\config.json"
                if (Test-Path "$($folder.FullName)\config.json") {
                    Write-Log -Message "Config files downloaded successfully" -Level Info
                } else {
                    Write-Log -Message "The config file did not download successfully, this may cause an issue in certain circumstances" -Level Warn
                }
                
                return $folderObj
            } else {                
                Throw "There was an error with the extraction of Influx, perhaps it did not download or the download was no reliable"
            }
        } else {            
            Throw "No download link could be found"
        }
    } catch {
        Write-Log -Message $_ -Level Error
    }
}

#Download NSSM to run tools as a service
Function Download-NSSM {
    param (
        [Parameter(Mandatory=$true)]
        $outputFolder
    )    
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "https://nssm.cc/download"
        $downloadLink = "https://nssm.cc" + $($response.links | Where-Object {($_ -match "zip") -and ($_ -match "release") -and ($_ -notmatch "prerelease")} | Select-Object -Last 1).href


        if (!$null -eq $downloadLink) {
            #If the download link is populated, lets attempt a download
            $fileName = $downloadLink.split("/") | Select-Object -Last 1
            $output = Join-Path -Path $outputFolder -ChildPath $fileName
            Invoke-WebRequest -UseBasicParsing -Uri $downloadLink -OutFile $output
            if (Test-Path $output) {
                Write-Log -Message "NSSM was successfully downloaded" -Level Info
            } else {                
                Throw "There was an error downloading NSSM"                
            }
            Write-Log -Message "Proceeding to decompress the NSSM archive" -Level Info
            Expand-Archive -Path $output -DestinationPath $(Get-ChildItem $output).Directory -Force
            $folder = Get-ChildItem -Path $(Get-ChildItem $output).Directory | Where-Object {($_.PSIsContainer -eq $true) -and ($_.BaseName -match "nssm")}
            if ($folder) {
                Write-Log -Message "NSSM extracted successfully - ready for use" -Level Info
                $folderObj = [PSCustomObject]@{
                    rootFolder = $folder
                    exeLocation = Get-ChildItem $folder.FullName -Recurse | Where-Object {($_.Name -eq "nssm.exe") -and ($_.Directory -match "win64")}
                }
                Write-Log -Message "NSSM executable located at $($folderObj.exeLocation.FullName)" -Level Info
                return $folderObj
            } else {
                Throw "There was an error with the extraction of NSSM, perhaps it did not download or the download was no reliable"
            }
        } else {            
            Throw "No download link could be found"
        }
    } catch {
        Write-Log -Message $_ -Level Error
    }
}

#Configure Firewall Ports
Function Configure-FirewallPorts {
    param (
        [Parameter(Mandatory)]
        [ValidateSet("grafana","influx")]
        $name,
        [Parameter(Mandatory)]   
        $exeLocation
    )
    try {
        if ($(Get-NetFirewallRule -Name "$name*" -ErrorAction SilentlyContinue).count -eq 0) {
            Write-Host "No existing firewall rules found, performing addition of rules"
            if ($name -eq "grafana") {
                New-NetFirewallRule -Name "$($name)_UDP" -DisplayName "$($name)_UDP" -Enabled True -Profile Any -Direction Inbound -Action Allow -Protocol UDP -Program $exeLocation
                New-NetFirewallRule -Name "$($name)_TCP" -DisplayName "$($name)_TCP" -Enabled True -Profile Any -Direction Inbound -Action Allow -Protocol TCP -Program $exeLocation
            }
            if ($name -eq "influx") {
                New-NetFirewallRule -Name "$($name)_UDP" -DisplayName "$($name)_UDP" -Enabled True -Profile Any -Direction Inbound -Action Allow -Protocol UDP -Program $exeLocation
                New-NetFirewallRule -Name "$($name)_TCP" -DisplayName "$($name)_TCP" -Enabled True -Profile Any -Direction Inbound -Action Allow -Protocol TCP -Program $exeLocation
            }
        } else {
            Write-Host "Firewall rules already exist, removing and re-adding"
            if ($name -eq "grafana") {
                Get-NetFirewallRule -Name "$name*" | Remove-NetFirewallRule
                New-NetFirewallRule -Name "$($name)_UDP" -DisplayName "$($name)_UDP" -Enabled True -Profile Any -Direction Inbound -Action Allow -Protocol UDP -Program $exeLocation
                New-NetFirewallRule -Name "$($name)_TCP" -DisplayName "$($name)_TCP" -Enabled True -Profile Any -Direction Inbound -Action Allow -Protocol TCP -Program $exeLocation
            }
            if ($name -eq "influx") {
                Get-NetFirewallRule -Name "$name*" | Remove-NetFirewallRule
                New-NetFirewallRule -Name "$($name)_UDP" -DisplayName "$($name)_UDP" -Enabled True -Profile Any -Direction Inbound -Action Allow -Protocol UDP -Program $exeLocation
                New-NetFirewallRule -Name "$($name)_TCP" -DisplayName "$($name)_TCP" -Enabled True -Profile Any -Direction Inbound -Action Allow -Protocol TCP -Program $exeLocation
            }
        }    
    } catch {
        Write-Log -Message $_ -Level Error
    }
}

#Script to add an executable as a service
Function Install-Service {
    param (
        [Parameter(Mandatory=$true)]   
        $nssmExe,    
        [Parameter(Mandatory=$true)]   
        $serviceName,
        [Parameter(Mandatory=$false)]   
        $serviceDisplayName,
        [Parameter(Mandatory=$false)]   
        $serviceDescription,
        [Parameter(Mandatory=$false)]
        $executableFolder        
    )
    try {
        & $nssmExe Install $serviceName $executableFolder
        if (!(Get-Service $serviceName)) {
            Throw "The $serviceName does not exist and was not created properly, please review the event log to see what happened"
        } else {
            Write-Log -Message "Attempting to start the $serviceName service"
            Start-Service $serviceName
            if ($(Get-Service $servicename).Status -eq "Running") {
                Write-Log "The service $serviceName has now been started"
            } else {
                Throw "The service $serviceName failed to start, please review the event log to see what happened"
            }
        }
    } catch {
        Write-Log -Message $_ -Level Error
    }
}

#Initial Influx Setup
Function Configure-InfluxDB {
    param (
        [Parameter(Mandatory)]   
        $bucketName,
        [Parameter(Mandatory)]
        $orgName,
        [Parameter(Mandatory)]
        $newAdminPassword,
        [Parameter(Mandatory)]
        $retentionPeriod,
        [Parameter(Mandatory)]   
        $userName        
    )
    $checkSetup = "http://localhost:8086/api/v2/setup"
    $postSetup = "http://localhost:8086/api/v2/setup"

    try {
        $setupState = (Invoke-WebRequest -UseBasicParsing -Uri $checkSetup -Method Get).Content | ConvertFrom-Json | Select-Object -ExpandProperty allowed

        if ($setupState -ne "False") {
            Throw "Influx seems to already be configured, if this is a mistake or you are running a second time, delete the install directory and start again"
        } else {
            Write-Log "Influx is not configured, proceeding with configuration" -Level Info
            $configObject = [PSCustomObject]@{
                bucket = $bucketName
                org = $orgName
                password = $newAdminPassword
                retentionPeriodSeconds = $retentionPeriod
                username = $userName      
            }
            Write-Log "Sending initial configuration to Influx" -Level Info
            $postState = (Invoke-WebRequest -UseBasicParsing -uri $postSetup -Method Post -Body $($configObject | ConvertTo-Json)).Content | ConvertFrom-Json

            if ($postState.User.Status -eq "active") {
                Write-Log "Influx configuration have been successful"
            } else {
                Throw "There has been and error configuring Influx, please try deleting the install directory and running the script again"
            }
            return $postState
        }
    } catch {
        Write-Log $_ -Level Error
    }
}

Function Configure-Grafana {
    param (
        [Parameter(Mandatory)]   
        $influxOrg,
        [Parameter(Mandatory)]
        $authToken,
        [Parameter(Mandatory)]
        $grafanaFolder 
    )
    $datasourceDownload = "https://raw.githubusercontent.com/automai/Automai-PerformanceCapture/main/template_datasource.yml"    

    try {
        Write-Log -Message "Downloading grafana template datasource for influxDB" -Level Info
        Invoke-WebRequest -UseBasicParsing -Uri $datasourceDownload -OutFile "$($grafanaFolder)\conf\provisioning\datasources\influx_datasource.yml"
        if (Test-Path "$($grafanaFolder)\conf\provisioning\datasources\influx_datasource.yml") {
            Write-Log -Message "Grafana datasource downloaded successfully, proceeding to replace placeholders" -Level Info
                (Get-Content "$($grafanaFolder)\conf\provisioning\datasources\influx_datasource.yml").replace('##ORG##',$influxOrg).replace('##TOKEN##',$authToken) | Out-File "$($grafanaFolder)\conf\provisioning\datasources\influx_datasource.yml" -Force
        } else {
            Throw "There has been an error downloading the data source for Grafana, this may need to be done manually."
        }
    } catch {
        Write-Log $_ -Level Error
    }
}

Function Install-GrafanaDashboard {
    param (
        [Parameter(Mandatory)]   
        $installFolder
    )

    $dashboardDownload = "https://raw.githubusercontent.com/automai/Automai-PerformanceCapture/main/Template_Performance-Capture.json"
    try {
        Write-Log -Message "Downloading grafana template dashboard" -Level Info
        Invoke-WebRequest -UseBasicParsing -Uri $dashboardDownload -OutFile "$($installFolder)\template_Perfromance-Capture.json"
        if (Test-Path "$($installFolder)\template_Perfromance-Capture.json") {
            Write-Log -Message "Template dashboard downloaded successfully, proceeding to replace placeholders" -Level Info
            Write-Log -Message "Proceeding with Dashboard import for Grafana" -Level Info
            #Prepare Auth Headers
            $pair = "admin:admin"
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
            $base64 = [System.Convert]::ToBase64String($bytes)
            $basicAuthValue = "Basic $base64"
            $headers = @{ Authorization = $basicAuthValue }

            #First Get the Data Source UID
            $datasourceURI = "http://localhost:3000/api/datasources"
            $datasource = $(Invoke-WebRequest -Uri $datasourceURI -Method Get -Headers $headers -ContentType "application/json" -Verbose).content | ConvertFrom-Json

            #Replace all placeholders
            (Get-Content "$($installFolder)\template_Perfromance-Capture.json").replace('##HOSTNAME##',$($env:computername).replace('##UID##',$datasource.uid)) | Out-File "$($installFolder)\template_Perfromance-Capture.json" -Force

            #Import the dashboard
            $dashboardURI = "http://localhost:3000/api/dashboards/db"
            $inFile = "$($installFolder)\template_Perfromance-Capture.json"
            $importResult = Invoke-WebRequest -Uri $dashboardURI -Method Post -infile $infile -Headers $headers -ContentType "application/json"

        } else {
            Throw "There has been an error downloading the dashboard for Grafana, this may need to be done manually."
        }
    } catch {
        Write-Log -Message $_ -Level Error
    }
}
Function Configure-PerformanceCapture {
    param (
        [Parameter(Mandatory)]   
        $installFolder,
        [Parameter(Mandatory)]
        $authToken,
        [Parameter(Mandatory)]
        $influxOrg   
    )

    $templateMachinesDownload = "https://raw.githubusercontent.com/automai/Automai-PerformanceCapture/main/Template_Machines.json"
    $templatePerformanceScript = "https://raw.githubusercontent.com/automai/Automai-PerformanceCapture/main/Template_Capture_Performance_Data.ps1"
    $templateProfile = "https://raw.githubusercontent.com/automai/Automai-PerformanceCapture/main/Counters.json"

    try {
        Write-Log -Message "Download the machines template file"
        Invoke-WebRequest -UseBasicParsing -Uri $templateMachinesDownload -OutFile "$installFolder\Machines.json"
        if (Test-Path "$installFolder\Machines.json") {
            Write-Log -Message "Machines JSON files downloaded successfully" -Level Info
            $(Get-Content -Path "$installFolder\Machines.json").replace('##HOSTNAME##',"$env:computername") | Out-File "$installFolder\Machines.json" -Force
        } else {
            Write-Log "Machines JSON file could not be downloaded, this may need to be downloaded and edited manually" -Level Warn
        }

        Write-Log -Message "Download the performance capture script"
        Invoke-WebRequest -UseBasicParsing -Uri $templatePerformanceScript -OutFile "$installFolder\Capture_Performance_Data.ps1"
        if (Test-Path "$installFolder\Capture_Performance_Data.ps1") {
            Write-Log -Message "Performance Capture Script downloaded successfully" -Level Info
            $(Get-Content -Path "$installFolder\Capture_Performance_Data.ps1").replace('##TOKEN##',$authToken).replace('##HOSTNAME##',$env:computername).replace('##ORG##',$influxOrg) | Out-File "$installFolder\Capture_Performance_Data.ps1" -Force
        } else {
            Write-Log "Performance Capture Script file could not be downloaded, this may need to be downloaded and edited manually" -Level Warn
        }        
    } catch {
        Write-Log -Message $_ -Level Error
    }
    
    Write-Log -Message "Download the counters template file"
    Invoke-WebRequest -UseBasicParsing -Uri $templateProfile -OutFile "$installFolder\counters.json"
    if (Test-Path "$installFolder\counters.json") {
        Write-Log -Message "Counters JSON files downloaded successfully" -Level Info
        $(Get-Content -Path "$installFolder\counters.json") | Out-File "$installFolder\Counters.json" -Force
    } else {
        Write-Log "Counters JSON file could not be downloaded, this may need to be downloaded and edited manually" -Level Warn
    }
}

Function Download-InfluxModule {
    param (
        [Parameter(Mandatory)]   
        $installFolder
    )
    $influxModule = "https://github.com/markwragg/PowerShell-Influx/archive/refs/heads/master.zip"
    try {
        Write-Log "Downloading the Influx PowerShell Module that will feed Influx the performance data"
        Invoke-WebRequest -UseBasicParsing -Uri $influxModule -OutFile "$installFolder\influxmodule.zip"
        if (Test-Path "$installFolder\influxmodule.zip") {
            Write-Log -Message "Influx Module downloaded successfully" -Level Info
            Expand-Archive "$installFolder\influxmodule.zip" -DestinationPath "$installFolder\Influx_Module" -Force
            if (Test-Path "$installFolder\Influx_Module") {
                Write-Log -Message "Influx module extraced successfully" -Level Info
                if (Test-Path "$installFolder\Influx_Module\PowerShell-Influx-master\Influx") {
                    Copy-Item "$installFolder\Influx_Module\PowerShell-Influx-master\Influx" -Destination "C:\Program Files\WindowsPowerShell\Modules" -Recurse -Force
                } else {
                    Throw "Unable to find the Influx PowerShell module within the archive, please check or install manually"
                }
            } else {
                Throw "Unable to extract the Influx PowerShell module"
            }
        } else {
            Throw "The InfluxDB PowerShell module could not be downloaded"
        }
    } catch {
        Write-Log -Message $_ -Level Error
    }
}

###Main Script###
try {
    #Script start
    Write-Log -Message "### Script Start ###"

    #Create the folder if it does not exist
    if (!(Test-Path $installFolder)) {
        Write-Log -Message "Installation folder $installFolder not found, creating it" -Level Info
        New-Item -Path $installFolder -ItemType Directory -Force
    } else {
        Write-Log -Message "Installation folder $installFolder already exists, no need to create it" -Level Warn
    }

    #Download performance monitoring tools
    $grafanaFolder = Download-Grafana -outputFolder $installFolder
    $influxFolder = Download-InfluxDB -outputFolder $installFolder
    $nssmFolder = Download-NSSM -outputFolder $installFolder

    #Configure Grafana Firewall Rules
    Configure-FirewallPorts -name grafana -exeLocation $grafanaFolder.exeLocation.FullName
    #Configure Influx Firewall Rules
    Configure-FirewallPorts -name influx -exeLocation $influxFolder.exeLocation.FullName

    #Start and Configure
    #Install InfluxDB as a Service and Start
    Install-Service -nssmExe $nssmFolder.exeLocation.FullName -serviceName "InfluxDB Server" -serviceDisplayName "InfluxDB Server" -serviceDescription "Influx Database Server" -executableFolder $influxFolder.exeLocation.FullName

    #Configure Influx
    $configResult = Configure-InfluxDB -bucketName "Performance" -orgName $influxOrgName -newAdminPassword $influxAdminPassword -retentionPeriod 0 -userName "influx_admin"

    #Pre-Configure Grafana Datasource
    Configure-Grafana -influxOrg $influxOrgName -authToken $configResult.auth.token -grafanaFolder $grafanaFolder.rootFolder.FullName

    #Install Grafana as a Service and Start
    Install-Service -nssmExe $nssmFolder.exeLocation.FullName -serviceName "Grafana Server" -serviceDisplayName "Grafana Server" -serviceDescription "Grafana Server" -executableFolder $grafanaFolder.exeLocation.FullName   

    #Import Dashboard Template for Grafana
    Install-GrafanaDashboard -installFolder $installFolder

    #Download performance capture script
    Configure-PerformanceCapture -installFolder $installFolder -authToken $configResult.auth.token -influxOrg $influxOrgName
    
    #Download the influx powershell module
    Download-InfluxModule -installFolder $installFolder
} catch {
    Write-Log -Message "$_" -Level Error
    
    #Rollback steps in the event of an error
    Write-Log -Message "Rolling back changes made" -Level Warn
    
    if (Get-Service -Name "Grafana Server" -ErrorAction SilentlyContinue) {
        Stop-Service 'Grafana Server' -Force
        & $nssmFolder.exeLocation.FullName Remove "Grafana Server" confirm
    }

    if (Get-Service -Name "InfluxDB Server" -ErrorAction SilentlyContinue) {
        Stop-Service 'InfluxDB Server' -Force
        & $nssmFolder.exeLocation.FullName Remove "InfluxDB Server" confirm
    }

    $allItems = Get-ChildItem $installFolder

    $itemsToRemove = $allItems | Where-Object {($_.Name -match "Grafana") -or ($_.Name -match "Influx") -or ($_.Name -match "Nssm")}
    $itemsToRemove | Remove-Item -Recurse -Force
    Write-Log -Message "Changes rolled back" -Level Warn
}
#Script stop
Write-Log -Message "### Script Stop ###"

#Download performance capture script