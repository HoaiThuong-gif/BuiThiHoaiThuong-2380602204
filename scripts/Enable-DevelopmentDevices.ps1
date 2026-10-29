$ErrorActionPreference='Stop'
$allowed=@('10.199.185.95','10.85.63.22')
foreach($config in Get-NetIPConfiguration){
    $local=@($config.IPv4Address.IPAddress)|Where-Object {$_ -in $allowed}|Select-Object -First 1
    $peer=$config.IPv4DefaultGateway.NextHop
    if(!$local -or !$peer){continue}
    $name='NhomBar-Dev-USB-'+$config.InterfaceIndex
    if(Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue){Set-NetFirewallRule -Name $name -Enabled True -LocalAddress $local -RemoteAddress $peer|Out-Null}
    else{New-NetFirewallRule -Name $name -DisplayName 'NhomBar development USB API' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5080 -LocalAddress $local -RemoteAddress $peer -Profile Any|Out-Null}
}
