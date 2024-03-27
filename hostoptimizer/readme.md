# Project Title

VMware CSP Host Optimization to find the minimum number of required host for the current workload

## Getting Started

These instructions will get you a copy of the project up and running on your local machine for development and testing purposes. See deployment for notes on how to deploy the project on a live system.

### Prerequisites

A windows based automation server that can be access by the active directory service user
Supported & Tested on Windows with Powershell 5.1
PowerCLi 11.5

### Installing

git clone https://github.com/comdivision/TBD onto your local system. Edit the globalConfig.json to fit the environment

{
 "vCenters":[
      "sa-vcsa-01.vclass.local",   --> All vCenters where the script should run against
      "sa-vcsa-02.vclass.local"
   ],
   "Clusters":[
      "SA-Compute-01",             --> All CLusters where the script should be applied to; * will for every cluster
      "SA-Compute-02"
   ],
   "MemoryFillrate":0.8, --> The percentage value of the memory allocation of a host: e.g. 0.8 means for a 1024GB Memory host will, it will be declared as full when having more that 819,2 GB allocated memory (VMs with that total amount of memory configured)
   "vMempMemRatio": 1.0, --> The business decision how much memory will be overcomitted: 1.0 means that on a 1024GB memory host a maximum of 1024 GB virtual Memory will be given to VMs.
   "vCpuCoreRatio":"4", --> The business decision how much CPU will be overcomitted: 4 means that on a single physical core an average of 4 virtual CPUs is allocated to
   "failoverHosts":"1" --> The number of failover hosts. If the calculation comes to a result of 5 required ESXi hosts it will select with failoverHosts = 1 a total of 6 ESXi hosts
}

### concept

The business logic will be executed by the main.ps1 script. Check all VMs and figure out how many of the existing ESXI hosts are required to run the number of VMs based on the parameters defined in the globalConfig.json

Phase 1 utilizes workload Analysis.psm1. Based on the Operating System delivered a workload analysis takes place. On every cluster:
How many vCPUs & vMemory are currently allocated for all VMS on the clusters?
Based on resource parameters like failoverhosts; vCPU:COre ratio & vMem:pMem ratio the number of physical resources required
to run the workload is calculated.
In the next step the proper ESXi hosts are selected based on their resourcec characteristics. The ESXi hosts are sorted by amount of cores first and their hostname second 
to make sure the results remain deterministic




## Running the tests

PS C:\> cd C:\automation\hostoptimizer
PS C:\> .\main.ps1

If no vCenter_credential.xml exists in the root folder, you will be asked for the proper credentials. These credentials are encrypted with the local windows user executing the script. In case a service user will run the scheduled task, make sure to create this credential file in the context of the service user.


A report will be created giving further summarized information about the placement characteristics, which os has been used and which other OS has been discovered during the runtime.

Sample output:


| ClusterName |                           OS                            | RequiredESXiHosts | ResourceDecision | allocatedMemory | allocatedCPU | vCpuCoreRatio | vMempMemRatio | memoryFillRate | failoverHosts |
|-------------|---------------------------------------------------------|-------------------|------------------|-----------------|--------------|---------------|---------------|----------------|---------------|
| LE01        | Windows                                                 |                 4 | Memory           |              52 |           11 |             4 |           1.0 |            0.8 |             1 |
| LE01        | Other 3.x or later Linux (64-bit),Ubuntu Linux (64-bit) |                 4 | Memory           |              60 |           24 |             4 |           1.0 |            0.8 |             1 |





## Deployment

You can create different instances either by putting the script in different folders and change the proper script location in main.ps1 input parameter; e.g. 
C:\automation\production 
C:\automation\test
C:\automation\tenantA

alternatively you can create different configFiles and execute the script accordingly.

e.g. 
Prod: C:\automation\prod_globalConfig.JSON and call .\main.ps1 -globalConfig C:\automation\prod_globalConfig.JSON
Test: C:\automation\test_globalConfig.JSON and call .\main.ps1 -globalConfig C:\automation\test_globalConfig.JSON

To keep the automation running for a complete lifecycle it is recommended to configure it as a windows scheduled task.

https://www.running-system.com/how-to-run-a-powercli-script-using-task-scheduler/

It is recommend to let the scheduled task be run as the service user (that has vCenter access & for whom the vCenter credentials file has been created). A sample xml (sample_scheduledTaskWin.xml) can be used to be imported and changed accordingly.


## Authors

* **Fabian Lenz - comdivision (creator)


## Acknowledgments

* To everyone in the PowerCLI community ;-)

