# Sync deploy configs to EC2 (Windows). Uses tar + sudo extract (testuser may not own /opt/proshop).
# Usage:
#   $env:EC2_HOST = "testuser@3.107.1.188"
#   $env:SSH_KEY  = "F:\Cloud Computing\Capstone Project\test_key"
#   $env:SUDO_PASSWORD = "testuser"
#   .\scripts\sync-to-ec2.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Ec2Host = $env:EC2_HOST
if (-not $Ec2Host) { throw "Set EC2_HOST, e.g. testuser@3.107.1.188" }

$Key = $env:SSH_KEY
$ProshopDir = if ($env:PROSHOP_DIR) { $env:PROSHOP_DIR } else { "/opt/proshop" }
$SudoPass = if ($env:SUDO_PASSWORD) { $env:SUDO_PASSWORD } else { "testuser" }

$sshArgs = @("-o", "StrictHostKeyChecking=no")
if ($Key) {
  $keyDst = Join-Path $env:TEMP "proshop_sync_key"
  Copy-Item -Force $Key $keyDst
  icacls $keyDst /inheritance:r | Out-Null
  icacls $keyDst /grant:r "${env:USERNAME}:(R)" | Out-Null
  $sshArgs += @("-i", $keyDst)
}

$archive = Join-Path $env:TEMP "proshop-deploy.tgz"
if (Test-Path $archive) { Remove-Item $archive -Force }

Push-Location $Root
tar -czf $archive --exclude=".env" app-stack monitoring-stack scripts
Pop-Location

Write-Host "==> Upload archive"
scp @sshArgs $archive "${Ec2Host}:/tmp/proshop-deploy.tgz"

Write-Host "==> Extract on server (sudo)"
$remoteCmd = "echo $SudoPass | sudo -S tar -xzf /tmp/proshop-deploy.tgz -C $ProshopDir && echo $SudoPass | sudo -S chmod +x $ProshopDir/scripts/*.sh && echo $SudoPass | sudo -S sed -i 's/\r$//' $ProshopDir/scripts/*.sh 2>/dev/null; rm -f /tmp/proshop-deploy.tgz"
ssh @sshArgs $Ec2Host $remoteCmd

Write-Host "Sync done. Deploy:"
Write-Host "  ssh ... `"echo $SudoPass | sudo -S bash -c 'export DOMAIN=proshop-mern.duckdns.org; export ENV_FILE=$ProshopDir/monitoring-stack/.env; bash $ProshopDir/scripts/deploy-ec2.sh'`""
