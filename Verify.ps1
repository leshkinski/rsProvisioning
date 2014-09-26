﻿. "C:\cloud-automation\secrets.ps1"
. "$($d.wD, $d.mR, "PullServerInfo.ps1" -join '\')"
try {
   $basePrepState = (Get-ScheduledTask -TaskName "BasePrep" -ErrorAction SilentlyContinue).State
}
catch {
}
if($basePrepState -eq "Running") {
   Write-EventLog -LogName DevOps -Source Verify -EntryType Information -EventId 1000 -Message "BasePrep task is currently running, aborting Verify task"
   break
}
if((Test-Path -Path "C:\Windows\System32\Configuration\Pending.mof") -and ((Get-ScheduledTask -TaskName "Consistency").State -eq "Running")) {
   Write-EventLog -LogName DevOps -Source Verify -EntryType Information -EventId 1000 -Message "Pending MOF exists and Consistency is currently running"
   if((Test-Path -Path "C:\Windows\System32\Configuration\Current.mof")) {
      Write-EventLog -LogName DevOps -Source Verify -EntryType Information -EventId 1000 -Message "Pending MOF exists and Consistency is currently running, Current MOF exists, aborting Verify task "
   }
   break
}
## This script is executed by the PullServerDSC scheduled task
## This script will check the hash value of the PullServerDSC.ps1 config script and if it has been modified it will create a new Hash and execute the PullServerDSC.ps1 script
## to start a new DSC configuration on the PullServer
Function Get-ServiceCatalog {
   return (Invoke-RestMethod -Uri $("https://identity.api.rackspacecloud.com/v2.0/tokens") -Method POST -Body $(@{"auth" = @{"RAX-KSKEY:apiKeyCredentials" = @{"username" = $($d.cU); "apiKey" = $($d.cAPI)}}} | convertTo-Json) -ContentType application/json)
}
Function Get-Region {
   $base = gwmi -n root\wmi -cl CitrixXenStoreBase
   $sid = $base.AddSession("MyNewSession")
   $session = gwmi -n root\wmi -q "select * from CitrixXenStoreSession where SessionId=$($sid.SessionId)"
   $region = $session.GetValue("vm-data/provider_data/region").value -replace "`"", ""
   return $region
}
Function Get-Role {
   $base = gwmi -n root\wmi -cl CitrixXenStoreBase
   $sid = $base.AddSession("MyNewSession")
   $session = gwmi -n root\wmi -q "select * from CitrixXenStoreSession where SessionId=$($sid.SessionId)"
   $role = $session.GetValue("vm-data/user-metadata/Role").value -replace "`"", ""
   return $role
}
Function Get-AccessIPv4 {
   $uri = (($catalog.access.serviceCatalog | ? name -eq "cloudServersOpenStack").endpoints | ? region -eq $(Get-Region)).publicURL
   $accessIPv4 = (((Invoke-RestMethod -Uri $($uri + "/servers/detail") -Method GET -Headers $AuthToken -ContentType application/json).servers) | ? { $_.name -eq $env:COMPUTERNAME}).accessIPv4
   return $accessIPv4
}
Function Download-File {
   # File download function
   param ( [string]$url, [string]$path )
   $webclient = New-Object System.Net.WebClient
   $webclient.DownloadFile($url,$path)
   return
}
### will pull before running rsEnvironments.ps1
Function Check-Hash {
   if((Test-Path $($d.wD, "rsEnvironments.hash" -join '\')) -eq $false) {
      Set-Content -Path $($d.wD, "rsEnvironments.hash" -join '\') -Value (Get-FileHash -Path $($d.wD, $d.mR, "rsEnvironments.ps1" -join '\')).hash
      chdir $($d.wD, $d.mR -join '\')
      Start-Service Browser
      Start -Wait git pull
      Stop-Service Browser
      taskkill /F /IM WmiPrvSE.exe
      Invoke-Command -ScriptBlock { PowerShell.exe $($d.wD, $d.mR, "rsEnvironments.ps1" -join '\')} -ArgumentList "-ExecutionPolicy Bypass -Force"
   }
   $checkHash = Get-FileHash $($d.wD, $d.mR, "rsEnvironments.ps1" -join '\')
   $currentHash = Get-Content $($d.wD, "rsEnvironments.hash" -join '\')
   if($checkHash.Hash -ne $currentHash) {
      Set-Content -Path $($d.wD, "rsEnvironments.hash" -join '\') -Value (Get-FileHash -Path $($d.wD, $d.mR, "rsEnvironments.ps1" -join '\')).hash
      taskkill /F /IM WmiPrvSE.exe
      Invoke-Command -ScriptBlock { PowerShell.exe $($d.wD, $d.mR, "rsEnvironments.ps1" -join '\')} -ArgumentList "-ExecutionPolicy Bypass -Force"
      taskkill /F /IM WmiPrvSE.exe
      Invoke-Command -ScriptBlock { PowerShell.exe $($d.wD, $d.mR, "rsEnvironments.ps1" -join '\')} -ArgumentList "-ExecutionPolicy Bypass -Force"
      $pullServerName = $env:COMPUTERNAME
      $pullServerPrivateIP = (Get-NetAdapter | ? status -eq 'up' | Get-NetIPAddress -ea 0 | ? IPAddress -match '^10\.').IPAddress
      $pullServerPublicIp = Get-AccessIPv4
      $path = $($d.wD, $d.mR, "PullServerInfo.ps1" -join '\')
      if(Test-Path -Path $path) {
         Remove-Item -Path $path -Force
      }
      $region = Get-Region
      chdir $($d.wD, $d.mR -join '\')
      New-Item -path $path -ItemType file
      Add-Content -Path $path -Value "`$pullServerInfo = @{"
      Add-Content -Path $path -Value "`"pullServerName`" = `"$pullServerName`""
      Add-Content -Path $path -Value "`"pullServerPrivateIp`" = `"$pullServerPrivateIp`""
      Add-Content -Path $path -Value "`"pullServerPublicIp`" = `"$pullServerPublicIp`""
      Add-Content -Path $path -Value "`"region`" = `"$region`""
      Add-Content -Path $path -Value "`"isRackConnect`" = `$$($isRackConnect.toString().toLower())"
      Add-Content -Path $path -Value "`"isManaged`" = `$$($isManaged.toString().toLower())"
      Add-Content -Path $path -Value "`"defaultRegion`" = `"$defaultRegion`""
      Add-Content -Path $path -Value "}"
      Set-Service Browser -startuptype "manual"
      Start-Service Browser
      Start -Wait -NoNewWindow "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "add $($d.wD + "\" + $d.mR + "\" + "PullServerInfo.ps1")"
      Start -Wait -NoNewWindow "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "commit -am `"$pullServerName pushing PullServerInfo.ps1`""
      Start -Wait -NoNewWindow "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "pull origin $($d.br)"
      Start -Wait -NoNewWindow "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "push origin $($d.br)"
      Stop-Service Browser
   }  
}
### Client tasks
Function Check-Hosts {
   $serverRegion = Get-Region
   $pullServerRegion = $pullServerInfo.region
   $pullServerName = $pullServerInfo.pullServerName
   $pullServerPublicIP = $pullserverInfo.pullserverPublicIp
   $pullServerPrivateIP = $pullServerInfo.pullServerPrivateIp
   if($pullServerRegion -ne $serverRegion) {
      $pullServerIP = $pullServerPublicIP
   }
   else {
      $pullServerIP = $pullServerPrivateIP
   }
   $hostEntry = "`n${pullServerIP}`t${pullServerName}"
   $entryExist = ((Get-Content "${env:windir}\system32\drivers\etc\hosts") -match "^[^#]*\s+$pullServerName") 
   if($entryExist) {
      $entryExist.Split()
      if(($entryExist[0]) -ne $pullServerIP) {
         ((Get-Content "${env:windir}\system32\drivers\etc\hosts") -notmatch "^\s*$") -notmatch "^[^#]*\s+$pullServerName" | Set-Content "${env:windir}\system32\drivers\etc\hosts"
         Add-Content -Path "${env:windir}\system32\drivers\etc\hosts" -Value $hostEntry -Force -Encoding ASCII
      }
   }
   else {
      Add-Content -Path "${env:windir}\system32\drivers\etc\hosts" -Value $hostEntry -Force -Encoding ASCII
   }
}
taskkill /F /IM WmiPrvSE.exe
Function Install-Certs {
   Stop-Service Browser
   Remove-Item -Path 'C:\Program Files (x86)\Git\.ssh\id_rsa*'
   Get-ChildItem Cert:\LocalMachine\Root\ | where {$_.Subject -eq $cN} | Remove-Item
   Copy-Item -Path $($d.wD, $d.mR, "Certificates\id_rsa.txt" -join '\') -Destination 'C:\Program Files (x86)\Git\.ssh\id_rsa'
   Copy-Item -Path $($d.wD, $d.mR, "Certificates\id_rsa.pub" -join '\') -Destination 'C:\Program Files (x86)\Git\.ssh\id_rsa.pub'
   powershell.exe certutil -addstore -f root $($d.wD, $d.mR, "Certificates\PullServer.crt" -join '\')
   taskkill /F /IM WmiPrvSE.exe
   Get-ScheduledTask -TaskName "Consistency" | Start-ScheduledTask
}
$role = Get-Role
   chdir $($d.wD, $d.mR -join '\')
   Start-Service Browser
   Start -Wait git pull
   Stop-Service Browser
if($role -eq "Pull") {
   $Global:catalog = Get-ServiceCatalog
   $Global:AuthToken = @{"X-Auth-Token"=($catalog.access.token.id)}
   $Global:defaultRegion = $catalog.access.user.'RAX-AUTH:defaultRegion'
   if(($catalog.access.user.roles | ? name -eq "rack_connect").id.count -gt 0) { $Global:isRackConnect = $true } else { $Global:isRackConnect = $false } 
   if(($catalog.access.user.roles | ? name -eq "rax_managed").id.count -gt 0) { $Global:isManaged = $true } else { $Global:isManaged = $false } 
   Check-Hash
}
else {
   Check-Hosts
   Install-Certs
}
