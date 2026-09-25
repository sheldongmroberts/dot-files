#!/usr/bin/env pwsh

param(
    [Parameter(Position = 0)]
    [string]$SshCfgAlias,

    [Parameter(Position = 1)]
    [string]$RemoteFolder
)

if ([string]::IsNullOrWhiteSpace($SshCfgAlias)) {
    Write-Error "No 1st argument provided."
    Write-Host "Usage: codessh.ps1 [LOCAL_SSH_CFG_HOST_ALIAS] [REMOTE_FOLDER]"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($RemoteFolder)) {
    Write-Error "No 2nd argument provided."
    Write-Host "Usage: codessh.ps1 [LOCAL_SSH_CFG_HOST_ALIAS] [REMOTE_FOLDER]"
    exit 1
}

$code = Get-Command code -ErrorAction SilentlyContinue
if (-not $code) {
    Write-Error "'code' command not found on PATH. Install VS Code and enable the shell command."
    exit 1
}

& $code.Source --folder-uri "vscode-remote://ssh-remote+$SshCfgAlias/home/dss/$RemoteFolder"
