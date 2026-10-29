param([Parameter(Mandatory=$true)][System.Net.IPAddress]$LocalIp,[Parameter(Mandatory=$true)][System.Net.IPAddress]$PhoneIp,[string]$RuleName='NhomBar-USB-Samsung-5080')
$ErrorActionPreference='Stop'
if($LocalIp.AddressFamily -ne 'InterNetwork' -or $PhoneIp.AddressFamily -ne 'InterNetwork'){throw 'Cần địa chỉ IPv4.'}
# Narrow demo rule: only the phone peer and the current laptop USB address.
$name=$RuleName
if(Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue){
    Set-NetFirewallRule -Name $name -Enabled True -LocalAddress $LocalIp.ToString() -RemoteAddress $PhoneIp.ToString()|Out-Null
}else{
    New-NetFirewallRule -Name $name -DisplayName 'NhomBar USB Samsung test' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5080 -LocalAddress $LocalIp.ToString() -RemoteAddress $PhoneIp.ToString() -Profile Any|Out-Null
}
Write-Host "NhomBar: cổng 5080 chỉ mở từ $PhoneIp đến $LocalIp."
