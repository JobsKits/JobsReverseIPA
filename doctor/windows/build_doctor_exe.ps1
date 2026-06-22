param(
    [string]$ProjectRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectRoot

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "未找到 python，请先安装 Python 后再构建 IPA环境体检.exe"
}

python -m pip install --upgrade pip
python -m pip install pyinstaller
python -m PyInstaller `
    --onefile `
    --console `
    --name "IPA环境体检" `
    --paths "$ProjectRoot" `
    "$ProjectRoot\doctor\doctor_entry.py"

Write-Host "构建完成：$ProjectRoot\dist\IPA环境体检.exe"
