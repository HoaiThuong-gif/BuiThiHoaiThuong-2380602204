$ErrorActionPreference='Stop'
$usbAdb=Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$usbSerial='R5CRC0C2T3V'
$usbResults=Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts/usb-test'
New-Item -ItemType Directory -Force -Path $usbResults|Out-Null
function Invoke-UsbAdb { $out=& $usbAdb -s $usbSerial @args; if($LASTEXITCODE -ne 0){throw 'USB Android command failed'}; return $out }
function Read-UsbUi {
    $focus=(Invoke-UsbAdb shell dumpsys window | Select-String 'mCurrentFocus=')-join "`n"
    if($focus -notmatch 'vn.nhombar.nhombar'){throw 'NhomBar must be unobscured before reading its screen.'}
    $activities=(Invoke-UsbAdb shell dumpsys activity activities)-join "`n"
    if($activities -notmatch 'mResumedActivity:.*vn.nhombar.nhombar|topResumedActivity=.*vn.nhombar.nhombar'){throw 'NhomBar must be the visible app before reading its screen.'}
    Invoke-UsbAdb shell uiautomator dump /data/local/tmp/nhombar-usb.xml|Out-Null
    Invoke-UsbAdb pull /data/local/tmp/nhombar-usb.xml (Join-Path $usbResults 'ui.xml')|Out-Null
    return [xml](Get-Content -Raw -Encoding utf8 (Join-Path $usbResults 'ui.xml'))
}
function Touch-UsbNode {param($Node);if($null -eq $Node){throw 'Missing UI element'};$n=[regex]::Matches($Node.bounds,'\d+');Invoke-UsbAdb shell input tap ([int](([int]$n[0].Value+[int]$n[2].Value)/2)) ([int](([int]$n[1].Value+[int]$n[3].Value)/2))|Out-Null}
function Touch-UsbLabel {param([string]$Label);$ui=Read-UsbUi;Touch-UsbNode ($ui.SelectNodes('//node')|Where-Object {$_.'content-desc' -eq $Label -or $_.text -eq $Label}|Select-Object -First 1)}
