# Trusts the test certificate (LocalMachine\TrustedPeople, needs admin) and installs the MSIX for the current user.
param([string]$Msix, [string]$Name = 'TrefoilStudio.WriteItDown', [string]$Cer = 'C:\wid\msixwork\wid-test.cer')
$ErrorActionPreference = 'Stop'
Import-Certificate -FilePath $Cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
Get-AppxPackage -Name $Name | Remove-AppxPackage -ErrorAction SilentlyContinue
Add-AppxPackage -Path $Msix
Get-AppxPackage -Name $Name | Select-Object Name, Version, InstallLocation, PackageFamilyName, SignatureKind | Format-List
