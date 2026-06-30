#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Files (Win32) 安装程序
.DESCRIPTION
    安装 Files 到 Program Files，注册协议、文件关联、快捷方式、开机自启
.NOTES
    需要以管理员身份运行
#>

[CmdletBinding()]
param(
    [string]$InstallPath = "$env:ProgramFiles\Files",
    [switch]$CreateDesktopShortcut,
    [switch]$CreateStartup,
    [switch]$Silent
)

$ErrorActionPreference = "Stop"
$AppName = "Files"
$AppExe = "Files.exe"
$AppPublisher = "Files Community"
$AppVersion = "4.1.6.0"
$ProtocolName = "files-dev"
$ExecAlias = "files-dev.exe"
$StartupTaskId = "3AA55462-A5FA-4933-88C4-712D0B6CDEBB"
$FileTypes = @(".zip", ".7z", ".rar", ".tar", ".jar", ".mrpack", ".gz")

# ProgID for file associations
$ProgID = "Files.Archive.1"

# ── Helper ────────────────────────────────────────────────────────────────────

function Write-Step([string]$msg) {
    if (-not $Silent) { Write-Host "[安装] $msg" -ForegroundColor Cyan }
}
function Write-OK([string]$msg) {
    if (-not $Silent) { Write-Host "  ✓ $msg" -ForegroundColor Green }
}
function Write-Warn([string]$msg) {
    if (-not $Silent) { Write-Host "  ! $msg" -ForegroundColor Yellow }
}

# ── 检查管理员权限 ────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "需要管理员权限，正在提升..." -ForegroundColor Yellow
    $argList = "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`""
    if ($InstallPath) { $argList += " -InstallPath `"$InstallPath`"" }
    if ($CreateDesktopShortcut) { $argList += " -CreateDesktopShortcut" }
    if ($CreateStartup) { $argList += " -CreateStartup" }
    if ($Silent) { $argList += " -Silent" }
    Start-Process PowerShell -Verb RunAs -ArgumentList $argList
    exit
}

# ── 确定 exe 路径 ─────────────────────────────────────────────────────────────
$scriptDir = Split-Path -Parent $PSCommandPath
$sourceExe = Join-Path $scriptDir $AppExe

if (-not (Test-Path $sourceExe)) {
    # 尝试在 Files 子目录查找
    $sourceExe = Join-Path $scriptDir "Files\$AppExe"
}
if (-not (Test-Path $sourceExe)) {
    Write-Host "错误: 找不到 $AppExe，请确保安装脚本和 Files.exe 在同一目录" -ForegroundColor Red
    exit 1
}

$sourceDir = Split-Path -Parent $sourceExe

Write-Host ""
Write-Host "========================================" -ForegroundColor White
Write-Host "  $AppName Win32 安装程序 v$AppVersion" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White
Write-Host ""

# ── 1. 复制文件 ───────────────────────────────────────────────────────────────
Write-Step "安装到 $InstallPath"

if (Test-Path $InstallPath) {
    # 如果 Files 正在运行，先关闭
    $proc = Get-Process -Name "Files" -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Step "关闭正在运行的 Files..."
        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Force -Path $InstallPath | Out-Null
Copy-Item -Path "$sourceDir\*" -Destination $InstallPath -Recurse -Force
$targetExe = Join-Path $InstallPath $AppExe
Write-OK "文件已复制"

# ── 2. 注册 URI 协议 (files-dev:) ─────────────────────────────────────────────
Write-Step "注册协议 $ProtocolName`:"
$protocolKey = "HKLM:\SOFTWARE\Classes\$ProtocolName"
New-Item -Path $protocolKey -Force | Out-Null
Set-ItemProperty -Path $protocolKey -Name "(Default)" -Value "URL:Files Protocol"
Set-ItemProperty -Path $protocolKey -Name "URL Protocol" -Value ""
New-Item -Path "$protocolKey\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$protocolKey\shell\open\command" -Name "(Default)" -Value "`"$targetExe`" `"%1`""
Write-OK "协议 $ProtocolName`: 已注册"

# ── 3. 注册执行别名 (files-dev.exe) ───────────────────────────────────────────
Write-Step "注册执行别名 $ExecAlias"
$aliasPath = Join-Path $InstallPath $ExecAlias
# 创建一个指向 Files.exe 的别名（复制 exe 或创建批处理）
if (-not (Test-Path $aliasPath)) {
    Copy-Item -Path $targetExe -Destination $aliasPath -Force
}
# 添加到 App Paths 以便在运行对话框中使用
$appPathsKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$ExecAlias"
New-Item -Path $appPathsKey -Force | Out-Null
Set-ItemProperty -Path $appPathsKey -Name "(Default)" -Value $aliasPath
Set-ItemProperty -Path $appPathsKey -Name "Path" -Value $InstallPath
Write-OK "执行别名 $ExecAlias 已注册"

# ── 4. 注册文件类型关联 ───────────────────────────────────────────────────────
Write-Step "注册文件类型关联"
# 创建 ProgID
$progidKey = "HKLM:\SOFTWARE\Classes\$ProgID"
New-Item -Path $progidKey -Force | Out-Null
Set-ItemProperty -Path $progidKey -Name "(Default)" -Value "Archive File"
New-Item -Path "$progidKey\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "$progidKey\DefaultIcon" -Name "(Default)" -Value "`"$targetExe`",0"
New-Item -Path "$progidKey\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$progidKey\shell\open\command" -Name "(Default)" -Value "`"$targetExe`" `"%1`""

foreach ($ext in $FileTypes) {
    $extKey = "HKLM:\SOFTWARE\Classes\$ext"
    New-Item -Path $extKey -Force | Out-Null
    Set-ItemProperty -Path $extKey -Name "(Default)" -Value $ProgID
    New-Item -Path "$extKey\OpenWithList" -Force | Out-Null
    Set-ItemProperty -Path "$extKey\OpenWithList" -Name $AppExe -Value "" -ErrorAction SilentlyContinue
    New-Item -Path "$extKey\OpenWithProgids" -Force | Out-Null
    Set-ItemProperty -Path "$extKey\OpenWithProgids" -Name $ProgID -Value "" -PropertyType String -ErrorAction SilentlyContinue
    Write-OK "$ext → $ProgID"
}

# 通知 Shell 文件关联已更改
$signature = @"
using System;
using System.Runtime.InteropServices;
public class Shell32 {
    [DllImport("shell32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern void SHChangeNotify(uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
"@
try {
    Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue
    # SHCNE_ASSOCCHANGED = 0x08000000, SHCNF_IDLIST = 0x0000
    [Shell32]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)
} catch {
    Write-Warn "无法通知 Shell 刷新（不影响安装）"
}

# ── 5. 创建开始菜单快捷方式 ───────────────────────────────────────────────────
Write-Step "创建开始菜单快捷方式"
$startMenuPath = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"
$lnkPath = Join-Path $startMenuPath "$AppName.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($lnkPath)
$shortcut.TargetPath = $targetExe
$shortcut.IconLocation = $targetExe
$shortcut.Description = "Files - 文件管理器"
$shortcut.WorkingDirectory = $InstallPath
$shortcut.Save()
Write-OK "开始菜单快捷方式已创建"

# ── 6. 创建桌面快捷方式 ───────────────────────────────────────────────────────
if ($CreateDesktopShortcut -or -not $Silent) {
    if (-not $Silent) {
        $choice = Read-Host "是否创建桌面快捷方式? (Y/N) [Y]"
        if ($choice -eq "" -or $choice -match "^[Yy]") { $CreateDesktopShortcut = $true }
    }
}
if ($CreateDesktopShortcut) {
    Write-Step "创建桌面快捷方式"
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $desktopLnk = Join-Path $desktopPath "$AppName.lnk"
    $shortcut = $shell.CreateShortcut($desktopLnk)
    $shortcut.TargetPath = $targetExe
    $shortcut.IconLocation = $targetExe
    $shortcut.Description = "Files - 文件管理器"
    $shortcut.WorkingDirectory = $InstallPath
    $shortcut.Save()
    Write-OK "桌面快捷方式已创建"
}

# ── 7. 注册开机自启 ───────────────────────────────────────────────────────────
if ($CreateStartup -or (-not $Silent -and -not $CreateStartup)) {
    if (-not $Silent -and -not $CreateStartup) {
        $choice = Read-Host "是否设置开机自启? (Y/N) [N]"
        if ($choice -match "^[Yy]") { $CreateStartup = $true }
    }
}
if ($CreateStartup) {
    Write-Step "注册开机自启"
    $runKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    Set-ItemProperty -Path $runKey -Name $AppName -Value "`"$targetExe`""
    Write-OK "开机自启已设置"
}

# ── 8. 注册到"添加/删除程序" ─────────────────────────────────────────────────
Write-Step "注册到系统程序列表"
$uninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$AppName"
New-Item -Path $uninstallKey -Force | Out-Null
Set-ItemProperty -Path $uninstallKey -Name "DisplayName" -Value $AppName
Set-ItemProperty -Path $uninstallKey -Name "DisplayVersion" -Value $AppVersion
Set-ItemProperty -Path $uninstallKey -Name "Publisher" -Value $AppPublisher
Set-ItemProperty -Path $uninstallKey -Name "InstallLocation" -Value $InstallPath
Set-ItemProperty -Path $uninstallKey -Name "DisplayIcon" -Value $targetExe
Set-ItemProperty -Path $uninstallKey -Name "UninstallString" -Value "powershell.exe -ExecutionPolicy Bypass -NoProfile -File `"$InstallPath\uninstall.ps1`""
Set-ItemProperty -Path $uninstallKey -Name "NoModify" -Value 1 -Type DWord
Set-ItemProperty -Path $uninstallKey -Name "NoRepair" -Value 1 -Type DWord
Write-OK "已注册到添加/删除程序"

# ── 9. 复制卸载脚本 ───────────────────────────────────────────────────────────
$uninstallScript = Join-Path $scriptDir "uninstall.ps1"
if (Test-Path $uninstallScript) {
    Copy-Item -Path $uninstallScript -Destination $InstallPath -Force
    Write-OK "卸载脚本已复制"
}

# ── 完成 ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  $AppName 安装完成!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "安装路径:  $InstallPath" -ForegroundColor White
Write-Host "执行文件:  $targetExe" -ForegroundColor White
Write-Host "命令行:    $ExecAlias" -ForegroundColor White
Write-Host "协议:      ${ProtocolName}:" -ForegroundColor White
Write-Host "文件关联:  $($FileTypes -join ', ')" -ForegroundColor White
Write-Host ""

if (-not $Silent) {
    $launch = Read-Host "是否立即启动 $AppName? (Y/N) [N]"
    if ($launch -match "^[Yy]") {
        Start-Process $targetExe
    }
}
