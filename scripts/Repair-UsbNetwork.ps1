$ErrorActionPreference='Stop'
$target='USB\VID_04E8&PID_6864&RNDIS\6&2B94E83C&0&0000'
$adapter=Get-CimInstance Win32_NetworkAdapter|Where-Object {$_.PNPDeviceID -eq $target}
if(!$adapter){throw 'Expected Samsung USB network adapter not found; no change made.'}
$result=Invoke-CimMethod -InputObject $adapter -MethodName Enable
$result|ConvertTo-Json|Set-Content -Encoding utf8 (Join-Path $PSScriptRoot '../artifacts/usb-test/network-enable.json')
if($result.ReturnValue -ne 0){throw ('Could not enable Samsung network adapter: '+$result.ReturnValue)}
Start-Sleep -Seconds 3
if(!(Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)){
    # Restart only the Samsung RNDIS child, never the USB composite/ADB interface.
    & pnputil.exe /restart-device $target | Set-Content -Encoding utf8 (Join-Path $PSScriptRoot '../artifacts/usb-test/network-restart.txt')
    if($LASTEXITCODE -ne 0){throw 'Samsung network restart failed.'}
}
