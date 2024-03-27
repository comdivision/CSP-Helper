#######################################################################
# Name: WorkloadAnalysis.psm1
# Description: Retrieves basic capacity info for VMware clusters
# Created: 2024-March
# Author: Fabian Lenz comdivision
# Version: 1.0
#######################################################################

<#
.SYNOPSIS
This module includes all relevant functions for the host optimization

.DESCRIPTION
Based on the Operating System delivered a workload analysis takes place. On every cluster:
How many vCPUs & vMemory are currently allocated for that certain OS on the clusters?
Based on resource parameters like failoverhosts; vCPU:COre ratio & vMem:pMem ratio the number of physical resources required
to run the workload is calculated.
In the next step the proper ESXi hosts are selected based on their resourcec characteristics. The ESXi hosts are sorted by amount of cores first and their hostname second
to make sure the results remain deterministic

.NOTES
Author: Fabian Lenz
Date: 15/03/2024
#>


### This function calculates the allocated workload CPU/Memory for any VM that is configured with a certain Guest OS.
### Returns: Object including total vCPU & vMemory required
function Get-WorkloadNames{
    Param(
	[parameter(Mandatory=$true)]$VMs
    )

    return $VMs.name
}


### This function calculates the allocated workload CPU/Memory for any VM that is configured with a certain Guest OS.
### Returns: Object including total vCPU & vMemory required
function Get-WorkloadAllocation{

	Param(
    [parameter(Mandatory=$true)]$VMs
    )

    #$VMs = get-vm | where {$_.ExtensionData.Guest.GuestFullName -match $OsDefinition}

    $TotalMemoryAllocated = (($VMs.MemoryGB) | Measure-Object -sum).sum
    $TotalvCPUAllocated = (($VMs.numcpu) | Measure-Object -sum).sum

    if(!$TotalMemoryAllocated){$TotalMemoryAllocated = 0}
    if(!$TotalvCPUAllocated){$TotalvCPUAllocated = 0}

    $allocatedObject = New-Object -TypeName PSObject -Property @{
        TotalMemoryAllocated = $TotalMemoryAllocated
        TotalvCPUAllocated = $TotalvCPUAllocated
        }

    return $allocatedObject

}

#### This function calculates based on an allocatedObject the number ESXi Hosts that are required to run the workload.
#### This function returns a list of concrete ESXi hosts that can run the defined workload
function Get-SuitableHosts{

	Param(
    [parameter(Mandatory=$true)] $allocatedObject,
    [parameter(Mandatory=$true)] $clusterObj,
    [parameter(Mandatory=$false)] $vCpuCoreRatio = 2,
    [parameter(Mandatory=$false)] $vMempMemRatio = 1,
    [parameter(Mandatory=$false)] $memoryFillRate = 0.8,
    [parameter(Mandatory=$false)] $failoverHosts = 1,
    [parameter(Mandatory=$false)] $OS,
    [parameter(Mandatory=$true)] $logObject
    )

    ### Sort number of hosts via Amount of Cores first & Name second
    $ESXObjs = $clusterObj | Get-VMHost | Where {$_.PowerState -match 'PoweredOn'} | Sort-Object -Property NumCPU,name

    $HostBasedOnMemory = Get-HostBasedOnMemory -ESXObjs $ESXObjs -allocatedMemory ($allocatedObject.TotalMemoryAllocated) -vMempMemRatio $vMempMemRatio -memoryFillRate $memoryFillRate -failoverHosts $failoverHosts
    $HostBasedOnCPU = Get-HostBasedOnCPU -ESXObjs $ESXObjs -allocatedCPU ($allocatedObject.TotalvCPUAllocated) -vCpuCoreRatio $vCpuCoreRatio -failoverHosts $failoverHosts

    #### Write Data into report log
    $clustername = $clusterObj.Name
    $allocatedMemory = $allocatedObject.TotalMemoryAllocated
    $allocatedCPU = $allocatedObject.TotalvCPUAllocated
    $availableCPU = ($ESXObjs.ExtensionData.Hardware.CpuInfo.NumCpuCores | measure -sum).sum
    $availableMemory = ($ESXObjs.MemoryTotalGB | measure -sum).sum
    ### Round to a whole number
    $availableMemory = [Math]::Round($availableMemory, 0)

    #### The resource where more hosts are required (the constraint)) must be taken into considerations. -> Array with more element wins
    If(($HostBasedOnCPU.count) -gt ($HostBasedOnMemory.count)){
        $logMessage = "ESXi Hosts Calculation are based on CPU Resources"
        Add-Content -Path $logobject.debugruntimeLog -Value $logMessage
        ### Get Physical resource
        #$drsVmHost = get-vmhost $HostBasedOnCPU
        $drsCpuCapacity = ($HostBasedOnCPU.ExtensionData.Hardware.CpuInfo.NumCpuCores | measure -sum).sum
        $drsMemCapacity = ($HostBasedOnCPU.MemoryTotalGB | measure -sum).sum
        $drsMemCapacity = [Math]::Round($drsMemCapacity, 0)
        ### Report
        $count = $HostBasedOnCPU.count
        $ResourceDecision = "CPU"
        $reportMessage = "$ClusterName;$count;$ResourceDecision;$allocatedMemory;$allocatedCPU;$vCpuCoreRatio;$availableCPU;$drsCpuCapacity;$vMempMemRatio;$memoryFillRate;$availableMemory;$drsMemCapacity;$failoverHosts"
        Add-Content -Path "$($logobject.reportFileFolder)\$($logobject.reportFileName)" -Value $reportMessage

        return $HostBasedOnCPU
    }
    else{
        $logMessage = "ESXi Hosts Calculation are based on Memory Resources"
        Add-Content -Path $logobject.debugruntimeLog -Value $logMessage
        ### Get Physical resource
        #$drsVmHost = get-vmhost $HostBasedOnMemory
        $drsCpuCapacity = ($HostBasedOnMemory.ExtensionData.Hardware.CpuInfo.NumCpuCores | measure -sum).sum
        $drsMemCapacity = ($HostBasedOnMemory.MemoryTotalGB | measure -sum).sum
        $drsMemCapacity = [Math]::Round($drsMemCapacity, 0)
        ### Report
        $count = $HostBasedOnMemory.count
        $ResourceDecision = "Memory"
        $reportMessage = "$ClusterName;$count;$ResourceDecision;$allocatedMemory;$allocatedCPU;$vCpuCoreRatio;$availableCPU;$drsCpuCapacity;$vMempMemRatio;$memoryFillRate;$availableMemory;$drsMemCapacity;$failoverHosts"
        Add-Content -Path "$($logobject.reportFileFolder)\$($logobject.reportFileName)" -Value $reportMessage

        return $HostBasedOnMemory
    }


}

function Get-HostBasedOnMemory{

	Param(
    [parameter(Mandatory=$true)] $ESXObjs,
    [parameter(Mandatory=$true)] $allocatedMemory,
    [parameter(Mandatory=$true)] $vMempMemRatio,
    [parameter(Mandatory=$true)] $memoryFillRate,
    [parameter(Mandatory=$true)] $failoverHosts
    )

    $totalMemoryCapacity = 0
    $MemoryESXiList = New-Object System.Collections.ArrayList

    ### Counter for taken ESXi hosts -> used for failover extension
    $usedESXi = 0

    ### Adding hosts to the list until Host-Capacity is higher than allocated capacity

    Foreach ($ESX in $ESxObjs){

        ### Including spare-capacity metrics
        $hostMemoryCapacity = $memoryFillRate * ($ESX.MemoryTotalGb) * $vMempMemRatio
        $totalMemoryCapacity = $totalMemoryCapacity + $hostMemoryCapacity
        $MemoryESXiList.Add($esx) | out-null
        $usedESXi++
        If($totalMemoryCapacity -gt $allocatedMemory)
        {
            break
        }
    }

    ### Add failover Capacity

    If($failoverHosts -ne 0){
        $i = 0
        $usedESXi++
        while ($i -lt $failoverHosts){
            $MemoryESXiList.Add($ESXObjs[$usedESXi]) | out-null
            $usedESXi++
            $i++
        }
    }

    ### Create a CSV File with the relevant information


    return $MemoryESXiList

}

function Get-HostBasedOnCPU{

	Param(
    [parameter(Mandatory=$true)] $ESXObjs,
    [parameter(Mandatory=$true)] $allocatedCPU,
    [parameter(Mandatory=$true)] $vCpuCoreRatio,
    [parameter(Mandatory=$true)] $failoverHosts
    )

    $totalCpuCapacity = 0
    $CpuESXiList = New-Object System.Collections.ArrayList

    ### Counter for taken ESXi hosts -> used for failover extension
    $usedESXi = 0

    ### Adding hosts to the list until Host-Capacity is higher than allocated capacity

    Foreach ($ESX in $ESxObjs){
        ### Including spare-capacity metrics
        $hostCPUCapacity = ($ESX.NumCpu) * $vCpuCoreRatio
        $totalCpuCapacity = $totalCpuCapacity + $hostCPUCapacity
        $CpuESXiList.Add($esx) | out-null
        $usedESXi++

        If($totalCpuCapacity -gt $allocatedCPU){
            break
        }

    }

    ### Add failover Capacity

    If($failoverHosts -ne 0){
        $i = 0
        $usedESXi++
        while ($i -lt $failoverHosts){
            $CpuESXiList.Add($ESXObjs[$usedESXi]) | out-null
            $usedESXi++
            $i++
        }
    }

    return $CpuESXiList

}



