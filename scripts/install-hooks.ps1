$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
} catch {
    # ignore
}

try {
    chcp 65001 | Out-Null
} catch {
    # ignore
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

git config core.hooksPath .githooks

Write-Host "OK: core.hooksPath установлен в .githooks" -ForegroundColor Green
Write-Host "Проверка: git config --get core.hooksPath" -ForegroundColor Cyan


