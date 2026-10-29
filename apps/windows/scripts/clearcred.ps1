# Deletes this app's Credential Manager entries of one flavour (the vault belongs to the interactive logon session, so
# this must run there: scripts/mke2e.py runs it through the driver). usage: clearcred.ps1 [-Service TrefoilStudio.WriteItDown.qa]
param([string]$Service = 'TrefoilStudio.WriteItDown.qa')
$esc = [regex]::Escape($Service)
cmdkey /list | Select-String ("target=(" + $esc + "/\S+)") | ForEach-Object { $t = $_.Matches[0].Groups[1].Value; "delete $t"; cmdkey /delete:$t }
