#######################################################################
# Name: main.ps1
# Description: Retrieves basic capacity info for VMware clusters
# Created: 2024-March
# Author: Fabian Lenz comdivision
# Version: 1.0
#######################################################################

<#
.SYNOPSIS
This tool allows us to efficiently place workloads based on the operating system on dedicated hosts within a cluster (for license optimization)
.DESCRIPTION
This script uses DRS and workload analysis modules (WorkloadAnalysis.psm1) to determin for a given OS how many
ESXi hosts are required to run the workload (phase 1). 

.PARAMETER
ConfigFile Location to a configFile that contains all relevant data (vCenter; Operating systems; etc.)
credentialFile Location where the vCenter_server credential file is stored

.EXAMPLE
PS C:\> cd C:\automation\drs_placer
PS C:\> .\main.ps1
.NOTES
Author: Fabian Lenz
Date: 15/03/2024
#>

param(
    $ConfigFile = '.\globalConfig.JSON',
    $dryRun = $false,
    $Location = 'C:\automation\hostoptimizer',
    $credentialFile = "$Location\vCenter_credential.xml"
)

Import-Module .\modules\WorkloadAnalysis.psm1 -force

### Start Time
$timestamp = Get-Date -format "yyyy-MM-dd-hh.mm.ss"

### Log-Object-Data

$logFolder = "$Location\log"
$logobject = New-Object -TypeName PSObject -Property @{
    logFolder = $logFolder
    debugruntimeLog = $logFolder+'\debug_runtimeinfo.log'
    inforuntimeLog = $logFolder+'\info_runtimeinfo.log'
    reportFileFolder = '.\report\'
    reportFileName = ('hostoptimizer_'+$timestamp+'.csv')
    }


### Pre-run -> File & Folder verification & creation
If(!(Test-Path -Path (($logobject.logFolder)))){
    New-Item -Path $logFolder -Name "log" -ItemType "directory"
}

If(!(Test-Path -Path (($logobject.reportFileFolder)))){
    New-Item -Path ($logobject.reportFileFolder) -Name "report" -ItemType "directory"
}
New-Item "$($logobject.reportFileFolder)\$($logobject.reportFileName)" -ItemType File
$reportMessage = "ClusterName;RequiredESXiHosts;ResourceDecision;allocatedMemory;allocatedCPU;vCpuCoreRatio;physicalAvailableCPUOnCluster;physicalCpuOnDRSGroup;vMempMemRatio;memoryFillRate;physicalAvailableMem;physicalMemOnDRSGroup;failoverHosts"
Add-Content -Path "$($logobject.reportFileFolder)\$($logobject.reportFileName)" -value $reportMessage | out-null

If(!(Test-Path -Path (($logobject.debugruntimeLog)))){
    "Create Log File" | Set-Content -Path ($logobject.debugruntimeLog) -force
}

If(!(Test-Path -Path (($logobject.debugruntimeLog)))){
    "Create Log File" | Set-Content -Path ($logobject.debugruntimeLog) -force
}

If(!(Test-Path -Path (($logobject.inforuntimeLog)))){
    "Create Log File" | Set-Content -Path ($logobject.inforuntimeLog) -force
}

### Load config file
$jsondata = Get-Content -Raw -Path $ConfigFile | ConvertFrom-Json

If(!(Test-Path -Path ($credentialFile))){
    ### Log
    $timestamp = (Get-Date -format "yyyy-MM-dd-hh.mm.ss")
    $logMessage = "Credential File does not exist. Will create one and ask for a prompt. Make sure the user is available and has the proper role on all vCenter on all vCenter Servers."
    $logMessage = "$timestamp : $logmessage"
    Add-Content -Path $logobject.debugruntimeLog -Value $logMessage
    ### Log
    $credential = Get-Credential
    $credential | Export-CliXml -Path $credentialFile
}

$credential = Import-Clixml -Path $credentialFile

### Output File Location
$outputFolder = '.\data'

$vCenters = $jsonData.vCenters
$clusters = $jsonData.Clusters
$vCpuCoreRatio = $jsonData.vCpuCoreRatio
$vMempMemRatio = $jsonData.vMempMemRatio
$memoryFillRate = $jsonData.memoryFillRate
$failoverHosts = $jsonData.failoverHosts


#### Phase 1
Foreach ($vCenter in $vCenters){
    $timestamp = (Get-Date -format "yyyy-MM-dd-hh.mm.ss")
    $logMessage = "Connecting to vCenter $vCenter"
    $logMessage = "$timestamp : $logmessage"
    Add-Content -Path $logobject.debugruntimeLog -Value $logMessage
    $ErrorActionPreference = "Stop"
    try{
        $vCenterCon = Connect-VIServer $vCenter -Credential $credential
    }
    catch{
        Remove-Item -Path $credentialFile
        $timestamp = (Get-Date -format "yyyy-MM-dd-hh.mm.ss")
        $logMessage = "Failure connecting to vCenter $vCenter. Verify that the file $credentialFile has the proper credentials & the proper permission exists on the vCenter"
        Write-host $logMessage
        $logMessage = "$timestamp : $logmessage"
        Add-Content -Path $logobject.debugruntimeLog -Value $logMessage
        break
    }
    $ErrorActionPreference = "Continue"

    if($vCenterCon){
        Foreach ($Cluster in $clusters){
            ### Create the proper Cluster Folder if not existing
            If(!(Test-Path -Path ("$outputfolder\$($Cluster)"))){
                New-Item -ItemType directory -Path "$outputfolder\$($Cluster)"
            }
            ### Log
            $timestamp = (Get-Date -format "yyyy-MM-dd-hh.mm.ss")
            $logMessage = "Optimizing Cluster $Cluster"
            $logMessage = "$timestamp : $logmessage"
            Add-Content -Path $logobject.debugruntimeLog -Value $logMessage
            ### Log
            $ClusterObj = get-cluster $Cluster
            
            ### Gather phase 1 information based on the Operating System
            ### Log
            $timestamp = (Get-Date -format "yyyy-MM-dd-hh.mm.ss")
            $logMessage = "Searching for Operating System $OS"
            $logMessage = "$timestamp : $logmessage"
            Add-Content -Path $logobject.debugruntimeLog -Value $logMessage
            ### Log
            $VMs = $ClusterObj | get-vm 
            If($VMs){
                $allocatedObject = Get-WorkloadAllocation -VMs $VMs
                $workloadVMs = Get-WorkloadNames -VMs $VMs

                ### Create Files that can be auditted / picked up by Phase 2 algorithm
                ### File structure is always 1. line: cluster 2. line: OS rest content
                $workloadVMs | Set-Content -Path "$outputfolder\$($Cluster)\$($OS)_workloadVMs" -force

                ### Log
                $timestamp = (Get-Date -format "yyyy-MM-dd-hh.mm.ss")
                $logMessage = "The following VMs are captured "
                $logMessage = "$timestamp : $logmessage"
                Add-Content -Path $logobject.debugruntimeLog -Value $logMessage
                Add-Content -Path $logobject.inforuntimeLog -Value $logMessage
                $logMessage = $workloadVMs
                $logMessage = "$timestamp : $logmessage"
                Add-Content -Path $logobject.debugruntimeLog -Value $logMessage
                Add-Content -Path $logobject.inforuntimeLog -Value $logMessage
                ### Log

                $suitableHosts = Get-SuitableHosts -allocatedObject $allocatedObject -clusterObj $clusterObj -vCpuCoreRatio $vCpuCoreRatio -vMempMemRatio $vMempMemRatio -memoryFillRate $memoryFillRate -failoverHosts $failoverHosts -logobject $logobject
                $suitableHosts | Set-Content -Path "$outputfolder\$($Cluster)\suitableHosts" -force

                ### Log
                $timestamp = (Get-Date -format "yyyy-MM-dd-hh.mm.ss")
                $logMessage = "The following ESXi host are required to run the existing VMs "
                Add-Content -Path $logobject.debugruntimeLog -Value $logMessage
                Add-Content -Path $logobject.inforuntimeLog -Value $logMessage
                $logMessage = $suitableHosts
                $logMessage = "$timestamp : $logmessage"
                Add-Content -Path $logobject.debugruntimeLog -Value $logMessage
                Add-Content -Path $logobject.inforuntimeLog -Value $logMessage
                ### Log
            }
               
        }

        #### Disconnect from all vCenters
        Disconnect-VIserver * -confirm:$false
    }
}








