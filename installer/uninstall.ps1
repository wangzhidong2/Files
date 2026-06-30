#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Files (Win32) 卸载程序
.DESCRIPTION
    清除所有注册的注册表项、快捷方式、文件关联和用户数据
.NOTES
    需要以管理员身份运行
#>

[CmdletBinding()]
param(
    [switch]$RemoveUserData,
    [switch]$Silent
)

$ErrorActionPreference = "Stop"
$AppName = "Files"
$AppExe = "Files.exe"
$ProtocolName = "files-dev"
$ExecAlias = "files-dev.exe"
$ProgID = "Files.Archive.1"
$FileTypes = @(".zip", ".7z", ".rar", ".tar", ".jar", ".mrpack", ".gz")
$InstallPath = "$env:ProgramFiles\Files"

function Write-Step([string]$msg) {
    if (-not $Silent) { Write-Host "[卸载] $msg" -ForegroundColor Cyan }
}
function Write-OK([string]$msg) {
    if (-not $Silent) { Write-Host "  ✓ $msg" -ForegroundColor Green }
}

# ── 检查管理员权限 ────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "需要管理员权限，正在提升..." -ForegroundColor Yellow
    $argList = "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`""
    if ($RemoveUserData) { $argList += " -RemoveUserData" }
    if ($Silent) { $argList += " -Silent" }
    Start-Process PowerShell -Verb RunAs -ArgumentList $argList
    exit
}

Write-Host ""
Write-Host "========================================" -ForegroundColor White
Write-Host "  $AppName Win32 卸载程序" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White
Write-Host ""

# ── 询问是否删除用户数据 ──────────────────────────────────────────────────────
if (-not $RemoveUserData -and -not $Silent) {
    $choice = Read-Host "是否同时删除用户数据 (设置、标签等)? (Y/N) [N]"
    if ($choice -match "^[Yy]") { $RemoveUserData = $true }
}

# ── 1. 关闭正在运行的 Files ───────────────────────────────────────────────────
Write-Step "关闭正在运行的 Files..."
$proc = Get-Process -Name "Files" -ErrorAction SilentlyContinue
if ($proc) {
    $proc | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-OK "Files 已关闭"
} else {
    Write-OK "Files 未运行"
}

# 同时关闭 Files.App.Server
$procServer = Get-Process -Name "Files.App.Server" -ErrorAction SilentlyContinue
if ($procServer) {
    $procServer | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# ── 2. 删除 URI 协议注册 ──────────────────────────────────────────────────────
Write-Step "移除协议 $ProtocolName`:"
$protocolKey = "HKLM:\SOFTWARE\Classes\$ProtocolName"
if (Test-Path $protocolKey) {
    Remove-Item -Path $protocolKey -Recurse -Force -ErrorAction SilentlyContinue
    Write-OK "协议 $ProtocolName`: 已移除"
}

# ── 3. 删除执行别名注册 ───────────────────────────────────────────────────────
Write-Step "移除执行别名 $ExecAlias"
$appPathsKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$ExecAlias"
if (Test-Path $appPathsKey) {
    Remove-Item -Path $appPathsKey -Recurse -Force -ErrorAction SilentlyContinue
    Write-OK "执行别名 $ExecAlias 已移除"
}

# ── 4. 删除文件类型关联 ───────────────────────────────────────────────────────
Write-Step "移除文件类型关联"
# 删除 ProgID
$progidKey = "HKLM:\SOFTWARE\Classes\$ProgID"
if (Test-Path $progidKey) {
    Remove-Item -Path $progidKey -Recurse -Force -ErrorAction SilentlyContinue
    Write-OK "ProgID $ProgID 已移除"
}
# 清理各扩展名的关联
foreach ($ext in $FileTypes) {
    $extKey = "HKLM:\SOFTWARE\Classes\$ext"
    if (Test-Path $extKey) {
        $currentVal = (Get-ItemProperty -Path $extKey -Name "(Default)" -ErrorAction SilentlyContinue)."(Default)"
        if ($currentVal -eq $ProgID) {
            Set-ItemProperty -Path $extKey -Name "(Default)" -Value "" -ErrorAction SilentlyContinue
        }
        # 移除 OpenWithProgids 中的记录
        $progidsKey = "$extKey\OpenWithProgids"
        if (Test-Path $progidsKey) {
            Remove-ItemProperty -Path $progidsKey -Name $ProgID -ErrorAction SilentlyContinue
        }
        # 移除 OpenWithList 中的记录
        $owlKey = "$extKey\OpenWithList"
        if (Test-Path $owlKey) {
            Remove-ItemProperty -Path $owlKey -Name $AppExe -ErrorAction SilentlyContinue
        }
        Write-OK "$ext 关联已清理"
    }
}

# 通知 Shell
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
    [Shell32]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)
} catch { }

# ── 5. 移除开机自启 ───────────────────────────────────────────────────────────
Write-Step "移除开机自启"
$runKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$runVal = (Get-ItemProperty -Path $runKey -Name $AppName -ErrorAction SilentlyContinue).$AppName
if ($runVal) {
    Remove-ItemProperty -Path $runKey -Name $AppName -ErrorAction SilentlyContinue
    Write-OK "开机自启已移除"
}

# ── 6. 删除快捷方式 ───────────────────────────────────────────────────────────
Write-Step "移除快捷方式"
$startMenuPath = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"
$lnkPath = Join-Path $startMenuPath "$AppName.lnk"
if (Test-Path $lnkPath) {
    Remove-Item -Path $lnkPath -Force -ErrorAction SilentlyContinue
    Write-OK "开始菜单快捷方式已删除"
}
$desktopPath = [Environment]::GetFolderPath("Desktop")
$desktopLnk = Join-Path $desktopPath "$AppName.lnk"
if (Test-Path $desktopLnk) {
    Remove-Item -Path $desktopLnk -Force -ErrorAction SilentlyContinue
    Write-OK "桌面快捷方式已删除"
}

# ── 7. 移除"添加/删除程序"注册 ───────────────────────────────────────────────
Write-Step "从系统程序列表移除"
$uninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$AppName"
if (Test-Path $uninstallKey) {
    Remove-Item -Path $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
    Write-OK "已从程序列表移除"
}

# ── 8. 删除程序文件 ───────────────────────────────────────────────────────────
Write-Step "删除程序文件"
if (Test-Path $InstallPath) {
    Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $InstallPath)) {
        Write-OK "程序文件已删除 ($InstallPath)"
    } else {
        Write-Host "  ! 部分文件无法删除，请手动移除 $InstallPath" -ForegroundColor Yellow
    }
} else {
    Write-OK "程序目录不存在"
}

# ── 9. 删除用户数据 ───────────────────────────────────────────────────────────
if ($RemoveUserData) {
    Write-Step "删除用户数据"
    $userPaths = @(
        "$env:LOCALAPPDATA\Files",
        "$env:APPDATA\Files",
        "$env:TEMP\Files"
    )
    foreach ($path in $userPaths) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $path)) {
                Write-OK "$path 已删除"
            } else {
                Write-Host "  ! $path 部分文件无法删除" -ForegroundColor Yellow
            }
        }
    }
} else {
    Write-Host "  用户数据已保留 ($env:LOCALAPPDATA\Files)" -ForegroundColor DarkGray
}

# ── 完成 ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  $AppName 卸载完成!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

if (-not $Silent) {
    Write-Host "按任意键退出..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
