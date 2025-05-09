﻿$ErrorActionPreference = "Stop"
$ScriptVersion = "1.0.3"

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$DateTime = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$LogsDirectory = Join-Path -Path $ScriptPath -ChildPath "Logs"
if (-not (Test-Path -Path $LogsDirectory)) {
    New-Item -Path $LogsDirectory -ItemType Directory -Force | Out-Null
}
$LogFile = "$LogsDirectory\MoveUserProfile_$DateTime.log"
$UsersProfileRoot = $env:SystemDrive + "\Users"

"========================================" | Out-File -FilePath $LogFile -Encoding utf8
"Скрипт запущен: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $LogFile -Append -Encoding utf8
"========================================" | Out-File -FilePath $LogFile -Append -Encoding utf8

function Write-LogAndConsole {
    param([string]$Message)
    $Message | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Host $Message
}

function Show-Header {
    param(
        [Parameter(Mandatory = $false)]
        [string]$StepDescription = ""
    )
    
    Clear-Host
    
    $titleWithVersion = "МИГРАЦИЯ ПРОФИЛЯ ПОЛЬЗОВАТЕЛЯ WINDOWS v$ScriptVersion"
    $desc = if ($StepDescription -ne "") { "* $StepDescription *" } else { "" }
    $maxLength = [math]::Max($titleWithVersion.Length, $desc.Length)
    $width = $maxLength + 10
    
    $border = "=" * $width
    
    Write-Host $border
    
    $titleSpaces = [math]::Max(0, [math]::Floor(($width - $titleWithVersion.Length) / 2))
    Write-Host (" " * $titleSpaces + $titleWithVersion)
    
    if ($StepDescription -ne "") {
        Write-Host ""
        $descSpaces = [math]::Max(0, [math]::Floor(($width - $desc.Length) / 2))
        Write-Host (" " * $descSpaces + $desc)
    }
    
    Write-Host $border
    Write-Host ""
}

function IsAdmin {
    return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function IsBuiltInAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    return $currentUser.User.Value -match "-500$"
}

function GetBuiltInAdminName {
    try {
        $adminAccount = Get-LocalUser | Where-Object { $_.SID.Value -match "-500$" }
        return $adminAccount.Name
    } catch {
        Write-LogAndConsole "Ошибка получения имени встроенной учетной записи администратора: $($_.Exception.Message)"
        return "Administrator"
    }
}

function ToggleUserAccount {
    param(
        [string]$Username,
        [ValidateSet("Enable", "Disable")] 
        [string]$Action = "Enable"
    )
    
    $actionText = if ($Action -eq "Enable") { "Включение" } else { "Отключение" }
    $cmdlet = if ($Action -eq "Enable") { "Enable-LocalUser" } else { "Disable-LocalUser" }
    
    Write-LogAndConsole "$actionText учетной записи пользователя $Username..."
    
    try {
        & $cmdlet -Name $Username
        Write-LogAndConsole "Учетная запись пользователя $Username успешно $(if ($Action -eq "Enable") { "включена" } else { "отключена" })"
        return $true
    } catch {
        Write-LogAndConsole "ОШИБКА при $($actionText.ToLower()) учетной записи пользователя $Username`: $($_.Exception.Message)"
        try {
            Start-Process -FilePath "powershell.exe" -ArgumentList "-Command $cmdlet -Name `"$Username`"" -Verb RunAs -Wait
            return $true
        } catch {
            Write-LogAndConsole "Не удалось выполнить команду с повышенными привилегиями: $($_.Exception.Message)"
            return $false
        }
    }
}

function GetNonSystemUsers {
    return Get-LocalUser | Where-Object { 
        $_.SID.Value -notmatch "-50[0-3]$" -and
        $_.SID.Value -notin @("S-1-5-18", "S-1-5-19", "S-1-5-20") -and
        $_.Name -ne "WDAGUtilityAccount"
    }
}

function FormatFileSize {
    param ([long]$SizeInBytes)
    
    if ($SizeInBytes -ge 1TB) {
        return "{0:N2} TB" -f ($SizeInBytes / 1TB)
    } elseif ($SizeInBytes -ge 1GB) {
        return "{0:N2} GB" -f ($SizeInBytes / 1GB)
    } elseif ($SizeInBytes -ge 1MB) {
        return "{0:N2} MB" -f ($SizeInBytes / 1MB)
    } elseif ($SizeInBytes -ge 1KB) {
        return "{0:N2} KB" -f ($SizeInBytes / 1KB)
    } else {
        return "$SizeInBytes bytes"
    }
}

function ShowUserAccounts {
    Show-Header -StepDescription "Выбор учетной записи для управления"
    
    $allUsers = GetNonSystemUsers
    
    Write-LogAndConsole "Список учетных записей пользователей:"
    
    for ($i = 0; $i -lt $allUsers.Count; $i++) {
        $status = if ($allUsers[$i].Enabled) { "Активна" } else { "Неактивна" }
        Write-LogAndConsole "  $($i+1). $($allUsers[$i].Name) - Статус: $status"
    }
    
    do {
        Write-Host "`n0. Вернуться в главное меню"
        $input = Read-Host "Выберите номер учетной записи для управления (0-$($allUsers.Count))"
        
        if ($input -eq "0") { return $null }
    
        try { $selectedIndex = [int]$input }
        catch { $selectedIndex = 0 }
    } while ($selectedIndex -lt 1 -or $selectedIndex -gt $allUsers.Count)
    
    return $allUsers[$selectedIndex - 1]
}

function ManageUserAccount {
    Show-Header -StepDescription "Шаг 1: Выбор учетной записи"
    
    $selectedUser = ShowUserAccounts
    if ($null -eq $selectedUser) { return }
    
    Show-Header -StepDescription "Шаг 2: Управление выбранной учетной записью"
    
    $currentStatus = $selectedUser.Enabled
    
    Write-Host "`nУчетная запись: $($selectedUser.Name)"
    Write-Host "Текущий статус: $(if ($currentStatus) { 'Активна' } else { 'Неактивна' })"
    Write-Host "`nВыберите действие:"
    Write-Host "1. $(if ($currentStatus) { 'Отключить' } else { 'Включить' }) учетную запись"
    Write-Host "0. Вернуться назад"
    
    $action = Read-Host "Ваш выбор (0-1)"
    
    if ($action -eq "1") {
        $toggleAction = if ($currentStatus) { "Disable" } else { "Enable" }
        $result = ToggleUserAccount -Username $selectedUser.Name -Action $toggleAction
        
        if ($result) {
            Write-LogAndConsole "Учетная запись пользователя $($selectedUser.Name) успешно $(if ($currentStatus) { 'отключена' } else { 'включена' })"
        }
    }
}

function SelectUserProfile {
    $usersWithProfiles = @()
    $allUsers = GetNonSystemUsers
        
    foreach ($user in $allUsers) {
        $userProfilePath = "$UsersProfileRoot\$($user.Name)"
        if (Test-Path $userProfilePath) {
            $usersWithProfiles += $user.Name
        }
    }
    
    if ($usersWithProfiles.Count -eq 0) {
        Write-LogAndConsole "ОШИБКА: Не найдено доступных профилей пользователей для миграции!"
        Read-Host "Нажмите Enter, чтобы вернуться в главное меню"
        return $null
    }
    
    Show-Header -StepDescription "Шаг 1.1: Выбор профиля пользователя для миграции"
    
    Write-LogAndConsole "Найдены следующие профили пользователей"
    Write-Host ""
        
    for ($i = 0; $i -lt $usersWithProfiles.Count; $i++) {
        $userProPath = "$UsersProfileRoot\$($usersWithProfiles[$i])"
        $userProSize = (Get-ChildItem -Path $userProPath -Recurse -Force -ErrorAction SilentlyContinue | 
                        Measure-Object -Property Length -Sum).Sum
        $formattedSize = FormatFileSize -SizeInBytes $userProSize
        Write-LogAndConsole "  $($i+1). $($usersWithProfiles[$i]) - размер: $formattedSize (ИСТОЧНИК: $userProPath)"
    }
    
    Write-Host ""
    
    if ($usersWithProfiles.Count -eq 1) {
        $confirmSelect = Read-Host "Найден только один профиль пользователя. Использовать его для миграции? (д/н)"
        
        if ($confirmSelect.ToLower() -eq "д") {
            Write-LogAndConsole "Выбран ИСХОДНЫЙ профиль пользователя: $UsersProfileRoot\$($usersWithProfiles[0])"
            return $usersWithProfiles[0]
        } else {
            Write-LogAndConsole "Выбор профиля отменен"
            return $null
        }
    } else {
        do {
            Write-Host "0. Вернуться в главное меню"
            $input = Read-Host "Введите номер профиля для миграции (1-$($usersWithProfiles.Count)) или 0 для отмены"
            
            if ($input -eq "0") { return $null }
            
            try { $selectedIndex = [int]$input } 
            catch { $selectedIndex = 0 }
        } while ($selectedIndex -lt 1 -or $selectedIndex -gt $usersWithProfiles.Count)
        
        $selectedUser = $usersWithProfiles[$selectedIndex - 1]
        Write-LogAndConsole "Выбран ИСХОДНЫЙ профиль пользователя: $UsersProfileRoot\$selectedUser"
        return $selectedUser
    }
}

function SelectTargetDrive {
    Show-Header -StepDescription "Шаг 1.2: Выбор диска для хранения профиля"
    
    Write-LogAndConsole "Выберите диск, на который будет перенесен профиль пользователя"
    Write-LogAndConsole "ИСХОДНЫЙ профиль останется в C:\Users\{имя пользователя} в виде символической ссылки"
    Write-Host ""
    
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -ne "C" -and $_.Free -gt 0 }
    
    if ($drives.Count -eq 0) {
        Write-LogAndConsole "ОШИБКА: Не найдено доступных дисков, кроме системного диска (C:)!"
        Read-Host "Нажмите Enter, чтобы вернуться в главное меню"
        return $null
    }
    
    Write-LogAndConsole "Доступные ЦЕЛЕВЫЕ диски:"
    Write-Host ""
    
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $drive = $drives[$i]
        $freeGB = [math]::Round($drive.Free / 1GB, 2)
        $totalGB = [math]::Round(($drive.Free + $drive.Used) / 1GB, 2)
        $percentFree = [math]::Round(($drive.Free / ($drive.Free + $drive.Used)) * 100, 1)
        Write-LogAndConsole "  $($i+1). Диск $($drive.Name): - Свободно $freeGB ГБ из $totalGB ГБ ($percentFree% свободно)"
    }
    
    Write-Host ""
    
    if ($drives.Count -eq 1) {
        $confirmSelect = Read-Host "Найден только один доступный диск. Использовать его для миграции? (д/н)"
        
        if ($confirmSelect.ToLower() -eq "д") {
            $targetPath = "$($drives[0].Name):\Users"
            Write-LogAndConsole "Выбран ЦЕЛЕВОЙ диск: $($drives[0].Name): - Целевая папка: $targetPath"
            return $targetPath
        } else {
            Write-LogAndConsole "Выбор диска отменен"
            return $null
        }
    } else {
        do {
            Write-Host "0. Вернуться в главное меню"
            $input = Read-Host "Введите номер диска для миграции профиля (1-$($drives.Count)) или 0 для отмены"
            
            if ($input -eq "0") { return $null }
            
            try { $selection = [int]$input } 
            catch { $selection = 0 }
        } while ($selection -lt 1 -or $selection -gt $drives.Count)
        
        $targetPath = "$($drives[$selection - 1].Name):\Users"
        Write-LogAndConsole "Выбран ЦЕЛЕВОЙ диск: $($drives[$selection - 1].Name): - Целевая папка: $targetPath"
        return $targetPath
    }
}

function IsSymbolicLink {
    param(
        [string]$Path
    )
    
    if (Test-Path $Path) {
        $item = Get-Item $Path -Force
        return ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
    }
    
    return $false
}

function CopyUserProfile {
    param (
        [string]$UserName,
        [string]$TargetPath
    )
    
    Show-Header -StepDescription "Шаг 1.3: Копирование профиля пользователя"
    
    $sourceUserProfile = "$UsersProfileRoot\$UserName"
    $targetUserProfile = "$TargetPath\$UserName"
    
    $isSourceSymLink = IsSymbolicLink -Path $sourceUserProfile
    $isTargetSymLink = (Test-Path $targetUserProfile) -and (IsSymbolicLink -Path $targetUserProfile)
    
    if ($isSourceSymLink) {
        $sourceTarget = (Get-Item $sourceUserProfile -Force).Target
        Write-LogAndConsole "ВНИМАНИЕ: Исходный профиль '$sourceUserProfile' уже является символической ссылкой на '$sourceTarget'"
        Write-LogAndConsole "Миграция уже была выполнена ранее."
        Read-Host "Нажмите Enter, чтобы вернуться в главное меню"
        return $null
    }
    
    if ($isTargetSymLink) {
        $targetTarget = (Get-Item $targetUserProfile -Force).Target
        Write-LogAndConsole "ВНИМАНИЕ: Целевой профиль '$targetUserProfile' уже является символической ссылкой на '$targetTarget'"
        Write-LogAndConsole "Миграция в этом случае не поддерживается, так как это необычная конфигурация."
        Read-Host "Нажмите Enter, чтобы вернуться в главное меню"
        return $null
    }
    
    if (-not (Test-Path $TargetPath)) {
        Write-LogAndConsole "Создание папки $TargetPath"
        try {
            New-Item -Path $TargetPath -ItemType Directory -Force | Out-Null
        } catch {
            Write-LogAndConsole "ОШИБКА: Не удалось создать папку $TargetPath`: $($_.Exception.Message)"
            Read-Host "Нажмите Enter, чтобы вернуться в главное меню"
            return $null
        }
    }
    
    if (Test-Path $targetUserProfile) {
        Write-LogAndConsole "ВНИМАНИЕ: Профиль уже существует в целевом расположении: $targetUserProfile"
        Write-Host ""
        Write-Host "Выберите действие:"
        Write-Host "1. Переименовать целевой профиль '$targetUserProfile' в '${targetUserProfile}_old' и продолжить миграцию"
        Write-Host "2. Переименовать исходный профиль '$UsersProfileRoot\$UserName' в 'C:\Users\${UserName}_old' и использовать целевой профиль"
        Write-Host "3. Заменить существующий профиль на целевом диске '$targetUserProfile'"
        Write-Host "0. Вернуться в главное меню"
        
        $action = Read-Host "Ваш выбор (0-3)"
        
        if ($action -eq "0") {
            return $null
        } elseif ($action -eq "3") {
            Write-LogAndConsole "Замена существующего профиля на целевом диске: $targetUserProfile"
            try {
                Remove-Item -Path $targetUserProfile -Force -Recurse
                Write-LogAndConsole "Существующий профиль на целевом диске удален"
            } catch {
                Write-LogAndConsole "ОШИБКА при удалении существующего профиля: $($_.Exception.Message)"
                
                if ((Read-Host "Продолжить, несмотря на ошибки? (1-да/0-нет)") -eq "1") {
                    return $null
                }
            }
        } elseif ($action -eq "2") {
            Write-LogAndConsole "Переименование исходного профиля и использование существующего целевого профиля"
            
            $oldSourceProfile = "${sourceUserProfile}_old"
            if (Test-Path $oldSourceProfile) {
                $oldSourceProfile = "${sourceUserProfile}_old_$(Get-Date -Format "yyyyMMdd_HHmmss")"
            }
            
            try {
                Write-LogAndConsole "Переименование исходного профиля в $oldSourceProfile"
                Rename-Item -Path $sourceUserProfile -NewName $oldSourceProfile -Force
                
                Write-LogAndConsole "Создание символической ссылки из $sourceUserProfile на $targetUserProfile"
                cmd /c mklink /d "`"$sourceUserProfile`"" "`"$targetUserProfile`""
                
                if (Test-Path $sourceUserProfile) {
                    $linkItem = Get-Item $sourceUserProfile -Force
                    if ($linkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                        Write-LogAndConsole "Символическая ссылка успешно создана"
                        return "source_renamed"
                    } else {
                        Write-LogAndConsole "ОШИБКА: Не удалось создать символическую ссылку"
                        
                        try {
                            Write-LogAndConsole "Восстановление исходного профиля"
                            Remove-Item -Path $sourceUserProfile -Force -ErrorAction SilentlyContinue
                            Rename-Item -Path $oldSourceProfile -NewName $sourceUserProfile -Force
                            Write-LogAndConsole "Исходный профиль восстановлен"
                        } catch {
                            Write-LogAndConsole "КРИТИЧЕСКАЯ ОШИБКА: Не удалось восстановить профиль: $($_.Exception.Message)"
                        }
                        
                        Read-Host "Нажмите Enter, чтобы вернуться в главное меню"
                        return $null
                    }
                } else {
                    Write-LogAndConsole "ОШИБКА: Не удалось создать символическую ссылку"
                    
                    try {
                        Write-LogAndConsole "Восстановление исходного профиля"
                        Rename-Item -Path $oldSourceProfile -NewName $sourceUserProfile -Force
                        Write-LogAndConsole "Исходный профиль восстановлен"
                    } catch {
                        Write-LogAndConsole "КРИТИЧЕСКАЯ ОШИБКА: Не удалось восстановить профиль: $($_.Exception.Message)"
                    }
                    
                    Read-Host "Нажмите Enter, чтобы вернуться в главное меню"
                    return $null
                }
            } catch {
                Write-LogAndConsole "ОШИБКА при переименовании исходного профиля: $($_.Exception.Message)"
                Read-Host "Нажмите Enter, чтобы вернуться в главное меню"
                return $null
            }
        } elseif ($action -eq "1") {
            $oldTargetProfile = "${targetUserProfile}_old"
            if (Test-Path $oldTargetProfile) {
                $oldTargetProfile = "${targetUserProfile}_old_$(Get-Date -Format "yyyyMMdd_HHmmss")"
            }
            
            try {
                Write-LogAndConsole "Переименование целевого профиля в $oldTargetProfile"
                Rename-Item -Path $targetUserProfile -NewName $oldTargetProfile -Force
                Write-LogAndConsole "Целевой профиль успешно переименован"
            } catch {
                Write-LogAndConsole "ОШИБКА при переименовании целевого профиля: $($_.Exception.Message)"
                
                if ((Read-Host "Продолжить, несмотря на ошибки? (1-да/0-нет)") -eq "1") {
                    return $null
                }
            }
        } else {
            Write-LogAndConsole "Некорректный ввод. Возврат в главное меню."
            return $null
        }
    }
    
    if ($action -eq "2") {
        return "source_renamed"
    }
    
    Write-LogAndConsole "Копирование профиля пользователя из $sourceUserProfile в $targetUserProfile"
    
    if (-not (Test-Path $targetUserProfile)) {
        try {
            New-Item -Path $targetUserProfile -ItemType Directory -Force | Out-Null
        } catch {
            Write-LogAndConsole "ОШИБКА: Не удалось создать целевую папку: $($_.Exception.Message)"
            Read-Host "Нажмите Enter, чтобы вернуться в главное меню"
            return $null
        }
    }
    
    try {
        $userSize = (Get-ChildItem -Path $sourceUserProfile -Recurse -Force -ErrorAction SilentlyContinue | 
                    Measure-Object -Property Length -Sum).Sum
        $formattedSize = FormatFileSize -SizeInBytes $userSize
        
        Write-LogAndConsole "Размер профиля для копирования: $formattedSize"
        Write-LogAndConsole "Запуск процесса копирования. Это может занять продолжительное время..."
        Write-Host ""
        Write-Host "Для отслеживания прогресса наблюдайте за активностью на дисках и за сообщениями ниже:"
        
        $progressDir = "$env:TEMP\ProfileMigrationProgress_$DateTime"
        New-Item -Path $progressDir -ItemType Directory -Force | Out-Null
        
        $monitorScript = {
            param ($targetDir, $progressDir)
            
            while ($true) {
                $stats = Get-ChildItem -Path $targetDir -Recurse -Force -ErrorAction SilentlyContinue | 
                        Measure-Object -Property Length -Sum
                $currentSize = $stats.Sum
                $fileCount = $stats.Count
                
                "$currentSize|$fileCount" | Out-File -FilePath "$progressDir\progress.txt" -Force
                
                Start-Sleep -Seconds 5
            }
        }
        
        $monitorJob = Start-Job -ScriptBlock $monitorScript -ArgumentList $targetUserProfile, $progressDir
        
        $robocopyArgs = "`"$sourceUserProfile`" `"$targetUserProfile`" /E /COPYALL /DCOPY:T /R:3 /W:5 /MT /XJ"
        Write-LogAndConsole "Выполнение команды: robocopy $robocopyArgs"
        
        $robocopyProcess = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
        
        Stop-Job -Job $monitorJob
        Remove-Job -Job $monitorJob
        Remove-Item -Path $progressDir -Recurse -Force -ErrorAction SilentlyContinue
        
        if ($robocopyProcess.ExitCode -lt 8) {
            Write-LogAndConsole "Копирование профиля успешно завершено"
            return "success"
        } else {
            Write-LogAndConsole "ВНИМАНИЕ: Процесс копирования завершен с ошибками (код $($robocopyProcess.ExitCode))"
            
            if ((Read-Host "Продолжить, несмотря на ошибки? (1-да/0-нет)") -eq "1") {
                return "errors"
            } else {
                return $null
            }
        }
    } catch {
        Write-LogAndConsole "ОШИБКА при копировании профиля: $($_.Exception.Message)"
        
        if ((Read-Host "Продолжить, несмотря на ошибки? (1-да/0-нет)") -eq "1") {
            return "errors"
        } else {
            return $null
        }
    }
}

function CreateSymLink {
    param (
        [string]$Source,
        [string]$Target,
        [switch]$IsDirectory = $true
    )
    
    $safeSource = $Source -replace '"', '\"'
    $safeTarget = $Target -replace '"', '\"'
    
    $dirFlag = if ($IsDirectory) { "/d" } else { "" }
    
    try {
        Write-LogAndConsole "Создание символической ссылки из $Source на $Target"
        cmd /c mklink $dirFlag "`"$safeSource`"" "`"$safeTarget`""
        
        if (Test-Path $Source) {
            $linkItem = Get-Item $Source -Force
            if ($linkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                Write-LogAndConsole "Символическая ссылка успешно создана"
                return $true
            }
        }
        
        Write-LogAndConsole "ОШИБКА: Не удалось создать символическую ссылку"
        return $false
    }
    catch {
        Write-LogAndConsole "ОШИБКА при создании символической ссылки: $($_.Exception.Message)"
        return $false
    }
}

function CreateSymbolicLink {
    param (
        [string]$UserName,
        [string]$TargetPath,
        [string]$CopyStatus
    )
    
    if ($CopyStatus -eq "source_renamed" -or $CopyStatus -eq "already_migrated") {
        Write-LogAndConsole "Пропуск создания символической ссылки (исходный профиль уже $(if ($CopyStatus -eq 'source_renamed') { 'переименован и связан' } else { 'является символической ссылкой' }))"
        return $true
    }
    
    Show-Header -StepDescription "Шаг 1.4: Создание символической ссылки для профиля пользователя"
    
    $sourceUserProfile = "$UsersProfileRoot\$UserName"
    $targetUserProfile = "$TargetPath\$UserName"
    
    try {
        if (Test-Path $sourceUserProfile) {
            $isSourceSymLink = IsSymbolicLink -Path $sourceUserProfile
            
            if ($isSourceSymLink) {
                $existingTarget = (Get-Item $sourceUserProfile -Force).Target
                Write-LogAndConsole "Обнаружено: исходный профиль '$sourceUserProfile' уже является символической ссылкой на '$existingTarget'"
                
                if ($existingTarget -eq $targetUserProfile) {
                    Write-LogAndConsole "Символическая ссылка уже настроена правильно и указывает на целевой профиль"
                    return $true
                } else {
                    Write-LogAndConsole "Текущая ссылка указывает на другой профиль. Необходимо её обновить."
                    
                    try {
                        Remove-Item -Path $sourceUserProfile -Force
                        Write-LogAndConsole "Существующая ссылка удалена"
                    } catch {
                        Write-LogAndConsole "ОШИБКА при удалении существующей ссылки: $($_.Exception.Message)"
                        Read-Host "Нажмите Enter для возврата в главное меню"
                        return $false
                    }
                }
            } else {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $backupDir = "$UsersProfileRoot\${UserName}_backup_$timestamp"
                
                try {
                    Write-LogAndConsole "Переименование исходного профиля в $backupDir"
                    Rename-Item -Path $sourceUserProfile -NewName $backupDir -Force
                } catch {
                    Write-LogAndConsole "ОШИБКА при переименовании профиля: $($_.Exception.Message)"
                    Write-LogAndConsole "Попытка прямого удаления папки..."
                    
                    try {
                        Remove-Item -Path $sourceUserProfile -Force -Recurse
                    } catch {
                        Write-LogAndConsole "ОШИБКА при удалении исходного профиля: $($_.Exception.Message)"
                        
                        if ((Test-Path $sourceUserProfile) -and 
                            ((Get-Item $sourceUserProfile -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                                
                            try {
                                $linkTarget = (Get-Item $sourceUserProfile).Target
                                if ($linkTarget -eq $targetUserProfile) {
                                    Write-LogAndConsole "Существующая символическая ссылка уже указывает на $targetUserProfile"
                                    return $true
                                } else {
                                    Write-LogAndConsole "Текущая ссылка указывает на $linkTarget, удаление..."
                                    Remove-Item -Path $sourceUserProfile -Force
                                }
                            } catch {
                                Write-LogAndConsole "ОШИБКА при работе с существующей ссылкой: $($_.Exception.Message)"
                                Read-Host "Нажмите Enter для возврата в главное меню"
                                return $false
                            }
                        } else {
                            Write-LogAndConsole "Не удалось удалить или переместить папку исходного профиля"
                            Read-Host "Нажмите Enter для возврата в главное меню"
                            return $false
                        }
                    }
                }
            }
        }
        
        $linkCreated = CreateSymLink -Source $sourceUserProfile -Target $targetUserProfile -IsDirectory
        
        if (-not $linkCreated) {
            if (Test-Path $backupDir) {
                Write-LogAndConsole "Восстановление из резервной копии $backupDir в $UsersProfileRoot\$UserName"
                Rename-Item -Path $backupDir -NewName $sourceUserProfile -Force
            } else {
                Write-LogAndConsole "КРИТИЧЕСКАЯ ОШИБКА: Исходный профиль пользователя удален, но ссылка не создана!"
            }
            
            Read-Host "Нажмите Enter для возврата в главное меню"
            return $false
        }
        
        Write-LogAndConsole "Проверка успешна: $UsersProfileRoot\$UserName теперь является символической ссылкой на $targetUserProfile"
        return $true
    } catch {
        Write-LogAndConsole "ОШИБКА при создании символической ссылки: $($_.Exception.Message)"
        Read-Host "Нажмите Enter для возврата в главное меню"
        return $false
    }
}

function FinishOperation {
    param (
        [string]$UserName,
        [string]$TargetPath,
        [string]$CopyStatus = ""
    )
    
    Show-Header -StepDescription "Шаг 1.5: Завершение процесса миграции"
    
    Write-LogAndConsole "Миграция профиля пользователя $UserName успешно завершена"
    
    if ($CopyStatus -eq "already_migrated") {
        Write-LogAndConsole "Профиль уже был перенесен ранее."
        Write-LogAndConsole "Исходное расположение профиля: $UsersProfileRoot\$UserName (символическая ссылка)"
        Write-LogAndConsole "Физическое расположение профиля: $((Get-Item $UsersProfileRoot\$UserName -Force).Target)"
    } else {
        Write-LogAndConsole "Исходное расположение профиля: $UsersProfileRoot\$UserName (теперь символическая ссылка)"
        Write-LogAndConsole "Новое физическое расположение профиля: $TargetPath\$UserName"
    }
    
    $null = ToggleUserAccount -Username $UserName -Action "Enable"
    
    if ((Read-Host "`n1. Перезагрузить компьютер сейчас`n0. Вернуться в главное меню`n`nВаш выбор (0-1)") -eq "1") {
        Write-LogAndConsole "Перезагрузка компьютера..."
        Restart-Computer -Force
    } else {
        Write-LogAndConsole "Перезагрузка отложена. Рекомендуется перезагрузить компьютер как можно скорее."
        Read-Host "Нажмите Enter, чтобы вернуться в главное меню"
    }
}

function MigrateUserProfile {
    Show-Header -StepDescription "Шаг 1: Мастер миграции профиля пользователя"
    
    Write-LogAndConsole "Это мастер поможет вам перенести профиль пользователя на другой диск"
    Write-LogAndConsole "с сохранением доступа через символическую ссылку из исходного места."
    Write-Host ""
    
    $userName = SelectUserProfile
    if ($null -eq $userName) { return }
    
    $targetPath = SelectTargetDrive
    if ($null -eq $targetPath) { return }
    
    Show-Header -StepDescription "Проверка выбранных параметров"
    
    Write-LogAndConsole "Параметры миграции:"
    Write-LogAndConsole "- ИСХОДНЫЙ профиль: $UsersProfileRoot\$userName"
    Write-LogAndConsole "- ЦЕЛЕВОЕ расположение: $targetPath\$userName"
    Write-Host ""
    
    if ((Read-Host "Начать миграцию профиля? (д/н)").ToLower() -ne "д") {
        Write-LogAndConsole "Миграция отменена пользователем"
        Read-Host "Нажмите Enter, чтобы вернуться в главное меню"
        return
    }
    
    $copyStatus = CopyUserProfile -UserName $userName -TargetPath $targetPath
    if ($null -eq $copyStatus) { return }
    
    $linkCreated = CreateSymbolicLink -UserName $userName -TargetPath $targetPath -CopyStatus $copyStatus
    if (-not $linkCreated) { return }
    
    FinishOperation -UserName $userName -TargetPath $targetPath -CopyStatus $copyStatus
}

function ManageAdminAccount {
    Show-Header -StepDescription "Управление учетной записью администратора"
    
    $adminName = GetBuiltInAdminName
    
    try {
        $adminAccount = Get-LocalUser -Name $adminName
        $status = if ($adminAccount.Enabled) { "Включена" } else { "Отключена" }
        
        Write-LogAndConsole "Имя учетной записи: $adminName"
        Write-LogAndConsole "Текущий статус: $status"
        
        if ((Read-Host "`n1. $(if ($adminAccount.Enabled) { 'Отключить' } else { 'Включить' }) учетную запись администратора`n0. Вернуться в главное меню`n`nВыберите действие (0-1)") -eq "1") {
            $action = if ($adminAccount.Enabled) { "Disable" } else { "Enable" }
            $result = ToggleUserAccount -Username $adminName -Action $action
            
            if ($result) {
                $actionText = if ($action -eq "Enable") { "включена" } else { "отключена" }
                Write-LogAndConsole "Учетная запись администратора успешно $actionText"
            } else {
                Write-LogAndConsole "Ошибка изменения статуса учетной записи администратора"
            }
        }
        
        Read-Host "`nНажмите Enter для возврата в меню"
    } catch {
        Write-LogAndConsole "Ошибка управления учетной записью администратора: $($_.Exception.Message)"
        Read-Host "`nНажмите Enter для возврата в меню"
    }
}

function SwitchToAdminAccount {
    Show-Header -StepDescription "Проверка необходимых разрешений"
    
    $adminName = GetBuiltInAdminName
    
    try {
        $adminAccount = Get-LocalUser -Name $adminName

        if ($adminAccount.Enabled) {
            Write-LogAndConsole "Учетная запись администратора: ВКЛЮЧЕНА"
            Write-Host "Вы можете деактивировать её для повышения безопасности системы."
            
            if ((Read-Host "`nОтключить учетную запись администратора? (д/н)").ToLower() -eq "д") {
                if (ToggleUserAccount -Username $adminName -Action "Disable") {
                    
                } else {
                    Write-LogAndConsole "Не удалось отключить учетную запись администратора"
                }
            } else {
                Write-LogAndConsole "Операция отменена пользователем"
            }
            
            Read-Host "Нажмите Enter для выхода"
            exit
        } else {
            Write-LogAndConsole "Учетная запись администратора: ОТКЛЮЧЕНА"
            Write-LogAndConsole "Для миграции профиля пользователя необходимо включить учетную запись администратора."

            if ((Read-Host "`nВключить учетную запись администратора и выйти из системы? (д/н)").ToLower() -eq "д") {
                if (ToggleUserAccount -Username $adminName -Action "Enable") {
                    
                    $currentUser = $env:USERNAME
                    Write-LogAndConsole "Отключение текущей учетной записи пользователя ($currentUser)..."
                    
                    $command = "Disable-LocalUser -Name '$currentUser'; logoff"
                    
                    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
                    Start-Process -FilePath "powershell.exe" -ArgumentList "-EncodedCommand $encodedCommand" -WindowStyle Hidden
                    
                    Write-LogAndConsole "Завершение сеанса..."
                    Write-LogAndConsole "Войдите с учетной записью администратора и запустите скрипт снова."
                    Start-Sleep -Seconds 2
                    exit
                } else {
                    Write-LogAndConsole "Не удалось включить учетную запись администратора"
                }
            } else {
                Write-LogAndConsole "Операция отменена пользователем"
            }
            
            Read-Host "Нажмите Enter для выхода"
            exit
        }
    } catch {
        Write-LogAndConsole "Ошибка проверки статуса учетной записи администратора: $($_.Exception.Message)"
        Read-Host "Нажмите Enter для выхода"
        exit
    }
}

function CheckMigrationStatus {
    Show-Header -StepDescription "Анализ состояния перенесенных профилей"
    
    Write-LogAndConsole "Проверка символических ссылок в профилях пользователей"
    Write-Host ""
    
    $allUsers = GetNonSystemUsers
    $migrationCount = 0
    
    foreach ($user in $allUsers) {
        $userProfilePath = "$UsersProfileRoot\$($user.Name)"
        
        if (Test-Path $userProfilePath) {
            $profileItem = Get-Item $userProfilePath -Force
            
            if ($profileItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                $targetPath = $profileItem.Target
                $migrationCount++
                
                Write-LogAndConsole "  [+] $($user.Name): Профиль перенесен, ссылка -> $targetPath"
                
                if (-not (Test-Path $targetPath)) {
                    Write-LogAndConsole "      ВНИМАНИЕ: Целевая папка недоступна!"
                }
            } else {
                Write-LogAndConsole "  [-] $($user.Name): Стандартный профиль (не перенесен)"
            }
        }
    }
    
    Write-Host ""
    
    if ($migrationCount -eq 0) {
        Write-LogAndConsole "На данный момент нет перенесенных профилей пользователей"
    } else {
        Write-LogAndConsole "Всего перенесенных профилей: $migrationCount"
    }
    
    Read-Host "`nНажмите Enter для возврата в главное меню"
}

function ShowAdminMenu {
    $continue = $true
    
    while ($continue) {
        Show-Header -StepDescription "Главное меню (режим администратора)"
        
        Write-Host "Текущий пользователь: $env:USERNAME"
        Write-Host ""
        Write-Host "1. Начать миграцию профиля пользователя"
        Write-Host "2. Управление учетными записями пользователей"
        Write-Host "3. Управление учетной записью администратора"
        Write-Host "4. Проверить состояние перенесенных профилей"
        Write-Host "0. Выход"
        
        switch (Read-Host "`nВыберите действие (0-4)") {
            "1" { MigrateUserProfile }
            "2" { ManageUserAccount }
            "3" { ManageAdminAccount }
            "4" { CheckMigrationStatus }
            "0" { $continue = $false }
            default { Read-Host "Некорректный ввод. Нажмите Enter для продолжения..." }
        }
    }
}

function ShowUserMenu {
    $continue = $true
    
    while ($continue) {
        Show-Header -StepDescription "Главное меню (режим пользователя)"
        
        Write-LogAndConsole "Этот скрипт позволяет перенести профиль пользователя на другой диск"
        Write-LogAndConsole "и создать символическую ссылку для бесшовной работы системы."
        Write-Host ""
        
        Write-Host "Текущий пользователь: $env:USERNAME"
        
        # Проверка статуса учётной записи администратора
        $adminName = GetBuiltInAdminName
        try {
            $adminAccount = Get-LocalUser -Name $adminName -ErrorAction Stop
            $status = if ($adminAccount.Enabled) { "ВКЛЮЧЕНА" } else { "ОТКЛЮЧЕНА" }
            
            if ($adminAccount.Enabled) {
                Write-LogAndConsole "Учетная запись администратора: $status"
                Write-LogAndConsole "Рекомендуется отключить её после использования для повышения безопасности."
            } else {
                Write-LogAndConsole "Учетная запись администратора: $status"
                Write-LogAndConsole "Для миграции профиля НЕОБХОДИМО включить учетную запись администратора."
                Write-LogAndConsole "Выберите пункт 2 для активации учетной записи администратора."
            }
        } catch {
            Write-LogAndConsole "Не удалось проверить статус учетной записи администратора: $($_.Exception.Message)"
        }
        
        Write-Host ""
        Write-Host "1. Проверить состояние перенесенных профилей"
        Write-Host "2. Управление учетной записью администратора"
        Write-Host "0. Выход"
        
        switch (Read-Host "`nВыберите действие (0-2)") {
            "1" { CheckMigrationStatus }
            "2" { SwitchToAdminAccount }
            "0" { $continue = $false }
            default { Read-Host "Некорректный ввод. Нажмите Enter для продолжения..." }
        }
    }
}

if (-not (IsAdmin)) {
    Write-LogAndConsole "Для выполнения этого скрипта требуются права администратора!"
    Write-LogAndConsole "Выполняется автоматический перезапуск с правами администратора..."
    
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`"" -Verb RunAs
    }
    catch {
        Write-LogAndConsole "Ошибка при попытке перезапуска с правами администратора: $($_.Exception.Message)"
        Write-LogAndConsole "Пожалуйста, перезапустите скрипт вручную с правами администратора."
    }
    
    Read-Host "Нажмите Enter для выхода"
    exit
}

if (IsBuiltInAdmin) {
    ShowAdminMenu
} else {
    ShowUserMenu
}

Write-LogAndConsole "Скрипт завершен." 
