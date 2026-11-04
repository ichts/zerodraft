# Packages the app exe as a test-signed MSIX on Windows (needs C:\wid\tools\x64 = Microsoft.Windows.SDK.BuildTools).
# -Version and -MinVersion are required: scripts/package-msix.sh passes them from version/version.txt and the Windows 11
# floor, and nothing here keeps a second copy of either.
#   release: make-msix.ps1 -Exe C:\wid\stage\wid.exe -Out C:\wid\out\WriteItDown.msix -Version 1.0.0.0 -MinVersion 10.0.22000.0
#   QA:      make-msix.ps1 -Exe ... -Out ... -Name TrefoilStudio.WriteItDownQA -Display 'Write It Down (QA)' -Short 'WID QA' -Version 1.0.0.0 -MinVersion 10.0.22000.0
param(
  [string]$Exe, [string]$Out, [string]$Work = 'C:\wid\msixwork',
  [string]$Name = 'TrefoilStudio.WriteItDown', [string]$Display = 'Write It Down', [string]$Short = 'Write It Down',
  [string]$Publisher = 'CN=WID Test Signing', [string]$PublisherDisplay = 'Trefoil Studio', [string]$Version, [string]$MinVersion,
  [switch]$NoSign
)
$ErrorActionPreference = 'Stop'
if (-not $Version -or -not $MinVersion) { throw 'make-msix.ps1 needs -Version a.b.c.0 and -MinVersion (scripts/package-msix.sh passes both)' }
$sdk = 'C:\wid\tools\x64'
Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$Work\layout\Assets" | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'assets\*') "$Work\layout\Assets" -Force
# the manifest names Assets\StoreLogo.png etc.; the shell picks the scale-qualified files
Copy-Item $Exe "$Work\layout\wid.exe"
$m = Get-Content (Join-Path $PSScriptRoot 'AppxManifest.xml') -Raw -Encoding UTF8
$m = $m.Replace('@EXE@', 'wid.exe').Replace('@NAME@', $Name).Replace('@DISPLAY@', $Display).Replace('@SHORT@', $Short).Replace('@PUBLISHER@', $Publisher).Replace('@PUBDISPLAY@', $PublisherDisplay).Replace('@VERSION@', $Version).Replace('@MINVERSION@', $MinVersion)
Set-Content "$Work\layout\AppxManifest.xml" $m -Encoding UTF8
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
Remove-Item $Out -Force -ErrorAction SilentlyContinue
& "$sdk\makeappx.exe" pack /d "$Work\layout" /p $Out /o | Out-Host
if ($NoSign) { return }
# test certificate (subject must equal the manifest Publisher); a Store submission is signed by the Store instead
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq $Publisher } | Select-Object -First 1
if (-not $cert) {
  $cert = New-SelfSignedCertificate -Type Custom -Subject $Publisher -KeyUsage DigitalSignature -FriendlyName 'WID test signing' `
    -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(1) `
    -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
}
Export-Certificate -Cert $cert -FilePath "$Work\wid-test.cer" | Out-Null
& "$sdk\signtool.exe" sign /fd SHA256 /sha1 $cert.Thumbprint /s My $Out | Out-Host
Write-Host "thumbprint $($cert.Thumbprint)"
