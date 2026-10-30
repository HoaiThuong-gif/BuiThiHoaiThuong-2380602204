$ErrorActionPreference='Stop'
$frontendPath = & (Join-Path $PSScriptRoot 'Get-FrontendPath.ps1')
$dictionary=@{}
foreach($relativePath in @('lib/core/strings.dart','lib/core/extra_english.dart')) {
    $source=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $frontendPath $relativePath)
    if($relativePath -eq 'lib/core/strings.dart'){$source=$source.Substring($source.IndexOf('const _english'))}
    foreach($entry in [regex]::Matches($source,"(?s)'((?:\\.|[^'\\])*)'\s*:\s*'((?:\\.|[^'\\])*)'")) {
        $translationKey=$entry.Groups[1].Value.Replace('\n',"`n").Replace("\'","'")
        $translationValue=$entry.Groups[2].Value.Replace('\n',"`n").Replace("\'","'")
        $dictionary[$translationKey]=$translationValue
    }
}
$dictionary | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 -LiteralPath (Join-Path $frontendPath 'assets/english.json')
Write-Host "Đã cập nhật $($dictionary.Count) câu dịch cho Android."
