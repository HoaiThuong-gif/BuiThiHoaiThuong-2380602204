$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$nestedFrontend = Join-Path $repositoryRoot 'bui-thi-hoai-thuong-2380602204'

# Nhánh frontend đặt Flutter ở gốc; main đặt trong thư mục riêng.
if (Test-Path -LiteralPath (Join-Path $repositoryRoot 'pubspec.yaml')) {
    $repositoryRoot
} elseif (Test-Path -LiteralPath (Join-Path $nestedFrontend 'pubspec.yaml')) {
    $nestedFrontend
} else {
    throw 'Không tìm thấy project Flutter. Hãy mở đúng nhánh main hoặc frontend.'
}
