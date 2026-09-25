#!/usr/bin/env pwsh

param(
    [Parameter(Position = 0)]
    [string]$SshCfgAlias
)

if ([string]::IsNullOrWhiteSpace($SshCfgAlias)) {
    Write-Error "No arguments provided."
    Write-Host "Usage: mon.ps1 [LOCAL_SSH_CFG_HOST_ALIAS]"
    exit 1
}

$code = Get-Command code -ErrorAction SilentlyContinue
if (-not $code) {
    Write-Error "'code' command not found on PATH. Install VS Code and enable the shell command."
    exit 1
}

& $code.Source --folder-uri "vscode-remote://ssh-remote+$SshCfgAlias/home/dss/dss-parallel-joey-runner"
