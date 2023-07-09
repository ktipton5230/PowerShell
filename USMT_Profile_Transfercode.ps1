$Credentials = Get-Credential -Credential "DOMAIN\user" # Make sure to change this to your domain so it includes it in the UserName field

# Prompt user for source, destination, and profile information
$SourcePCName = Read-Host -Prompt "Enter the old PC hostname to capture a user profile for"
$TargetPCName = Read-Host -Prompt "Enter the new PC hostname to restore the user profile to"
$CapturedUser = Read-Host -Prompt "Enter the username for the profile you want to capture"

Enable-WSManCredSSP -Role client -DelegateComputer *.your.domain.example -Force

$allowed = @('WSMAN/*.your.domain.example')

$key = 'hklm:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
if (!(Test-Path $key)) {
    md $key
}
New-ItemProperty -Path $key -Name AllowFreshCredentials -Value 1 -PropertyType Dword -Force            

$key = Join-Path $key 'AllowFreshCredentials'
if (!(Test-Path $key)) {
    md $key
}
$i = 1
$allowed |% {
    # Script does not take into account existing entries in this key
    New-ItemProperty -Path $key -Name $i -Value $_ -PropertyType String -Force
    $i++
}

#Enable CredSSP
Invoke-Command -ComputerName $SourcePCName -Credential $Credentials -ScriptBlock {Enable-WSManCredSSP -Role server -Force} 
Invoke-Command -ComputerName $TargetPCName -Credential $Credentials -ScriptBlock {Enable-WSManCredSSP -Role server -Force} 
Enable-WSManCredSSP -Role client -DelegateComputer $SourcePCName -Force
Enable-WSManCredSSP -Role client -DelegateComputer $TargetPCName -Force 

# Build and store remote PsExec and USMT command arguments in a string
# to run on the OLD PC you are capturing FROM
#
# Make sure to replace the "\\YourServer" paths to your network share
# with USMT files (loadstate and scanstate and XML USMT config files)
#
$CaptureArgs = "\\domaincifs\HDFILES\Groups\ServiceDesk\USMT\amd64\Store\$CapturedUser" 
$CaptureArgs2 = '/ue:*\*' 
$CaptureArg3 = "/ui:DOMAIN\$CapturedUser" 
$CaptureArg4 = "/i:\\domaincifs\HDFILES\Groups\ServiceDesk\USMT\amd64\miguser_including_downloads.xml" 
$CaptureArg5 = "/i:\\domaincifs\HDFILES\Groups\ServiceDesk\USMT\amd64\chromebookmarks.xml" 
$CaptureArg6 = "/i:\\domaincifs\HDFILES\Groups\ServiceDesk\USMT\amd64\migdocs.xml" 
$CaptureArg7 = "/l:C:\scanlog.log" 
$CaptureArg8 = "/o" 
$CaptureArg9 = "/c" 
$CaptureArg10 = "/v:13"
$CaptureArg11 = "/localonly"

$ScriptBlock = {
    $exePath = "\\domaincifs\HDFILES\Groups\ServiceDesk\USMT\amd64\scanstate.exe" 
    & $exePath $Using:CaptureArgs $Using:CaptureArgs2 $Using:CaptureArg3 $Using:CaptureArg4 $Using:CaptureArg5 $Using:CaptureArg6 $Using:CaptureArg7 $Using:CaptureArg8 $Using:CaptureArg9 $Using:CaptureArg10 $Using:CaptureArg11
}

#Invoke-Command -ComputerName "$SourcePCName" -ScriptBlock $ScriptBlock -ArgumentList {$CaptureArgs,$CaptureArgs2,$CaptureArg3,$CaptureArg4,$CaptureArg5,$CaptureArg6,$CaptureArg7,$CaptureArg8,$CaptureArg9,$CaptureArg10,$CaptureArg11} -Authentication Credssp -Credential $Credentials

$Verify = "/verify:all"
$Verify2 = "\\domaincifs\HDFILES\Groups\ServiceDesk\USMT\amd64\Store\$CapturedUser\USMT\USMT.MIG"
$Verify3 = "/v:13"
$Verify4 = "/l:C:\usmtutils.log"

$ScriptBlock3 = {
    $exepath = "\\domaincifs\HDFILES\Groups\ServiceDesk\USMT\amd64\usmtutils.exe"
    & $exepath $Using:Verify $Using:Verify2 $Using:Verify3 $Using:Verify4
}

#Invoke-Command -ComputerName "$SourcePCName" -ScriptBlock $ScriptBlock3 -ArgumentList {$Verify,$Verify2,$Verify3,$Verify4} -Authentication Credssp -Credential $Credentials

Read-Host -Prompt "`nPlease verify there is no corruption of files before entering Loadstate. (Press Enter to continue.)"

# Build and store remote PsExec and USMT command arguments in a string
# to run on the NEW PC you are restoring the profile TO
#
# Make sure to replace the "\\YourServer" paths to your network share
# with USMT files (loadstate and scanstate and XML USMT config files)
#
$RestoreArgs = "\\domaincifs\HDFILES\Groups\ServiceDesk\USMT\amd64\Store\$CapturedUser" 
$RestoreArgs2 = "/i:\\domaincifs\HDFILES\Groups\ServiceDesk\USMT\amd64\miguser_including_downloads.xml" 
$RestoreArgs3 = "/i:\\domaincifs\HDFILES\Groups\ServiceDesk\USMT\amd64\chromebookmarks.xml" 
$RestoreArgs4 = "/i:\\domaincifs\HDFILES\Groups\ServiceDesk\USMT\amd64\migdocs.xml"
$RestoreArgs5 = "/l:C:\loadlog.log" 
$RestoreArgs6 = "/c" 
$RestoreArgs7 = "/v:13"

$ScriptBlock2 = {
    $exepath =  "\\domaincifs\HDFILES\Groups\ServiceDesk\USMT\amd64\loadstate.exe"
    & $exePath $Using:RestoreArgs $Using:RestoreArgs2 $Using:RestoreArgs3 $Using:RestoreArgs4 $Using:RestoreArgs5 $Using:RestoreArgs6 $Using:RestoreArgs7
}

#Invoke-Command -ComputerName "$TargetPCName" -ScriptBlock $ScriptBlock2 -ArgumentList {$RestoreArgs,$RestoreArgs2,$RestoreArgs3,$RestoreArgs4,$RestoreArgs5,$RestoreArgs6,$RestoreArgs7} -Authentication Credssp -Credential $Credentials

# Check if the key exists before deleting
if (Test-Path $key) {
    Remove-Item -Path $key -Recurse -Force
    Write-Host "Registry key deleted: $key"
} else {
    Write-Host "Registry key does not exist: $key"
}

#Disable CredSSP on remote computers
Invoke-Command -ComputerName $SourcePCName -Credential $Credentials -ScriptBlock {Disable-WSManCredSSP -Role server }
Invoke-Command -ComputerName $TargetPCName -Credential $Credentials -ScriptBlock {Disable-WSManCredSSP -Role server }  
Disable-WSManCredSSP -Role client

# Inform user of completion
Read-Host -Prompt "`nUSMT Process has completed! Check USMT logs for details. (Press Enter to exit) "