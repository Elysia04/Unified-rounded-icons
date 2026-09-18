[CmdletBinding()]
param(
    [switch] $SkipIcon
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot '_engine\png-jpg-to-ico.ps1'
$output = Join-Path $projectRoot '图片转圆角ICO.exe'
$manifest = Join-Path $PSScriptRoot 'app.manifest'
$icon = Join-Path $PSScriptRoot 'app.ico'

$compiler = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $compiler) {
    throw '找不到 .NET Framework C# 编译器。'
}

if (-not (Test-Path -LiteralPath $engine)) {
    throw "找不到转换引擎：$engine"
}

$sources = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.cs' |
    Sort-Object -Property Name |
    ForEach-Object { $_.FullName }

if ($sources.Count -eq 0) {
    throw '在 _app 里找不到任何 .cs 源文件。'
}

$compilerArguments = @(
    '/nologo'
    '/target:winexe'
    '/platform:anycpu'
    '/optimize+'
    '/langversion:5'
    "/out:$output"
    "/resource:$engine,RoundedIcoApp.Converter.ps1"
    '/reference:System.dll'
    '/reference:System.Drawing.dll'
    '/reference:System.Windows.Forms.dll'
)

if (Test-Path -LiteralPath $manifest) {
    $compilerArguments += "/win32manifest:$manifest"
}

if (-not $SkipIcon -and (Test-Path -LiteralPath $icon)) {
    $compilerArguments += "/win32icon:$icon"
}

$compilerArguments += $sources

& $compiler $compilerArguments

if ($LASTEXITCODE -ne 0) {
    throw "编译失败，退出代码：$LASTEXITCODE"
}

Write-Host "已生成：$output"