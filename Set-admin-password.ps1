# Требуются права администратора домена и модуль ActiveDirectory

# Импортируем модуль ActiveDirectory
Import-Module ActiveDirectory -ErrorAction Stop

# Функция генерации сложного пароля
function Generate-Password {
    $length = 20
    $charSets = @(
        "abcdefghijklmnopqrstuvwxyz",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "0123456789",
        "!@#$%^&*()_+-=[]{};:,./<>?"
    )
    
    $password = [System.Text.StringBuilder]::new()
    
    # Добавляем минимум по одному символу из каждого набора
    foreach ($charSet in $charSets) {
        $randomIndex = Get-Random -Maximum $charSet.Length
        $null = $password.Append($charSet[$randomIndex])
    }
    
    # Добавляем оставшиеся символы
    $allChars = $charSets -join ''
    for ($i = $password.Length; $i -lt $length; $i++) {
        $randomIndex = Get-Random -Maximum $allChars.Length
        $null = $password.Append($allChars[$randomIndex])
    }
    
    # Перемешиваем символы
    return -join ($password.ToString().ToCharArray() | Sort-Object {Get-Random})
}

# Функция для получения локальных администраторов (универсальная для всех языков)
function Get-LocalAdministrators {
    param($ComputerName)
    
    $admins = @()
    
    # Способ 1: Используем SID группы администраторов (универсальный способ)
    try {
        $admins = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            # SID встроенной группы администраторов: S-1-5-32-544
            $adminGroup = Get-LocalGroup -SID "S-1-5-32-544" -ErrorAction SilentlyContinue
            if ($adminGroup) {
                Get-LocalGroupMember -Group $adminGroup | 
                Where-Object { 
                    # Фильтруем локальных пользователей (не группы и не доменные учетки)
                    ($_.ObjectClass -eq "User" -or $_.ObjectClass -eq "Пользователь") -and 
                    $_.PrincipalSource -eq "Local"
                } |
                Select-Object -ExpandProperty Name
            }
        } -ErrorAction Stop
    }
    catch {
        Write-Warning "Не удалось получить администраторов через SID на $ComputerName : $_"
    }
    
    # Если через SID не сработало, пробуем оба варианта названий групп
    if (-not $admins) {
        # Список возможных названий группы администраторов на разных языках
        $groupNames = @("Administrators", "Администраторы")
        
        foreach ($groupName in $groupNames) {
            try {
                $currentAdmins = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
                    param($gName)
                    Get-LocalGroupMember -Group $gName -ErrorAction SilentlyContinue | 
                    Where-Object { 
                        # Универсальная фильтрация по типу объекта
                        ($_.ObjectClass -eq "User" -or $_.ObjectClass -eq "Пользователь") -and 
                        $_.PrincipalSource -eq "Local"
                    } |
                    Select-Object -ExpandProperty Name
                } -ArgumentList $groupName -ErrorAction Stop
                
                if ($currentAdmins) {
                    $admins = $currentAdmins
                    break
                }
            }
            catch {
                # Продолжаем пробовать другие названия групп
                continue
            }
        }
    }
    
    return $admins
}

# Получаем все включенные серверы Windows
#$servers = Get-ADComputer -Filter {
#    OperatingSystem -like "Windows Server*" -and 
#    Enabled -eq $true
#} | Select-Object -ExpandProperty Name


$servers = @(
    'SCCM2016',
    'TECHEXP'
)




$results = @()

foreach ($server in $servers) {
    try {
        # Проверяем доступность сервера
        if (-not (Test-Connection -ComputerName $server -Count 1 -Quiet)) {
            Write-Warning "Сервер $server недоступен"
            continue
        }

        # Получаем локальных администраторов (универсальным методом)
        $admins = Get-LocalAdministrators -ComputerName $server

        if (-not $admins) {
            Write-Warning "На сервере $server не найдены локальные администраторы"
            continue
        }

        # Генерируем новый пароль
        $newPassword = Generate-Password
        $securePassword = ConvertTo-SecureString -String $newPassword -AsPlainText -Force

        # Меняем пароль для каждого локального администратора
        foreach ($admin in $admins) {
            $username = $admin -replace '.*\\', ''
            
            try {
                Invoke-Command -ComputerName $server -ScriptBlock {
                    param($uname, $pass)
                    Set-LocalUser -Name $uname -Password $pass -ErrorAction Stop
                } -ArgumentList $username, $securePassword -ErrorAction Stop
                
                Write-Host "Пароль обновлен для пользователя $username на сервере $server" -ForegroundColor Green
            }
            catch {
                Write-Warning "Не удалось обновить пароль для $username на $server : $_"
            }
        }

        # Сохраняем результат
        $result = [PSCustomObject]@{
            Server = $server
            Administrators = $admins -join ', '
            Password = $newPassword
            Timestamp = Get-Date
            Status = "Success"
        }
        $results += $result
    }
    catch {
        Write-Error "Ошибка при обработке сервера $server : $_"
        
        $result = [PSCustomObject]@{
            Server = $server
            Administrators = "Error"
            Password = "Error"
            Timestamp = Get-Date
            Status = "Failed: $_"
        }
        $results += $result
    }
}

# Сохраняем результаты в файл
$outputPath = "ServerPasswords_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$results | Format-Table -AutoSize | Out-String -Width 4096 | Out-File $outputPath

# Дополнительно сохраняем в CSV для удобства
$csvPath = "ServerPasswords_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "Результаты сохранены в файлы:`n$outputPath`n$csvPath" -ForegroundColor Cyan

# Выводим статистику
$successCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
$failedCount = ($results | Where-Object { $_.Status -like "Failed*" }).Count

Write-Host "`nСтатистика выполнения:" -ForegroundColor Yellow
Write-Host "Успешно обработано: $successCount серверов" -ForegroundColor Green
Write-Host "Не удалось обработать: $failedCount серверов" -ForegroundColor Red