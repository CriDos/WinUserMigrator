# Скрипт для переноса папки профилей пользователей

# Включение обработки ошибок
$ErrorActionPreference = "Stop"

# Настройка логирования
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$DateTime = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$LogFile = "$ScriptPath\MoveUserProfile_$DateTime.log"

# Начало логирования
"========================================" | Out-File -FilePath $LogFile -Encoding utf8
"Запуск скрипта: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $LogFile -Append -Encoding utf8
"========================================" | Out-File -FilePath $LogFile -Append -Encoding utf8

# Функция для одновременного вывода в консоль и лог
function Write-LogAndConsole {
    param(
        [string]$Message
    )
    $Message | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Host $Message
}

# Функция для принудительного выхода из системы
function ForceLogout {
    param(
        [int]$Timeout = 3
    )
    
    Write-LogAndConsole "Выполняется выход из системы..."
    
    # Выполняем команду выхода из системы
    Write-Host "Выполнение команды выхода..." -ForegroundColor Yellow
    & shutdown.exe /l /f
    
    # Форсированный выход из скрипта
    exit
}

# Функция для активации/деактивации учетной записи пользователя
function ToggleUserAccount {
    param(
        [string]$Username,
        [ValidateSet("Enable", "Disable")] 
        [string]$Action = "Enable"
    )
    
    $actionRu = if ($Action -eq "Enable") { "Активация" } else { "Деактивация" }
    $actionedRu = if ($Action -eq "Enable") { "активирована" } else { "деактивирована" }
    $cmdlet = if ($Action -eq "Enable") { "Enable-LocalUser" } else { "Disable-LocalUser" }
    $stateCheck = if ($Action -eq "Enable") { $true } else { $false }
    
    Write-LogAndConsole "$actionRu учетной записи пользователя $Username..."
    
    try {
        & $cmdlet -Name $Username
        Write-LogAndConsole "Учетная запись $Username успешно $actionedRu"
        return $true
    } catch {
        Write-LogAndConsole ("ОШИБКА при $($actionRu.ToLower()) учетной записи $Username`: {0}" -f $_.Exception.Message)
        try {
            Start-Process -FilePath "powershell.exe" -ArgumentList "-Command $cmdlet -Name `"$Username`"" -Verb RunAs -Wait
            # Проверяем успешность операции
            $userAccount = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
            if ($userAccount -ne $null -and $userAccount.Enabled -eq $stateCheck) {
                # Не выводим сообщение второй раз, результат будет отображен в вызывающем коде
                return $true
            } else {
                Write-LogAndConsole "ВНИМАНИЕ: Не удалось подтвердить $($actionRu.ToLower()) учетной записи $Username"
                if ($Action -eq "Enable") {
                    Write-LogAndConsole "Попробуйте активировать учетную запись вручную после завершения работы скрипта"
                }
                return $false
            }
        } catch {
            Write-LogAndConsole ("Не удалось выполнить команду с повышенными правами`: {0}" -f $_.Exception.Message)
            if ($Action -eq "Enable") {
                Write-LogAndConsole "Попробуйте активировать учетную запись $Username вручную после завершения работы скрипта"
            }
            return $false
        }
    }
}

# Функция для предложения перезагрузки
function OfferRestart {
    param(
        [string]$TargetPath
    )
    
    Write-LogAndConsole "Перенос профиля завершен."
    Write-LogAndConsole "Новое расположение профиля: $TargetPath"
    
    # Активируем учетную запись пользователя
    $userToEnable = $Global:SelectedUserName
    ToggleUserAccount -Username $userToEnable -Action "Enable"
    
    Write-Host ""
    
    $restart = Read-Host "Хотите перезагрузить компьютер сейчас? (y/n)"
    if ($restart -eq "y") {
        Write-LogAndConsole "Перезагрузка компьютера..."
        Restart-Computer -Force
    } else {
        Write-LogAndConsole "Перезагрузка отложена. Рекомендуется перезагрузить компьютер как можно скорее."
        Write-LogAndConsole "Завершение работы скрипта."
    }
}

# Проверка прав администратора
Write-LogAndConsole "Проверка прав администратора..."
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-LogAndConsole "Требуются права администратора!"
    Write-Host "Запустите скрипт от имени администратора."
    Read-Host "Нажмите Enter для выхода"
    exit 1
}
Write-LogAndConsole "Права администратора подтверждены"

# Определение типа текущей учетной записи и проверка статуса учетной записи Администратор
# Получаем данные из системы вместо хранения их в переменных
$currentUserName = $env:USERNAME
Write-LogAndConsole "Текущий пользователь: $currentUserName"

# Функция для проверки, является ли текущая учетная запись встроенным администратором
function IsBuiltInAdmin {
    $userName = $env:USERNAME
    return ($userName -eq "Administrator" -or $userName -eq "Администратор")
}

# Функция для получения имени встроенной учетной записи администратора
function GetBuiltInAdminName {
    # Проверка английской версии Administrator
    try {
        $adminEN = Get-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
        if ($adminEN -ne $null) {
            return "Administrator"
        }
    } catch {
        # Ничего не делаем, продолжаем проверку
    }
    
    # Проверка русской версии Администратор
    try {
        $adminRU = Get-LocalUser -Name "Администратор" -ErrorAction SilentlyContinue
        if ($adminRU -ne $null) {
            return "Администратор"
        }
    } catch {
        # Ничего не делаем, продолжаем проверку
    }
    
    return $null
}

# Функция для проверки активации учетной записи Администратор
function IsAdminAccountEnabled {
    param (
        [string]$AdminName
    )
    
    if ([string]::IsNullOrEmpty($AdminName)) {
        return $false
    }
    
    try {
        $adminAccount = Get-LocalUser -Name $AdminName -ErrorAction SilentlyContinue
        return ($adminAccount -ne $null -and $adminAccount.Enabled)
    } catch {
        return $false
    }
}

# Получаем имя встроенной учетной записи администратора 
$adminName = GetBuiltInAdminName
if ($adminName -eq $null) {
    Write-LogAndConsole "Встроенная учетная запись Administrator/Администратор не найдена в системе"
} else {
    $isAdminEnabled = IsAdminAccountEnabled -AdminName $adminName
    $isRunningAsBuiltInAdmin = IsBuiltInAdmin
    
    # Разные сценарии в зависимости от учетной записи, под которой запущен скрипт
    if ($isRunningAsBuiltInAdmin) {
        # Скрипт запущен под учетной записью Администратор
        Write-LogAndConsole "Запуск под учетной записью $adminName"
        
        # Предложение активировать пользовательские учетные записи
        Write-Host ""
        Write-Host "Выберите действие:"
        Write-Host "1. Активировать/деактивировать учетную запись пользователя"
        Write-Host "2. Продолжить с переносом профиля пользователя"
        
        $adminChoice = Read-Host "Выберите действие (1-2)"
        
        if ($adminChoice -eq "1") {
            # Получаем список всех локальных пользователей, кроме системных
            $allAccounts = Get-LocalUser | Where-Object { 
                $_.Name -ne "Administrator" -and 
                $_.Name -ne "Администратор" -and 
                $_.Name -ne "DefaultAccount" -and 
                $_.Name -ne "Гость" -and 
                $_.Name -ne "Guest" -and 
                $_.Name -ne "WDAGUtilityAccount" 
            }
            
            Write-Host ""
            Write-LogAndConsole "Список учетных записей пользователей:"
            for ($i = 0; $i -lt $allAccounts.Count; $i++) {
                $status = if ($allAccounts[$i].Enabled) { "Активна" } else { "Неактивна" }
                Write-LogAndConsole "  $($i+1). $($allAccounts[$i].Name) - Статус: $status"
            }
            
            Write-Host ""
            $accountIndex = 0
            do {
                try {
                    $accountIndex = [int](Read-Host "Выберите номер учетной записи для активации/деактивации (1-$($allAccounts.Count))")
                } catch {
                    $accountIndex = 0
                }
            } while ($accountIndex -lt 1 -or $accountIndex -gt $allAccounts.Count)
            
            $selectedAccount = $allAccounts[$accountIndex - 1]
            $currentStatus = $selectedAccount.Enabled
            
            Write-Host ""
            if ($currentStatus) {
                Write-LogAndConsole "Учетная запись $($selectedAccount.Name) в настоящее время активирована"
                $action = Read-Host "Деактивировать учетную запись $($selectedAccount.Name)? (y/n)"
                
                if ($action -eq "y") {
                    $result = ToggleUserAccount -Username $selectedAccount.Name -Action "Disable"
                    if ($result) {
                        Write-LogAndConsole "Учетная запись $($selectedAccount.Name) успешно деактивирована"
                    }
                } else {
                    Write-LogAndConsole "Действие отменено"
                }
            } else {
                Write-LogAndConsole "Учетная запись $($selectedAccount.Name) в настоящее время деактивирована"
                $action = Read-Host "Активировать учетную запись $($selectedAccount.Name)? (y/n)"
                
                if ($action -eq "y") {
                    $result = ToggleUserAccount -Username $selectedAccount.Name -Action "Enable"
                    if ($result) {
                        Write-LogAndConsole "Учетная запись $($selectedAccount.Name) успешно активирована"
                    }
                } else {
                    Write-LogAndConsole "Действие отменено"
                }
            }
            
            # Предлагаем вернуться к основному меню или выйти
            Write-Host ""
            $continueScript = Read-Host "Продолжить работу со скриптом? (y/n)"
            if ($continueScript -ne "y") {
                Write-LogAndConsole "Выход из скрипта по запросу пользователя"
                exit 0
            }
            
            Write-Host ""
            Write-LogAndConsole "Продолжение работы скрипта"
        }
        
        # Определяем, какую учетную запись будем переносить
        $usersToMove = @()
        
        # Получаем список всех локальных пользователей, кроме системных
        $allUsers = Get-LocalUser | Where-Object { 
            $_.Name -ne "Administrator" -and 
            $_.Name -ne "Администратор" -and 
            $_.Name -ne "DefaultAccount" -and 
            $_.Name -ne "Гость" -and 
            $_.Name -ne "Guest" -and 
            $_.Name -ne "WDAGUtilityAccount" 
        }
        
        foreach ($user in $allUsers) {
            # Проверяем существование профиля
            $userProfilePath = "C:\Users\$($user.Name)"
            if (Test-Path $userProfilePath) {
                $usersToMove += $user.Name
            }
        }
        
        Write-Host ""
        Write-LogAndConsole "*** Информация о переносе профиля ***"
        Write-LogAndConsole "Найдены следующие профили пользователей:"
        
        for ($i = 0; $i -lt $usersToMove.Count; $i++) {
            $userProPath = "C:\Users\$($usersToMove[$i])"
            $userProSize = "{0:N2} МБ" -f ((Get-ChildItem -Path $userProPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB)
            Write-LogAndConsole "  $($i+1). $($usersToMove[$i]) - размер: $userProSize"
        }
        
        Write-Host ""
        
        # Выбор учетной записи для переноса
        $selectedUserIndex = 0
        
        if ($usersToMove.Count -eq 0) {
            Write-LogAndConsole "ОШИБКА: Не найдено доступных профилей пользователей для переноса!"
            Read-Host "Нажмите Enter для выхода"
            exit 1
        } elseif ($usersToMove.Count -eq 1) {
            Write-LogAndConsole "Найден только один профиль пользователя. Будет перенесен профиль пользователя: $($usersToMove[0])"
            $selectedUserName = $usersToMove[0]
        } else {
            do {
                try {
                    $selectedUserIndex = [int](Read-Host "Выберите номер профиля для переноса (1-$($usersToMove.Count))")
                } catch {
                    $selectedUserIndex = 0
                }
            } while ($selectedUserIndex -lt 1 -or $selectedUserIndex -gt $usersToMove.Count)
            
            $selectedUserName = $usersToMove[$selectedUserIndex - 1]
            Write-LogAndConsole "Выбран профиль пользователя: $selectedUserName"
        }
        
        # Запрос на начало переноса
        $startMove = Read-Host "Начать перенос профиля пользователя $selectedUserName? (y/n)"
        if ($startMove -ne "y") {
            Write-LogAndConsole "Операция отменена пользователем"
            exit 0
        }
        
        Write-LogAndConsole "Начинаем процесс переноса профиля..."
        
        # Сохраняем выбранного пользователя для дальнейшего использования
        $Global:SelectedUserName = $selectedUserName
    } else {
        # Скрипт запущен под обычной учетной записью пользователя
        if ($isAdminEnabled) {
            Write-LogAndConsole "Учетная запись $adminName активирована"
            
            Write-Host ""
            Write-Host "Выберите действие:"
            Write-Host "1. Деактивировать учетную запись $adminName"
            Write-Host "2. Выйти из системы и войти под учетной записью $adminName"
            Write-Host "3. Продолжить работу с текущей учетной записью"
            
            $actionChoice = Read-Host "Выберите действие (1-3)"
            
            if ($actionChoice -eq "1") {
                Write-LogAndConsole "Деактивация учетной записи $adminName..."
                ToggleUserAccount -Username $adminName -Action "Disable"
            } elseif ($actionChoice -eq "2") {
                Write-LogAndConsole "Выход из системы для входа под учетной записью $adminName..."
                $logoutConfirm = Read-Host "Нажмите Enter для выхода из системы или 'n' для отмены"
                if ($logoutConfirm -ne "n") {
                    # Используем функцию для надежного выхода из системы
                    ForceLogout -Timeout 5
                } else {
                    Write-LogAndConsole "Выход отменен пользователем"
                }
            } else {
                Write-LogAndConsole "Продолжение работы с текущей учетной записью"
            }
        } else {
            Write-LogAndConsole "Учетная запись $adminName существует, но НЕ активирована"
            $activateAdmin = Read-Host "Активировать встроенную учетную запись $adminName? (y/n)"
            
            if ($activateAdmin -eq "y") {
                Write-LogAndConsole "Активация учетной записи $adminName..."
                $result = ToggleUserAccount -Username $adminName -Action "Enable"
                
                if ($result) {
                    $disableCurrentUser = Read-Host "Отключить текущую учетную запись и выйти из системы? (y/n)"
                    if ($disableCurrentUser -eq "y") {
                        $currentUser = $env:USERNAME
                        Write-LogAndConsole "Отключение текущей учетной записи $currentUser..."
                        
                        ToggleUserAccount -Username $currentUser -Action "Disable"
                        
                        # Выход из системы
                        Write-LogAndConsole "Выполняется выход из системы через 5 секунд..."
                        $logoutConfirm = Read-Host "Нажмите Enter для выхода из системы или 'n' для отмены"
                        if ($logoutConfirm -ne "n") {
                            # Используем функцию для надежного выхода из системы
                            ForceLogout -Timeout 5
                        } else {
                            Write-LogAndConsole "Выход отменен пользователем"
                        }
                    } else {
                        # Опция выхода из скрипта или продолжения
                        $continueOrExit = Read-Host "Выйти из скрипта для перезапуска под учетной записью $adminName? (y/n)"
                        if ($continueOrExit -eq "y") {
                            Write-LogAndConsole "Выход из скрипта по запросу пользователя."
                            Write-LogAndConsole "Для переноса профиля запустите скрипт снова, войдя в систему под учетной записью $adminName."
                            Read-Host "Нажмите Enter для выхода"
                            exit 0
                        } else {
                            Write-LogAndConsole "Продолжение выполнения скрипта..."
                        }
                    }
                } else {
                    Write-Host ""
                    Write-Host "Выберите действие:"
                    Write-Host "1. Продолжить без активации учетной записи $adminName"
                    Write-Host "2. Попробовать еще раз с повышенными правами"
                    Write-Host "3. Отменить выполнение скрипта"
                    
                    $adminAction = Read-Host "Выберите действие (1-3)"
                    Write-LogAndConsole "Пользователь выбрал: $adminAction"
                    
                    if ($adminAction -eq "1") {
                        Write-LogAndConsole "Продолжение работы без активации $adminName..."
                    } elseif ($adminAction -eq "2") {
                        Write-LogAndConsole "Попытка выполнить команду с явным указанием прав..."
                        $result = ToggleUserAccount -Username $adminName -Action "Enable"
                        if (-not $result) {
                            Write-LogAndConsole "Продолжение работы..."
                        }
                    } else {
                        Write-LogAndConsole "Выполнение скрипта отменено пользователем"
                        Read-Host "Нажмите Enter для выхода"
                        exit 1
                    }
                }
            } else {
                Write-LogAndConsole "Продолжение без активации учетной записи $adminName"
            }
        }
    }
}

Write-Host "================================================"
Write-Host "    Перенос профиля пользователя"
Write-Host "================================================"
Write-Host ""
Write-Host "Скрипт переместит выбранный профиль пользователя с диска C: на другой диск."
Write-Host "В исходном месте будет создана символическая ссылка."
Write-Host ""

# Проверка, запущен ли скрипт под учетной записью Администратор
$isBuiltInAdminAccount = IsBuiltInAdmin
if (-not $isBuiltInAdminAccount) {
    Write-LogAndConsole "ОШИБКА: Перенос профиля доступен только при запуске от имени встроенной учетной записи Администратор."
    Write-LogAndConsole "Текущая учетная запись: $env:USERNAME"
    Write-LogAndConsole "Пожалуйста, войдите в систему под учетной записью Администратор и повторите попытку."
    Read-Host "Нажмите Enter для выхода"
    exit 1
}

# Текущий пользователь - запрашиваем из системы, когда нужно
$CurrentUser = $env:USERNAME
Write-LogAndConsole "Текущий пользователь: $CurrentUser"

# Функция для выбора целевого диска
function SelectTargetDrive {
    Write-Host ""
    Write-LogAndConsole "*** Этап 1: Выбор целевого диска ***"
    Write-Host ""
    
    # Получение списка доступных дисков
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -ne "C" -and $_.Free -gt 0 }
    
    if ($drives.Count -eq 0) {
        Write-LogAndConsole "ОШИБКА: Не найдено доступных дисков, кроме системного!"
        Read-Host "Нажмите Enter для выхода"
        exit 1
    }
    
    # Вывод списка доступных дисков
    Write-LogAndConsole "Доступные диски:"
    $index = 1
    foreach ($drive in $drives) {
        $freeGB = [math]::Round($drive.Free / 1GB, 2)
        $usedGB = [math]::Round(($drive.Used / 1GB), 2)
        $totalGB = [math]::Round(($drive.Free + $drive.Used) / 1GB, 2)
        
        Write-LogAndConsole "$index. $($drive.Name): - $freeGB ГБ свободно из $totalGB ГБ"
        $index++
    }
    
    # Выбор диска
    $selection = 0
    do {
        try {
            $selection = [int](Read-Host "Выберите диск для переноса профиля (1-$($drives.Count))")
        } catch {
            $selection = 0
        }
    } while ($selection -lt 1 -or $selection -gt $drives.Count)
    
    $selectedDrive = $drives[$selection - 1]
    $targetPath = "$($selectedDrive.Name):\Users"
    
    Write-LogAndConsole "Выбран диск: $($selectedDrive.Name): - Целевая папка: $targetPath"
    
    return $targetPath
}

# Функция для копирования профиля текущего пользователя
function CopyProfilesAndCreateSymlink {
    param (
        [string]$TargetPath
    )
    
    Write-Host ""
    Write-LogAndConsole "*** Этап 2: Копирование профиля пользователя ***"
    Write-Host ""
    
    # Используем выбранного пользователя вместо текущего
    $userToMove = $Global:SelectedUserName
    $sourceUserProfile = "C:\Users\$userToMove"
    $targetUserProfile = "$TargetPath\$userToMove"
    
    Write-LogAndConsole "Копирование профиля пользователя $userToMove"
    
    # Создаем папку назначения, если её нет
    if (-not (Test-Path $TargetPath)) {
        Write-LogAndConsole "Создание папки $TargetPath"
        try {
            New-Item -Path $TargetPath -ItemType Directory -Force | Out-Null
        } catch {
            Write-LogAndConsole ("ОШИБКА: Не удалось создать папку {0}: {1}" -f ${TargetPath}, $_.Exception.Message)
            Read-Host "Нажмите Enter для выхода"
            exit 1
        }
    } else {
        Write-LogAndConsole "Папка $TargetPath уже существует"
    }
    
    # Проверяем, существует ли уже профиль пользователя в целевой папке
    if (Test-Path $targetUserProfile) {
        Write-LogAndConsole "ВНИМАНИЕ: Профиль пользователя $userToMove уже существует в $TargetPath"
        $action = Read-Host "Профиль уже существует. Выберите действие: (r)eplace - заменить, (s)kip - пропустить копирование, (a)bort - отменить"
        
        if ($action -eq "a") {
            Write-LogAndConsole "Операция отменена пользователем"
            Read-Host "Нажмите Enter для выхода"
            exit
        } elseif ($action -eq "s") {
            Write-LogAndConsole "Пропуск копирования профиля"
            return "skip"
        } elseif ($action -eq "r") {
            Write-LogAndConsole "Продолжение с заменой существующего профиля"
            try {
                Remove-Item -Path $targetUserProfile -Force -Recurse
                Write-LogAndConsole "Существующий профиль удален"
            } catch {
                Write-LogAndConsole ("ОШИБКА при удалении существующего профиля: {0}" -f $_.Exception.Message)
                $continueWithErrors = Read-Host "Продолжить несмотря на ошибки? (y/n)"
                if ($continueWithErrors -ne "y") {
                    Write-LogAndConsole "Операция отменена пользователем"
                    Read-Host "Нажмите Enter для выхода"
                    exit
                }
            }
        } else {
            Write-LogAndConsole "Неверный ввод. Операция отменена"
            Read-Host "Нажмите Enter для выхода"
            exit
        }
    }
    
    # Копирование профиля пользователя
    Write-LogAndConsole "Копирование профиля пользователя $userToMove из $sourceUserProfile в $targetUserProfile"
    
    # Создаем целевую папку пользователя
    if (-not (Test-Path $targetUserProfile)) {
        try {
            New-Item -Path $targetUserProfile -ItemType Directory -Force | Out-Null
        } catch {
            Write-LogAndConsole ("ОШИБКА: Не удалось создать папку {0}: {1}" -f ${targetUserProfile}, $_.Exception.Message)
            Read-Host "Нажмите Enter для выхода"
            exit 1
        }
    }
    
    # Копирование с robocopy для сохранения прав доступа и атрибутов
    try {
        $robocopyArgs = "`"$sourceUserProfile`" `"$targetUserProfile`" /E /COPYALL /DCOPY:T /R:1 /W:1 /XJ"
        Write-LogAndConsole "Запуск команды: robocopy $robocopyArgs"
        
        $robocopyProcess = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
        
        # Проверка кода возврата robocopy
        # Коды от 0 до 7 считаются успешными для robocopy
        if ($robocopyProcess.ExitCode -lt 8) {
            Write-LogAndConsole "Копирование профиля завершено успешно"
            return "success"
        } else {
            Write-LogAndConsole "ВНИМАНИЕ: Процесс копирования завершен с ошибками (код $($robocopyProcess.ExitCode))"
            $continueWithErrors = Read-Host "Продолжить несмотря на ошибки? (y/n)"
            
            if ($continueWithErrors -ne "y") {
                Write-LogAndConsole "Операция отменена пользователем"
                Read-Host "Нажмите Enter для выхода"
                exit
            }
            return "errors"
        }
    } catch {
        Write-LogAndConsole ("ОШИБКА при копировании профиля: {0}" -f $_.Exception.Message)
        $continueWithErrors = Read-Host "Продолжить несмотря на ошибки? (y/n)"
        
        if ($continueWithErrors -ne "y") {
            Write-LogAndConsole "Операция отменена пользователем"
            Read-Host "Нажмите Enter для выхода"
            exit
        }
        return "errors"
    }
}

# Функция для создания символической ссылки для профиля пользователя
function CreateSymbolicLink {
    param (
        [string]$TargetPath,
        [string]$CopyStatus
    )
    
    if ($CopyStatus -eq "skip") {
        Write-LogAndConsole "Пропуск создания символической ссылки (копирование было пропущено)"
        return
    }
    
    Write-Host ""
    Write-LogAndConsole "*** Этап 3: Создание символической ссылки для профиля пользователя ***"
    Write-Host ""
    
    # Используем выбранного пользователя вместо текущего
    $userToMove = $Global:SelectedUserName
    $sourceUserProfile = "C:\Users\$userToMove"
    $targetUserProfile = "$TargetPath\$userToMove"
    
    # Создание символической ссылки
    Write-Host "Создание символической ссылки..."
    
    try {
        # Проверяем, существует ли исходный профиль пользователя
        if (Test-Path $sourceUserProfile) {
            # Удаление исходного профиля пользователя
            Write-LogAndConsole "Удаление исходного профиля пользователя $sourceUserProfile"
            
            # Сначала попробуем переименовать папку для безопасности
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $backupDir = "C:\Users\${userToMove}_backup_$timestamp"
            
            try {
                Rename-Item -Path $sourceUserProfile -NewName $backupDir -Force
                Write-LogAndConsole "Исходный профиль пользователя $sourceUserProfile переименован в $backupDir"
            } catch {
                Write-LogAndConsole ("ОШИБКА при переименовании ${sourceUserProfile}: {0}" -f $_.Exception.Message)
                Write-LogAndConsole "Попытка прямого удаления папки..."
                
                # Если переименование не удалось, пытаемся удалить
                try {
                    Remove-Item -Path $sourceUserProfile -Force -Recurse
                } catch {
                    Write-LogAndConsole ("ОШИБКА при удалении ${sourceUserProfile}: {0}" -f $_.Exception.Message)
                    
                    # Проверяем, существует ли папка профиля (может быть уже символической ссылкой)
                    if (Test-Path $sourceUserProfile) {
                        $linkInfo = Get-Item $sourceUserProfile -Force
                        
                        if ($linkInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                            Write-LogAndConsole "$sourceUserProfile уже является символической ссылкой"
                            
                            # Проверяем, указывает ли она на нужный нам путь
                            try {
                                $linkTarget = (Get-Item $sourceUserProfile).Target
                                
                                if ($linkTarget -eq $targetUserProfile) {
                                    Write-LogAndConsole "Существующая символическая ссылка уже указывает на $targetUserProfile"
                                    return
                                } else {
                                    Write-LogAndConsole "Текущая ссылка указывает на $linkTarget. Попытка переназначения..."
                                    
                                    try {
                                        Remove-Item -Path $sourceUserProfile -Force
                                    } catch {
                                        Write-LogAndConsole ("ОШИБКА при удалении существующей символической ссылки: {0}" -f $_.Exception.Message)
                                        Write-LogAndConsole "Не удалось создать ссылку на $sourceUserProfile"
                                        Read-Host "Нажмите Enter для выхода"
                                        exit 1
                                    }
                                }
                            } catch {
                                Write-LogAndConsole ("ОШИБКА при проверке цели символической ссылки: {0}" -f $_.Exception.Message)
                            }
                        } else {
                            Write-LogAndConsole "$sourceUserProfile существует и не является символической ссылкой"
                            Write-LogAndConsole "Не удалось удалить или переместить исходную папку профиля"
                            Read-Host "Нажмите Enter для выхода"
                            exit 1
                        }
                    }
                }
            }
        }
        
        # Создание символической ссылки
        Write-Host "Создание символической ссылки $sourceUserProfile -> $targetUserProfile"
        cmd /c mklink /d "$sourceUserProfile" "$targetUserProfile"
        
        # Проверка создания символической ссылки
        if (Test-Path $sourceUserProfile) {
            Write-LogAndConsole "Символическая ссылка $sourceUserProfile успешно создана"
            
            # Проверим, создана ли директория в правильное место
            try {
                $linkItem = Get-Item $sourceUserProfile -Force
                if ($linkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    Write-LogAndConsole "Проверка подтверждает, что $sourceUserProfile является символической ссылкой"
                } else {
                    Write-LogAndConsole "ПРЕДУПРЕЖДЕНИЕ: $sourceUserProfile снова стала обычной папкой"
                }
            } catch {
                Write-LogAndConsole ("ОШИБКА при проверке символической ссылки: {0}" -f $_.Exception.Message)
            }
        } else {
            Write-LogAndConsole "ОШИБКА: Не удалось создать символическую ссылку ${sourceUserProfile}"
            
            # Восстановление из резервной копии
            if (Test-Path $backupDir) {
                Write-LogAndConsole "Восстановление из резервной копии $backupDir"
                try {
                    Rename-Item -Path $backupDir -NewName $sourceUserProfile -Force
                    Write-LogAndConsole "Исходная папка профиля $sourceUserProfile восстановлена из резервной копии"
                } catch {
                    Write-LogAndConsole ("ОШИБКА при восстановлении из резервной копии: {0}" -f $_.Exception.Message)
                    Write-LogAndConsole "КРИТИЧЕСКАЯ ОШИБКА: Папка профиля ${sourceUserProfile} отсутствует и не может быть восстановлена!"
                    Read-Host "Нажмите Enter для выхода"
                    exit 1
                }
            } else {
                Write-LogAndConsole "КРИТИЧЕСКАЯ ОШИБКА: Папка профиля ${sourceUserProfile} была удалена, но символическая ссылка не создана!"
                Read-Host "Нажмите Enter для выхода"
                exit 1
            }
        }
    } catch {
        Write-LogAndConsole ("ОШИБКА при создании символической ссылки: {0}" -f $_.Exception.Message)
        Read-Host "Нажмите Enter для выхода"
        exit 1
    }
}

# Выполнение основных функций
$TargetPath = SelectTargetDrive
$CopyStatus = CopyProfilesAndCreateSymlink -TargetPath $TargetPath
CreateSymbolicLink -TargetPath $TargetPath -CopyStatus $CopyStatus

# Предлагаем перезагрузку
OfferRestart -TargetPath $TargetPath 
