import-module activedirectory

#Make it dynamic
#$DCOU = (get-addomaincontroller).ComputerObjectDN
#$DCOU = $DCOU.subtring($DCOU.indexof(",",$DCOU.indexof(",") + 1) + 1)

$DCOU = Get-ADOrganizationalUnit -Filter {Name -eq "Domain Controllers"} | select -ExpandProperty DistinguishedName

#Check all DCs for connectivity first
$DCs = @()
Get-ADComputer -SearchBase $DCOU -filter * | select -ExpandProperty Name | foreach {
    $dc = $_
    try {
        Test-Connection -Count 1 $dc -EA Stop | out-null
        $DCs += $dc
        }
    catch {
        Write-Host -ForegroundColor Red "Error: $dc unreachable"
        }
    }
    
#Get the replication status of all partitions for each DC
$results = @()
foreach ($dc in $DCs) {
    try {
<# List of attributes for each returned object:
CompressChanges
ConsecutiveReplicationFailures
DisableScheduledSync
IgnoreChangeNotifications
IntersiteTransport
IntersiteTransportGuid
IntersiteTransportType
LastChangeUsn
LastReplicationAttempt
LastReplicationResult
LastReplicationSuccess
Partition
PartitionGuid
Partner
PartnerAddress
PartnerGuid
PartnerInvocationId
PartnerType
ScheduledSync
Server
SyncOnStartup
TwoWaySync
UsnFilter
Writable
#>
        Get-ADReplicationPartnerMetadata -Target $dc -Partition * -EA Stop | foreach {
            #Get the data we want, how we want
            $results += New-Object PSObject -Property @{
                "Server" = $_.server
                "Partner" = $_.Partner.split(",")[1].split("=")[1]
                "Partition" = $_.Partition
                "LastReplicationSuccess" = $_.LastReplicationSuccess
                "LastReplicationAttempt" = $_.LastReplicationAttempt
                }
            }
        }
    catch {$dc}
    } 
    
$results | sort LastReplicationSuccess | select Server,Partner,Partition,LastReplicationSuccess,LastReplicationAttempt | Out-GridView

<#repadmin implementation
#Necessary for pre-win8+/Win 2012
foreach ($DC in $DCs) {
    #For some reason, this output has a blank line inserted after every actual line outputted
    $ShowRepl = repadmin /showrepl $dc
    Remove-Variable outPutted -EA SilentlyContinue
    for ($i = 16;$i -lt $ShowRepl.count;$i+=2) {
        switch -regex ($ShowRepl[$i]) {
            "DC=" {
                Remove-Variable Partition,Partner,GUID,Timestamp -EA SilentlyContinue
                $Partition = $ShowRepl[$i].trim()
                break
                }
            "via RPC" {
                Remove-Variable Partner,GUID,Timestamp -EA SilentlyContinue
                $Partner = $ShowRepl[$i].trim().split(" ")[0].split("\")[1]
                break
                }
            "DSA object GUID" {
                $GUID = $ShowRepl[$i].split(":")[1].trim()
                break
                }
            "Last attempt" {
                $Timestamp = $ShowRepl[$i].split("@")[1].trim().substring(0,19)
                if (((Get-Date) - (Get-Date $Timestamp)).TotalDays -gt 5) {
                    $outStr = "$DC to $partner : $Partition - $Timestamp"
                    write-host $outStr
                    $outPutted = $true
                    }
                break
                }
            default {break}
            }
        }
    if ($outPutted) {Write-Host "_____________________________________________"}
    $BaseCode = [regex]::match(($dc.split("-")[0]),"[A-Z]{4}").value
    $ReplSum = repadmin /replsum "*$BaseCode*"
    for ($i = 12;$i -lt $ReplSum.count;$i+=2) {
        switch -regex ($ReplSum[$i]) {
            "DSA" {
                
                
                }
            default {break}
            }
        }
    }
#>
