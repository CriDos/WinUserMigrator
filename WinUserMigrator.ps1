$ErrorActionPreference = "Stop"

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$DateTime = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$LogFile = "$ScriptPath\MoveUserProfile_$DateTime.log"

"========================================" | Out-File -FilePath $LogFile -Encoding utf8
"Script started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $LogFile -Append -Encoding utf8
"========================================" | Out-File -FilePath $LogFile -Append -Encoding utf8

function Write-LogAndConsole {
    param([string]$Message)
    $Message | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Host $Message
}

function IsAdmin {
    return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function IsBuiltInAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $userSID = $currentUser.User.Value
    return $userSID -match "-500$"
}

function GetBuiltInAdminName {
    try {
        $adminAccount = Get-LocalUser | Where-Object { $_.SID.Value -match "-500$" }
        return $adminAccount.Name
    } catch {
        Write-LogAndConsole "Error getting built-in Administrator account name: $($_.Exception.Message)"
        return "Administrator"
    }
}

function ToggleUserAccount {
    param(
        [string]$Username,
        [ValidateSet("Enable", "Disable")] 
        [string]$Action = "Enable"
    )
    
    $actionText = if ($Action -eq "Enable") { "Enabling" } else { "Disabling" }
    $cmdlet = if ($Action -eq "Enable") { "Enable-LocalUser" } else { "Disable-LocalUser" }
    
    Write-LogAndConsole "$actionText user account $Username..."
    
    try {
        & $cmdlet -Name $Username
        Write-LogAndConsole "User account $Username successfully $($Action.ToLower())d"
        return $true
    } catch {
        Write-LogAndConsole "ERROR when $($actionText.ToLower()) user account $Username`: $($_.Exception.Message)"
        try {
            Start-Process -FilePath "powershell.exe" -ArgumentList "-Command $cmdlet -Name `"$Username`"" -Verb RunAs -Wait
            return $true
        } catch {
            Write-LogAndConsole "Failed to execute command with elevated privileges: $($_.Exception.Message)"
            return $false
        }
    }
}

function GetNonSystemUsers {
    return Get-LocalUser | Where-Object { 
        -not ($_.SID.Value -match "-500$" -or
              $_.SID.Value -match "-501$" -or
              $_.SID.Value -match "-503$" -or
              $_.SID.Value -eq "S-1-5-18" -or
              $_.SID.Value -eq "S-1-5-19" -or
              $_.SID.Value -eq "S-1-5-20" -or
              $_.Name -eq "WDAGUtilityAccount")
    }
}

function ShowUserAccounts {
    $allUsers = GetNonSystemUsers
    
    Write-LogAndConsole "List of user accounts:"
    
    for ($i = 0; $i -lt $allUsers.Count; $i++) {
        $status = if ($allUsers[$i].Enabled) { "Active" } else { "Inactive" }
        Write-LogAndConsole "  $($i+1). $($allUsers[$i].Name) - Status: $status"
    }
    
    $selectedIndex = 0
    do {
        Write-Host ""
        Write-Host "0. Return to main menu"
        $input = Read-Host "Select user account number to manage (0-$($allUsers.Count))"
        
        if ($input -eq "0") {
            return $null
        }
    
        try {
            $selectedIndex = [int]$input
        } catch {
            $selectedIndex = 0
        }
    } while ($selectedIndex -lt 1 -or $selectedIndex -gt $allUsers.Count)
    
    $selectedUser = $allUsers[$selectedIndex - 1]
    return $selectedUser
}

function ManageUserAccount {
    Write-Host ""
    Write-LogAndConsole "*** User Account Management ***"
    
    $selectedUser = ShowUserAccounts
    if ($selectedUser -eq $null) {
        return
    }
    
    $currentStatus = $selectedUser.Enabled
    
    Write-Host ""
    Write-Host "Account: $($selectedUser.Name)"
    Write-Host "Current status: $(if ($currentStatus) { 'Active' } else { 'Inactive' })"
    Write-Host ""
    Write-Host "Select action:"
    Write-Host "1. $(if ($currentStatus) { 'Disable' } else { 'Enable' }) account"
    Write-Host "0. Return back"
    
    $action = Read-Host "Your choice (0-1)"
    
    if ($action -eq "1") {
        $toggleAction = if ($currentStatus) { "Disable" } else { "Enable" }
        $result = ToggleUserAccount -Username $selectedUser.Name -Action $toggleAction
        
        if ($result) {
            Write-LogAndConsole "User account $($selectedUser.Name) successfully $(if ($currentStatus) { 'disabled' } else { 'enabled' })"
        }
    }
}

function SelectUserProfile {
    $usersWithProfiles = @()
    $allUsers = GetNonSystemUsers
        
    foreach ($user in $allUsers) {
        $userProfilePath = "C:\Users\$($user.Name)"
        if (Test-Path $userProfilePath) {
            $usersWithProfiles += $user.Name
        }
    }
    
    if ($usersWithProfiles.Count -eq 0) {
        Write-LogAndConsole "ERROR: No available user profiles found for migration!"
        Read-Host "Press Enter to return to main menu"
        return $null
    }
    
    Clear-Host
    Write-Host "================================================"
    Write-Host "           USER PROFILE SELECTION"
    Write-Host "================================================"
    Write-Host ""
    Write-LogAndConsole "Found the following user profiles in C:\Users:"
    Write-Host ""
        
    for ($i = 0; $i -lt $usersWithProfiles.Count; $i++) {
        $userProPath = "C:\Users\$($usersWithProfiles[$i])"
        $userProSize = "{0:N2} MB" -f ((Get-ChildItem -Path $userProPath -Recurse -Force -ErrorAction SilentlyContinue | 
                                        Measure-Object -Property Length -Sum).Sum / 1MB)
        Write-LogAndConsole "  $($i+1). $($usersWithProfiles[$i]) - size: $userProSize (SOURCE: $userProPath)"
    }
    
    Write-Host ""
    
    if ($usersWithProfiles.Count -eq 1) {
        $confirmSelect = Read-Host "Only one user profile found. Use it for migration? (y/n)"
        
        if ($confirmSelect.ToLower() -eq "y") {
            Write-LogAndConsole "Selected SOURCE user profile: C:\Users\$($usersWithProfiles[0])"
            return $usersWithProfiles[0]
        } else {
            Write-LogAndConsole "Profile selection canceled"
            return $null
        }
    } 
    else {
        $selectedIndex = 0
        do {
            Write-Host "0. Return to main menu"
            $input = Read-Host "Enter profile number for migration (1-$($usersWithProfiles.Count)) or 0 to cancel"
            
            if ($input -eq "0") {
                return $null
            }
            
            try {
                $selectedIndex = [int]$input
            } catch {
                $selectedIndex = 0
            }
        } while ($selectedIndex -lt 1 -or $selectedIndex -gt $usersWithProfiles.Count)
        
        $selectedUser = $usersWithProfiles[$selectedIndex - 1]
        Write-LogAndConsole "Selected SOURCE user profile: C:\Users\$selectedUser"
        return $selectedUser
    }
}

function SelectTargetDrive {
    Clear-Host
    Write-Host "================================================"
    Write-Host "              TARGET DRIVE SELECTION"
    Write-Host "================================================"
    Write-Host ""
    Write-LogAndConsole "Select the drive where the user profile will be migrated to"
    Write-LogAndConsole "SOURCE profile will remain at C:\Users\{username} as a symbolic link"
    Write-Host ""
    
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -ne "C" -and $_.Free -gt 0 }
    
    if ($drives.Count -eq 0) {
        Write-LogAndConsole "ERROR: No available drives found other than the system drive (C:)!"
        Read-Host "Press Enter to return to main menu"
        return $null
    }
    
    Write-LogAndConsole "Available TARGET drives:"
    Write-Host ""
    
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $drive = $drives[$i]
        $freeGB = [math]::Round($drive.Free / 1GB, 2)
        $totalGB = [math]::Round(($drive.Free + $drive.Used) / 1GB, 2)
        $percentFree = [math]::Round(($drive.Free / ($drive.Free + $drive.Used)) * 100, 1)
        Write-LogAndConsole "  $($i+1). Drive $($drive.Name): - Free $freeGB GB of $totalGB GB ($percentFree% free)"
        Write-LogAndConsole "      TARGET path would be: $($drive.Name):\Users"
    }
    
    Write-Host ""
    
    if ($drives.Count -eq 1) {
        $confirmSelect = Read-Host "Only one available drive found. Use it for migration? (y/n)"
        
        if ($confirmSelect.ToLower() -eq "y") {
            $selectedDrive = $drives[0]
            $targetPath = "$($selectedDrive.Name):\Users"
            Write-LogAndConsole "Selected TARGET drive: $($selectedDrive.Name): - Target folder: $targetPath"
            return $targetPath
        } else {
            Write-LogAndConsole "Drive selection canceled"
            return $null
        }
    } 
    else {
        $selection = 0
        do {
            Write-Host "0. Return to main menu"
            $input = Read-Host "Enter drive number for profile migration (1-$($drives.Count)) or 0 to cancel"
            
            if ($input -eq "0") {
                return $null
            }
            
            try {
                $selection = [int]$input
            } catch {
                $selection = 0
            }
        } while ($selection -lt 1 -or $selection -gt $drives.Count)
        
        $selectedDrive = $drives[$selection - 1]
        $targetPath = "$($selectedDrive.Name):\Users"
        
        Write-LogAndConsole "Selected TARGET drive: $($selectedDrive.Name): - Target folder: $targetPath"
        return $targetPath
    }
}

function CopyUserProfile {
    param (
        [string]$UserName,
        [string]$TargetPath
    )
    
    Clear-Host
    Write-Host "================================================"
    Write-Host "           USER PROFILE COPYING"
    Write-Host "================================================"
    Write-Host ""
    Write-LogAndConsole "*** Step 3: Copying user profile ***"
    
    $sourceUserProfile = "C:\Users\$UserName"
    $targetUserProfile = "$TargetPath\$UserName"
    
    if (-not (Test-Path $TargetPath)) {
        Write-LogAndConsole "Creating folder $TargetPath"
        try {
            New-Item -Path $TargetPath -ItemType Directory -Force | Out-Null
        } catch {
            Write-LogAndConsole "ERROR: Failed to create folder $TargetPath`: $($_.Exception.Message)"
            Read-Host "Press Enter to return to main menu"
            return $null
        }
    }
    
    if (Test-Path $targetUserProfile) {
        Write-LogAndConsole "WARNING: Profile already exists at target location: $targetUserProfile"
        Write-Host ""
        Write-Host "Select action:"
        Write-Host "1. Rename target profile '$targetUserProfile' to '${targetUserProfile}_old' and proceed with migration"
        Write-Host "2. Rename source profile 'C:\Users\$UserName' to 'C:\Users\${UserName}_old' and use target profile"
        Write-Host "3. Replace existing profile on target drive '$targetUserProfile'"
        Write-Host "0. Return to main menu"
        
        $action = Read-Host "Your choice (0-3)"
        
        if ($action -eq "0") {
            return $null
        } elseif ($action -eq "3") {
            Write-LogAndConsole "Replacing existing profile on target drive: $targetUserProfile"
            try {
                Remove-Item -Path $targetUserProfile -Force -Recurse
                Write-LogAndConsole "Existing profile on target drive deleted"
            } catch {
                Write-LogAndConsole "ERROR when deleting existing profile on target drive: $($_.Exception.Message)"
                
                Write-Host "1. Continue despite errors"
                Write-Host "0. Return to main menu"
                
                $continueOption = Read-Host "Your choice (0-1)"
                if ($continueOption -ne "1") {
                    return $null
                }
            }
        } elseif ($action -eq "2") {
            Write-LogAndConsole "Renaming source profile (C:\Users\$UserName) and using existing target profile ($targetUserProfile)"
            
            $oldSourceProfile = "${sourceUserProfile}_old"
            if (Test-Path $oldSourceProfile) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $oldSourceProfile = "${sourceUserProfile}_old_$timestamp"
            }
            
            try {
                Write-LogAndConsole "Renaming source profile C:\Users\$UserName to $oldSourceProfile"
                Rename-Item -Path $sourceUserProfile -NewName $oldSourceProfile -Force
                
                Write-LogAndConsole "Creating symbolic link from C:\Users\$UserName to target profile $targetUserProfile"
                cmd /c mklink /d "$sourceUserProfile" "$targetUserProfile"
                
                if (Test-Path $sourceUserProfile) {
                    $linkItem = Get-Item $sourceUserProfile -Force
                    if ($linkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                        Write-LogAndConsole "Symbolic link created successfully from C:\Users\$UserName to $targetUserProfile"
                        return "source_renamed"
                    } else {
                        Write-LogAndConsole "ERROR: Failed to create symbolic link"
                        
                        try {
                            Write-LogAndConsole "Restoring original source profile"
                            if (Test-Path $sourceUserProfile) {
                                Remove-Item -Path $sourceUserProfile -Force -Recurse
                            }
                            Rename-Item -Path $oldSourceProfile -NewName $sourceUserProfile -Force
                            Write-LogAndConsole "Original source profile (C:\Users\$UserName) restored"
                        } catch {
                            Write-LogAndConsole "CRITICAL ERROR: Failed to restore original source profile: $($_.Exception.Message)"
                        }
                        
                        Read-Host "Press Enter to return to main menu"
                        return $null
                    }
                } else {
                    Write-LogAndConsole "ERROR: Failed to create symbolic link"
                    
                    try {
                        Write-LogAndConsole "Restoring original source profile"
                        Rename-Item -Path $oldSourceProfile -NewName $sourceUserProfile -Force
                        Write-LogAndConsole "Original source profile (C:\Users\$UserName) restored"
                    } catch {
                        Write-LogAndConsole "CRITICAL ERROR: Failed to restore original source profile: $($_.Exception.Message)"
                    }
                    
                    Read-Host "Press Enter to return to main menu"
                    return $null
                }
            } catch {
                Write-LogAndConsole "ERROR when renaming source profile: $($_.Exception.Message)"
                Read-Host "Press Enter to return to main menu"
                return $null
            }
        } elseif ($action -eq "1") {
            Write-LogAndConsole "Renaming target profile and proceeding with migration"
            
            $oldTargetProfile = "${targetUserProfile}_old"
            if (Test-Path $oldTargetProfile) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $oldTargetProfile = "${targetUserProfile}_old_$timestamp"
            }
            
            try {
                Write-LogAndConsole "Renaming target profile $targetUserProfile to $oldTargetProfile"
                Rename-Item -Path $targetUserProfile -NewName $oldTargetProfile -Force
                Write-LogAndConsole "Target profile renamed successfully"
            } catch {
                Write-LogAndConsole "ERROR when renaming target profile: $($_.Exception.Message)"
                
                Write-Host "1. Continue despite errors"
                Write-Host "0. Return to main menu"
                
                $continueOption = Read-Host "Your choice (0-1)"
                if ($continueOption -ne "1") {
                    return $null
                }
            }
        } else {
            Write-LogAndConsole "Invalid input. Returning to main menu."
            return $null
        }
    }
    
    if ($action -eq "2") {
        return "source_renamed"
    }
    
    Write-LogAndConsole "Copying user profile from SOURCE (C:\Users\$UserName) to TARGET ($targetUserProfile)"
    
    if (-not (Test-Path $targetUserProfile)) {
        try {
            New-Item -Path $targetUserProfile -ItemType Directory -Force | Out-Null
        } catch {
            Write-LogAndConsole "ERROR: Failed to create target folder $targetUserProfile`: $($_.Exception.Message)"
            Read-Host "Press Enter to return to main menu"
            return $null
        }
    }
    
    try {
        $robocopyArgs = "`"$sourceUserProfile`" `"$targetUserProfile`" /E /COPYALL /DCOPY:T /R:1 /W:1 /XJ"
        Write-LogAndConsole "Executing command: robocopy $robocopyArgs"
        
        $robocopyProcess = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
        
        if ($robocopyProcess.ExitCode -lt 8) {
            Write-LogAndConsole "Profile copying from SOURCE (C:\Users\$UserName) to TARGET ($targetUserProfile) completed successfully"
            return "success"
        } else {
            Write-LogAndConsole "WARNING: Copying process completed with errors (code $($robocopyProcess.ExitCode))"
            
            Write-Host "1. Continue despite errors"
            Write-Host "0. Return to main menu"
            
            $continueOption = Read-Host "Your choice (0-1)"
            if ($continueOption -ne "1") {
                return $null
            }
            
            return "errors"
        }
    } catch {
        Write-LogAndConsole "ERROR when copying profile: $($_.Exception.Message)"
        
        Write-Host "1. Continue despite errors"
        Write-Host "0. Return to main menu"
        
        $continueOption = Read-Host "Your choice (0-1)"
        if ($continueOption -ne "1") {
            return $null
        }
        
        return "errors"
    }
}

function CreateSymbolicLink {
    param (
        [string]$UserName,
        [string]$TargetPath,
        [string]$CopyStatus
    )
    
    if ($CopyStatus -eq "source_renamed") {
        Write-LogAndConsole "Skipping symbolic link creation (source profile already renamed and linked)"
        return $true
    }
    
    Clear-Host
    Write-Host "================================================"
    Write-Host "           SYMBOLIC LINK CREATION"
    Write-Host "================================================"
    Write-Host ""
    Write-LogAndConsole "*** Step 4: Creating symbolic link for user profile ***"
    
    $sourceUserProfile = "C:\Users\$UserName"
    $targetUserProfile = "$TargetPath\$UserName"
    
    try {
        if (Test-Path $sourceUserProfile) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $backupDir = "C:\Users\${UserName}_backup_$timestamp"
            
            try {
                Write-LogAndConsole "Renaming source profile from C:\Users\$UserName to $backupDir"
                Rename-Item -Path $sourceUserProfile -NewName $backupDir -Force
            } catch {
                Write-LogAndConsole "ERROR when renaming source profile: $($_.Exception.Message)"
                Write-LogAndConsole "Attempting direct folder deletion..."
                
                try {
                    Remove-Item -Path $sourceUserProfile -Force -Recurse
                } catch {
                    Write-LogAndConsole "ERROR when deleting source profile (C:\Users\$UserName): $($_.Exception.Message)"
                    
                    if ((Test-Path $sourceUserProfile) -and 
                        ((Get-Item $sourceUserProfile -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                            
                        try {
                            $linkTarget = (Get-Item $sourceUserProfile).Target
                            if ($linkTarget -eq $targetUserProfile) {
                                Write-LogAndConsole "Existing symbolic link already points from SOURCE (C:\Users\$UserName) to TARGET ($targetUserProfile)"
                                return $true
                            } else {
                                Write-LogAndConsole "Current link points to $linkTarget, deleting..."
                                Remove-Item -Path $sourceUserProfile -Force
                            }
                        } catch {
                            Write-LogAndConsole "ERROR when working with existing link: $($_.Exception.Message)"
                            
                            Write-Host "0. Return to main menu"
                            Read-Host "Press Enter to return"
                            return $false
                        }
                    } else {
                        Write-LogAndConsole "Failed to delete or move the source profile folder (C:\Users\$UserName)"
                        
                        Write-Host "0. Return to main menu"
                        Read-Host "Press Enter to return"
                        return $false
                    }
                }
            }
        }
        
        Write-LogAndConsole "Creating symbolic link from SOURCE (C:\Users\$UserName) to TARGET ($targetUserProfile)"
        cmd /c mklink /d "$sourceUserProfile" "$targetUserProfile"
        
        if (Test-Path $sourceUserProfile) {
            Write-LogAndConsole "Symbolic link created successfully"
            
            $linkItem = Get-Item $sourceUserProfile -Force
            if ($linkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                Write-LogAndConsole "Verification successful: C:\Users\$UserName is now a symbolic link to $targetUserProfile"
            } else {
                Write-LogAndConsole "WARNING: C:\Users\$UserName is not a symbolic link"
            }
            
            return $true
        } else {
            Write-LogAndConsole "ERROR: Failed to create symbolic link"
            
            if (Test-Path $backupDir) {
                Write-LogAndConsole "Restoring from backup $backupDir to C:\Users\$UserName"
                Rename-Item -Path $backupDir -NewName $sourceUserProfile -Force
            } else {
                Write-LogAndConsole "CRITICAL ERROR: Source user profile deleted, but link not created!"
            }
            
            Write-Host "0. Return to main menu"
            Read-Host "Press Enter to return"
            return $false
        }
    } catch {
        Write-LogAndConsole "ERROR when creating symbolic link: $($_.Exception.Message)"
        
        Write-Host "0. Return to main menu"
        Read-Host "Press Enter to return"
        return $false
    }
}

function FinishOperation {
    param (
        [string]$UserName,
        [string]$TargetPath
    )
    
    Clear-Host
    Write-Host "================================================"
    Write-Host "          PROFILE MIGRATION COMPLETION"
    Write-Host "================================================"
    Write-Host ""
    
    Write-LogAndConsole "User profile migration for $UserName completed successfully"
    Write-LogAndConsole "Original profile location: C:\Users\$UserName (now a symbolic link)"
    Write-LogAndConsole "New physical profile location: $TargetPath\$UserName"
    
    ToggleUserAccount -Username $UserName -Action "Enable"
    
    Write-Host ""
    Write-Host "1. Restart computer now"
    Write-Host "0. Return to main menu"
    
    $restart = Read-Host "Your choice (0-1)"
    
    if ($restart -eq "1") {
        Write-LogAndConsole "Restarting computer..."
        Restart-Computer -Force
    } else {
        Write-LogAndConsole "Restart postponed. It is recommended to restart your computer as soon as possible."
        Read-Host "Press Enter to return to main menu"
    }
}

function MigrateUserProfile {
    Clear-Host
    Write-Host "================================================"
    Write-Host "           USER PROFILE MIGRATION"
    Write-Host "================================================"
    Write-Host ""
    
    Write-LogAndConsole "*** Step 1: User profile selection ***"
    $userName = SelectUserProfile
    if ($userName -eq $null) {
        return
    }
    
    Write-LogAndConsole "*** Step 2: Target drive selection ***"
    $targetPath = SelectTargetDrive
    if ($targetPath -eq $null) {
        return
    }
    
    Clear-Host
    Write-Host "================================================"
    Write-Host "          MIGRATION CONFIRMATION"
    Write-Host "================================================"
    Write-Host ""
    Write-LogAndConsole "Migration parameters:"
    Write-LogAndConsole "- SOURCE profile: C:\Users\$userName"
    Write-LogAndConsole "- TARGET location: $targetPath\$userName"
    Write-Host ""
    
    $confirm = Read-Host "Start profile migration? (y/n)"
    if ($confirm.ToLower() -ne "y") {
        Write-LogAndConsole "Migration canceled by user"
        Read-Host "Press Enter to return to main menu"
        return
    }
    
    $copyStatus = CopyUserProfile -UserName $userName -TargetPath $targetPath
    if ($copyStatus -eq $null) {
        return
    }
    
    $linkCreated = CreateSymbolicLink -UserName $userName -TargetPath $targetPath -CopyStatus $copyStatus
    if (-not $linkCreated) {
        return
    }
    
    FinishOperation -UserName $userName -TargetPath $targetPath
}

function ManageAdminAccount {
    $adminName = GetBuiltInAdminName
    
    try {
        $adminAccount = Get-LocalUser -Name $adminName
        $status = if ($adminAccount.Enabled) { "Enabled" } else { "Disabled" }
        
        Write-Host ""
        Write-LogAndConsole "Managing built-in Administrator account"
        Write-LogAndConsole "Account name: $adminName"
        Write-LogAndConsole "Current status: $status"
        
        Write-Host ""
        Write-Host "1. $(if ($adminAccount.Enabled) { 'Disable' } else { 'Enable' }) Administrator account"
        Write-Host "0. Return to main menu"
        
        $choice = Read-Host "Select action (0-1)"
        
        if ($choice -eq "1") {
            $action = if ($adminAccount.Enabled) { "Disable" } else { "Enable" }
            $result = ToggleUserAccount -Username $adminName -Action $action
            
            if ($result) {
                $actionText = if ($action -eq "Enable") { "enabled" } else { "disabled" }
                Write-LogAndConsole "Administrator account successfully $actionText"
            } else {
                Write-LogAndConsole "Error changing Administrator account status"
            }
            
            Write-Host ""
            Read-Host "Press Enter to return to menu"
        }
    } catch {
        Write-LogAndConsole "Error managing Administrator account: $($_.Exception.Message)"
        Write-Host ""
        Read-Host "Press Enter to return to menu"
    }
}

function SwitchToAdminAccount {
    $adminName = GetBuiltInAdminName
    
    try {
        $adminAccount = Get-LocalUser -Name $adminName
        
        Write-Host ""
        Write-Host "================================================"
        Write-Host "          WINDOWS USER PROFILE MIGRATION"
        Write-Host "================================================"
        Write-Host ""
        Write-LogAndConsole "This script allows you to migrate a user profile to another drive"
        Write-LogAndConsole "and create a symbolic link for seamless system operation."
        Write-Host ""
        
        if ($adminAccount.Enabled) {
            Write-LogAndConsole "Administrator account ($adminName) is enabled"
            Write-Host "You can deactivate it to improve system security."
            Write-Host ""
            
            $confirmDisable = Read-Host "Disable Administrator account? (y/n)"
            
            if ($confirmDisable.ToLower() -eq "y") {
                $adminDisabled = ToggleUserAccount -Username $adminName -Action "Disable"
                
                if ($adminDisabled) {
                    Write-LogAndConsole "Administrator account ($adminName) successfully disabled"
                } else {
                    Write-LogAndConsole "Failed to disable Administrator account"
                }
                
                Read-Host "Press Enter to exit"
                exit
            } else {
                Write-LogAndConsole "Operation canceled by user"
                Read-Host "Press Enter to exit"
                exit
            }
        } else {
            Write-LogAndConsole "Administrator account ($adminName) is disabled"
            Write-LogAndConsole "Administrator account must be enabled to migrate user profile."
            Write-Host ""
            
            $confirmEnable = Read-Host "Enable Administrator account and log off? (y/n)"
            
            if ($confirmEnable.ToLower() -eq "y") {
                $adminEnabled = ToggleUserAccount -Username $adminName -Action "Enable"
                
                if ($adminEnabled) {
                    Write-LogAndConsole "Administrator account ($adminName) successfully enabled"
                    
                    $currentUser = $env:USERNAME
                    Write-LogAndConsole "Disabling current user account ($currentUser)..."
                    
                    $command = "Disable-LocalUser -Name '$currentUser'; logoff"
                    
                    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
                    Start-Process -FilePath "powershell.exe" -ArgumentList "-EncodedCommand $encodedCommand" -WindowStyle Hidden
                    
                    Write-LogAndConsole "Ending session..."
                    Write-LogAndConsole "Log in with Administrator account and run the script again."
                    Start-Sleep -Seconds 2
                    exit
                } else {
                    Write-LogAndConsole "Failed to enable Administrator account"
                    Read-Host "Press Enter to exit"
                    exit
                }
            } else {
                Write-LogAndConsole "Operation canceled by user"
                Read-Host "Press Enter to exit"
                exit
            }
        }
    } catch {
        Write-LogAndConsole "Error checking Administrator account status: $($_.Exception.Message)"
        Read-Host "Press Enter to exit"
        exit
    }
}

function ShowAdminMenu {
    $continue = $true
    
    while ($continue) {
        Clear-Host
        Write-Host "================================================"
        Write-Host "          WINDOWS USER PROFILE MIGRATION"
        Write-Host "================================================"
        Write-Host ""
        Write-Host "Current user: $env:USERNAME"
        Write-Host ""
        Write-Host "1. Start user profile migration"
        Write-Host "2. Manage user accounts"
        Write-Host "0. Exit"
        Write-Host ""
        
        $choice = Read-Host "Select action (0-2)"
        
        switch ($choice) {
            "1" { MigrateUserProfile }
            "2" { ManageUserAccount }
            "0" { $continue = $false }
            default { 
                Write-Host "Invalid input. Press Enter to continue..." 
                Read-Host
            }
        }
    }
}

function ShowUserMenu {
    SwitchToAdminAccount
}

if (-not (IsAdmin)) {
    Write-LogAndConsole "Administrator rights required to run this script!"
    Write-LogAndConsole "Please restart with administrator privileges."
    Read-Host "Press Enter to exit"
    exit 1
}

if (IsBuiltInAdmin) {
    ShowAdminMenu
} else {
    Write-Host ""
    Write-LogAndConsole "WARNING: Not running as built-in Administrator account"
    Write-LogAndConsole "For full functionality, it is recommended to run the script"
    Write-LogAndConsole "as the built-in administrator account."
    Write-Host ""
    
    ShowUserMenu
}

Write-LogAndConsole "Script completed." 
