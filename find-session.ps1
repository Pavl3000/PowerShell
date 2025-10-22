cls

# Получаем дату 20 дней назад
$CutoffDate = (Get-Date).AddDays(-20)

# Список для хранения результатов
$LogonEvents = @()

# --- 1. События входа (Security Log: Event ID 4624) ---
Write-Host "Поиск событий входа (Event ID 4624)..." -ForegroundColor Cyan
try {
    $LogonEvents4624 = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        Id = 4624
        StartTime = $CutoffDate
    } -ErrorAction Stop

    foreach ($event in $LogonEvents4624) {
        $eventXml = [xml]$event.ToXml()
        $properties = $eventXml.Event.EventData.Data

        $logonType = ($properties | Where-Object { $_.Name -eq 'LogonType' }).'#text'
        $userName = ($properties | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
        $domain = ($properties | Where-Object { $_.Name -eq 'TargetDomainName' }).'#text'
        $logonTime = $event.TimeCreated

        # Определяем тип сессии
        $sessionType = switch ($logonType) {
            '2'  { 'Interactive (локальный вход)' }
            '3'  { 'Сетевой вход (например, файловый доступ)' }
            '7'  { 'Разблокировка рабочей станции' }
            '10' { 'Удалённый рабочий стол (RDP)' }
            '11' { 'Кэшированный интерактивный вход' }
            default { "Другой (код: $logonType)" }
        }

        $LogonEvents += [PSCustomObject]@{
            Time        = $logonTime
            EventType   = 'Вход'
            User        = "$domain\$userName"
            SessionType = $sessionType
            LogonType   = $logonType
            EventId     = 4624
        }
    }
} catch {
    if ($_.Exception.Message -like "*No events were found*") {
        Write-Host "События входа за последние 20 дней не найдены." -ForegroundColor Yellow
    } else {
        Write-Warning "Не удалось прочитать журнал безопасности: $($_.Exception.Message)"
        Write-Host "Убедитесь, что запущено от администратора и включён аудит входа." -ForegroundColor Red
    }
}

# --- 2. События выхода (Security Log: Event ID 4634 и 4647) ---
Write-Host "Поиск событий выхода (Event ID 4634, 4647)..." -ForegroundColor Cyan
try {
    $LogoffEvents = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        Id = 4634, 4647
        StartTime = $CutoffDate
    } -ErrorAction Stop

    foreach ($event in $LogoffEvents) {
        $eventXml = [xml]$event.ToXml()
        $properties = $eventXml.Event.EventData.Data

        $userName = ($properties | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
        $domain = ($properties | Where-Object { $_.Name -eq 'TargetDomainName' }).'#text'
        $logonType = ($properties | Where-Object { $_.Name -eq 'LogonType' }).'#text'
        $logoffTime = $event.TimeCreated

        $sessionType = switch ($logonType) {
            '2'  { 'Interactive (локальный вход)' }
            '3'  { 'Сетевой вход' }
            '7'  { 'Разблокировка' }
            '10' { 'Удалённый рабочий стол (RDP)' }
            '11' { 'Кэшированный вход' }
            default { "Другой (код: $logonType)" }
        }

        $LogonEvents += [PSCustomObject]@{
            Time        = $logoffTime
            EventType   = if ($event.Id -eq 4634) { 'Выход' } else { 'Выход (принудительный/локальный)' }
            User        = "$domain\$userName"
            SessionType = $sessionType
            LogonType   = $logonType
            EventId     = $event.Id
        }
    }
} catch {
    if ($_.Exception.Message -like "*No events were found*") {
        Write-Host "События выхода за последние 20 дней не найдены." -ForegroundColor Yellow
    } else {
        Write-Warning "Ошибка при чтении событий выхода: $($_.Exception.Message)"
    }
}



# --- Вывод результата ---
if ($LogonEvents.Count -gt 0) {
    $LogonEvents | Sort-Object Time |
    Format-Table -AutoSize -Property Time, EventType, User, SessionType, EventId
} else {
    Write-Host "За последние 20 дней не найдено ни одного события входа/выхода." -ForegroundColor Red
}