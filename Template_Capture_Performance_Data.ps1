<#
.SYNOPSIS
Capture performance metrics for a number of servers, simply using Get-Counter (Port 445 RPC) and store metrics in InfluxDB

.DESCRIPTION
The folder structure for this script is important.

.OUTPUTS
Log files and versbose loggging is present as the script runs. To review logs either use the console or view the
log files in C:\Windows\Temp or your custom log folder location.

.NOTES
If this process fails then contact should be made with Leee to remediate.

.parameter TBD
TBD

#>
#latest influx DB module - https://github.com/markwragg/PowerShell-Influx
$influxDB = "http://INFLUXDB-01.ctxlab.local:8086" #Influx database uri
$influDBToken = "##TOKEN##" #API token for InfluxDB
$testDuration = "14400" # Duration in seconds

#Latest Influx module is not signed
Set-ExecutionPolicy Bypass -Confirm:$false -Force

#Check if the module is installed
if (!(Import-Module -Name "Influx" -PassThru)) {
    Write-Host "The Influx module is not installed - please download from https://github.com/markwragg/PowerShell-Influx and place in C:\Program Files\WindowsPowerShell\Modules"
    Exit
}

#Change location to script root
Set-Location $PSScriptRoot

#Get a list of all configured machines
try {
    if (Test-Path ".\Machines.json") {
        $machines = $(Get-Content ".\Machines.json" | ConvertFrom-Json)
    } else {
        Throw "There has been an error loading your machine config file"
    }
} catch {
    Write-Host $_ -ForegroundColor Red
    Write-Host "Please check your machine config file has the correct syntax and is in the correct location" -ForegroundColor Red
    Exit
}

#Loop through the machines settings the template counters and launching the monitoring jobs
foreach ($machine in $machines) {
    try {
        #Extract the template and check existance
        if (test-path ".\$($machine.Performance_Template)") {
            $counters = $(Get-Content ".\$($machine.Performance_Template)" | ConvertFrom-Json).Counters
            $networkCapture = $machine.Capture_Network
        } else {
            Throw "There was an error locating the template referenced for machine $($machine.MachineName)"
        }        

        #Set the script block that will be sent to the machine
        $scriptBlock = {
            param (
                $influxDB,
                $influDBToken,
                $testDuration,
                $machine,
                $counters,
                $networkCapture
            )
                       
            #If network needs to be captured, grab the network details on the machines and capture the metrics
            if ($networkCapture -eq 1) {
                $adapterNames = Invoke-Command -ComputerName $($machine.MachineName) -ScriptBlock {Get-NetAdapter | Select -ExpandProperty InterfaceDescription | Select -First 1}
                $tempCounters = New-Object System.Collections.Generic.List[String]
                
                foreach ($counter in $counters) {
                    $tempCounters.Add($counter)
                }
            
                foreach ($adapter in $adapterNames) {                    
                    #Add network adapter info too
                    $tempCounters.Add("\network interface`($($adapter)`)\bytes sent/sec")
                    $tempCounters.Add("\network interface`($($adapter)`)\bytes received/sec")                        
                }
            }                    
            
            $counters = $tempCounters
            #$networkCapture
            #$counters
            #Start-Sleep -Seconds 30
            
            [int]$x = 0
            Do {
                $valuesList = Get-Counter -ComputerName $machine.MachineName -Counter $counters -SampleInterval 1           
                $Metrics = foreach ($counter in $valuesList.CounterSamples) {
                     $metricPlacement = $($counter.path.split("\").count-1)

                     #Is a Ram measurement
                     if (($counter.path -match "available bytes") -or ($counter.path -match "committed bytes")) {
                        @{
                            "Memory-$(($counter.path.split("\"))[$metricPlacement])/MB" = [math]::Round($counter.CookedValue,3) /1024 /1024
                        }
                     } elseif ($counter.path -match "network adapter") {
                        @{
                            "Network-$(($counter.path.split("\"))[$metricPlacement])/kb" = [math]::Round($counter.CookedValue,3) /1024
                        }
                     } else {
                        @{
                            $($counter.path.split("\"))[$metricPlacement] = [math]::Round($counter.cookedValue,2)
                        }
                    }
                }       
                

                foreach ($table in $metrics) {
                    Write-Influx -Measure Server -Tags @{Server=$machine.MachineName} -Metrics $table -Server $influxDB -Organisation LJC -Bucket Performance -Token $influDBToken
                }
                $x++
            } Until ($x -eq $testDuration)

        }

        #Start performance capture process for given VM
        Write-Host "Starting performance capture for $($machine.MachineName) using template $($machine.Performance_Template)"
        Start-Job -Name "$machine-job" -ScriptBlock $scriptBlock -ArgumentList $influxDB,$influDBToken,$testDuration,$machine,$counters,$networkCapture | Out-Null

    } catch {
        Write-Host _$ -ForegroundColor Red
        Write-Host "There was an error during the performance capture process of $($machine.MachineName)" -ForegroundColor Red
    }
}

#Wait for test to complete
Start-Sleep -seconds $testDuration

#Clear all Jobs
#Get-Job | Stop-Job ; Get-Job | Receive-Job ; Get-Job | Remove-Job
Get-Job | Stop-Job ; Get-Job | Remove-Job
