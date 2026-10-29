param([Parameter(Mandatory=$true)][System.Net.IPAddress]$LocalIp,[Parameter(Mandatory=$true)][string]$PhoneIp)
$ErrorActionPreference='Stop'
$phones=@($PhoneIp.Split(',')|ForEach-Object {[System.Net.IPAddress]::Parse($_.Trim())})
if($LocalIp.AddressFamily -ne 'InterNetwork' -or @($phones|Where-Object {$_.AddressFamily -ne 'InterNetwork'}).Count){throw 'IPv4 required.'}
$addresses=@($phones|ForEach-Object {$_.ToString()})
$name='NhomBar-Dev-Wifi-5080'
if(Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue){
    Set-NetFirewallRule -Name $name -Enabled True -LocalAddress $LocalIp.ToString() -RemoteAddress $addresses|Out-Null
}else{
    New-NetFirewallRule -Name $name -DisplayName 'NhomBar development Wi-Fi API' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5080 -LocalAddress $LocalIp.ToString() -RemoteAddress $addresses -Profile Any|Out-Null
}
Write-Host 'Port 5080 allowed only for the specified phones on the specified local address.'
