param(
    [Parameter(Mandatory=$true)][String]$SnapshotName,
    [String]$SnapshotDescription,
    [Parameter(Mandatory=$true)][String]$vCenter,
    [Switch]$removeSnapshot,
    [Switch]$testing
    )

# -----------------------
# Define Global Variables
# -----------------------
$Global:Folder = $env:USERPROFILE+"\Documents\SnapshotManagement" 
#$Global:WorkingFolder = $Global:Folder+"\"+$(Get-Date -f MM-dd-yyyy_HH_mm_ss)
#$Global:SnapshotName = "Patching-Apr11"
#$Global:SnapshotDescription = "Snapshot prior to patching Apr11, 2018" 
#$Global:TimeStamp = $(Get-Date) 

<#
#*****************
# Get VC from User
#*****************
Function Get-VCenter {
    [CmdletBinding()]
    Param()
    #Prompt User for vCenter
    Write-Host "Enter the FQHN of the vCenter to Get Hosting Listing From: " -ForegroundColor "Yellow" -NoNewline
    $Global:VCName = Read-Host 
}
#*******************
# EndFunction Get-VC
#*******************
#>

#*************************************************
# Check for Folder Structure if not present create
#*************************************************
Function Verify-Folders {
    [CmdletBinding()]
    Param()
    "Building Local folder structure" 
    If (!(Test-Path $Global:Folder)) {
        New-Item $Global:Folder -type Directory
        }
    If (!(Test-Path $Global:WorkingFolder)){
        New-Item $Global:WorkingFolder -type Directory
        }
    "Folder Structure built" 

}
#***************************
# EndFunction Verify-Folders
#***************************

#*******************
# Connect to vCenter
#*******************
Function Connect-VC {
    [CmdletBinding()]
    Param()
    "Connecting to $vCenter"
    #Connect-VIServer $vCenter -Credential $Global:Creds -WarningAction SilentlyContinue
    Connect-VIServer $vCenter -WarningAction SilentlyContinue
}
#***********************
# EndFunction Connect-VC
#***********************

#*******************
# Disconnect vCenter
#*******************
Function Disconnect-VC {
    [CmdletBinding()]
    Param()
    "Disconnecting $vCenter"
    Disconnect-VIServer -Server $vCenter -Confirm:$false
}
#**************************
# EndFunction Disconnect-VC
#**************************

#**********************
# Function Get-FileName
#**********************
Function Get-FileName {
    [CmdletBinding()]
    Param($initialDirectory)
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = "TXT (*.txt)| *.txt"
    $OpenFileDialog.ShowDialog() | Out-Null
    Return $OpenFileDialog.filename
}
#*************************
# EndFunction Get-FileName
#*************************

#*************************
# Function Read-TargetList
#*************************
Function Read-TargetList {
    [CmdletBinding()]
    Param($TargetFile)
    $Targets = Get-Content $TargetFile
    Return $Targets
}
#****************************
# EndFunction Read-TargetList
#****************************

#**************************
# Function Check-Membership
#**************************
Function Check-Membership {
    [CmdletBinding()]
    Param($vmHosts)
    foreach($Name in $vmhosts){
        #"Verifing that $Name exists"
        $Exists = get-vm -name $Name -ErrorAction SilentlyContinue
        if ($Exists){
            Write-Host "$Name exists in this vCenter" -ForegroundColor Green
            Add-Content -Path "$Global:WorkingFolder\Confirmed.txt" -Value "$Name"
                }
            else {
                Write-Host "$Name does not exist in this vCenter" -ForegroundColor Red
                Add-Content -Path "$Global:WorkingFolder\Failed.txt" -Value "$Name"
                }
            }
}
#*****************************
# EndFunction Check-Membership
#*****************************


#***************
# Take-Snapshots
#***************
Function Take-Snapshots {
    [CmdletBinding()]
    Param($vmHosts)
    $taskTab = @{}
    foreach($Name in $vmhosts){
        #"Verifing that $Name exists"
        $Exists = get-vm -name $Name -ErrorAction SilentlyContinue
        if ($Exists){
            $SnapshotExists = (get-vm $Name | Get-Snapshot | Where {$_.name -eq $SnapshotName})
            if (!($SnapShotExists)) {
                "Initiate Snapshot of $Name"
                $taskTab[(Get-VM $Name | New-Snapshot -Name $SnapshotName -Description $SnapshotDescription -RunAsync).Id] = $Name
                #Add-Content -Path "$Global:WorkingFolder\SnapShot-Taken.txt" -Value "$Name"
                }
            else {
                Write-Host "$SnapshotName already exists for $Name" -ForegroundColor Red
                Add-Content -Path "$Global:WorkingFolder\SnapShot-AlreadyExists.txt" -Value "$SnapshotName already exists for $Name"
                }
            }
        Else {
            Write-Host "$Name was not found in this vCenter" -ForegroundColor Red
            Add-Content -Path "$Global:WorkingFolder\NotFound.txt" -Value "$Name" 
            }
    }
    $totalTasks = $taskTab.Count
    $runningTasks = $taskTab.Count
    While($runningTasks -gt 0){
        Get-Task | % {
            if($taskTab.ContainsKey($_.ID) -and $_.State -eq "Success"){
                "Snapshot completed on "+ ($_.ObjectID | Get-VIObjectByVIView | Select -expandproperty Name)
                Add-Content -Path "$Global:WorkingFolder\SnapShot-Taken.txt" -Value ($_.ObjectID | Get-VIObjectByVIView | Select -expandproperty Name)
                $taskTab.Remove($_.Id)
                $runningTasks--
                }
            ElseIF($taskTab.ContainsKey($_.Id) -and $_.State -eq "Error"){
                Write-Host "Snapshot failed on" ($_.ObjectID | Get-VIObjectByVIView | Select -expandproperty Name) -ForegroundColor Red
                Add-Content -Path "$Global:WorkingFolder\SnapShot-Failed.txt" -Value ($_.ObjectID | Get-VIObjectByVIView | Select -expandproperty Name)
                $taskTab.Remove($_.Id)
                $runningTasks--
                }
        }
        Write-Progress -Id 0 -Activity 'Snapshot tasks still running' -Status "$($runningTasks) task of $($totalTasks) still running" -PercentComplete (($runningTasks/$totalTasks) * 100)
        Start-Sleep -Seconds 5
    }
    Write-Progress -Id 0 -Activity 'Snapshot tasks still running' -Completed

}
#***************************
# EndFunction Take-Snapshots
#***************************

#*****************
# Remove-Snapshots
#*****************
Function Remove-Snapshots {
    [CmdletBinding()]
    Param($vmHosts)
    $taskTab = @{}
    foreach($Name in $vmhosts){
        $SnapshotExists = (get-vm $Name | Get-Snapshot | Where {$_.name -eq $SnapshotName})
        if ($SnapShotExists){
            "Initiate Snapshot $SnapshotName removal on $Name"
            $taskTab[(Get-VM $Name | Get-Snapshot | Where {$_.Name -eq $SnapshotName} | Remove-Snapshot -confirm:$false -RunAsync).Id] = $Name 
            }
        else {
            Write-Host "$SnapshotName doesn't exist for $Name" -ForegroundColor Red
            }
    }
    $totalTasks = $taskTab.Count
    $runningTasks = $taskTab.Count
    While($runningTasks -gt 0){
        Get-Task | % {
            if($taskTab.ContainsKey($_.ID) -and $_.State -eq "Success"){
                "Snapshot removal completed on "+ ($_.ObjectID | Get-VIObjectByVIView | Select -expandproperty Name)
                Add-Content -Path "$Global:WorkingFolder\SnapShotRemoval-Success.txt" -Value ($_.ObjectID | Get-VIObjectByVIView | Select -expandproperty Name)
                $taskTab.Remove($_.Id)
                $runningTasks--
                }
            ElseIF($taskTab.ContainsKey($_.Id) -and $_.State -eq "Error"){
                Write-Host "Snapshot removal failed on" + ($_.ObjectID | Get-VIObjectByVIView | Select -expandproperty Name) -ForegroundColor Red
                Add-Content -Path "$Global:WorkingFolder\SnapShotRemoval-Failed.txt" -Value ($_.ObjectID | Get-VIObjectByVIView | Select -expandproperty Name)
                $taskTab.Remove($_.Id)
                $runningTasks--
                }
        }
        Write-Progress -Id 0 -Activity 'Snapshot removal tasks still running' -Status "$($runningTasks) tasks of $($totalTasks) still running" -PercentComplete (($runningTasks/$totalTasks) * 100)
        Start-Sleep -Seconds 5
    }
    Write-Progress -Id 0 -Activity 'Snapshot removal tasks still running' -Completed

}
#*****************************
# EndFunction Remove-Snapshots
#*****************************


#***************
# Execute Script
#***************
CLS
$ErrorActionPreference="SilentlyContinue"

"=========================================================="
" "
#Write-Host "Get CIHS credentials" -ForegroundColor Yellow
#$Global:Creds = Get-Credential -Credential $null

#Get-VCenter
Connect-VC
"=========================================================="
"Get Target List"
$inputFile = Get-FileName $Global:Folder
"=========================================================="
$Global:WorkingFolder = $inputFile+"-"+$(Get-Date -f MM-dd-yyyy_HH_mm_ss)
$Global:WorkingFolder
Verify-Folders
"=========================================================="
"Reading Target List"
$VMHostList = Read-TargetList $inputFile
"=========================================================="
If ($testing){
    "Checking for vCenter Membership "
    Check-Membership $VMHostList
    }
    ElseIf ($removeSnapshot){
        "Removing Snapshots from Targets"
        Remove-Snapshots $VMHostList
        }
    Else {
        "Taking Snapshots of Targets"
        Take-Snapshots $VMHostList
        }