# Проверка наличия и содержимого переменной
if (-not (Get-Variable -Name UnlinkedGPOs -ErrorAction SilentlyContinue) -or
    ($null -eq $UnlinkedGPOs) -or
    ($UnlinkedGPOs.Count -eq 0)) {
    Write-Host "Переменная \$UnlinkedGPOs не определена или пуста." -ForegroundColor Red
    return
}

# Проверка, что у объектов есть нужные свойства
if (-not ($UnlinkedGPOs[0].PSObject.Properties.Name -contains "DisplayName") -or
    -not ($UnlinkedGPOs[0].PSObject.Properties.Name -contains "Id")) {
    Write-Host "Переменная \$UnlinkedGPOs не содержит ожидаемых свойств 'DisplayName' и 'Id'." -ForegroundColor Red
    return
}

# Загрузка модуля GroupPolicy
Import-Module GroupPolicy -ErrorAction Stop

# Определение текущего домена (если у вас один лес/домен — этого достаточно)
$CurrentDomain = (Get-WmiObject Win32_ComputerSystem).Domain
if (-not $CurrentDomain) {
    $CurrentDomain = (Get-ADDomain).DNSRoot
}

# Экспорт на случай отката
$BackupPath = "C:\TEMP\UnlinkedGPOs_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$UnlinkedGPOs | Select-Object DisplayName, Id |
    Export-Csv -Path $BackupPath -NoTypeInformation -Encoding UTF8

Write-Host "Резервная копия сохранена: $BackupPath" -ForegroundColor Yellow

# Подтверждение
$confirmation = Read-Host "Вы уверены, что хотите удалить $($UnlinkedGPOs.Count) несвязанных GPO? Введите 'YES' для подтверждения"
if ($confirmation -ne 'YES') {
    Write-Host "Удаление отменено." -ForegroundColor Yellow
    return
}

# Удаление по GUID
foreach ($gpo in $UnlinkedGPOs) {
    $displayName = $gpo.DisplayName
    $guid = $gpo.Id

    try {
        Write-Host "Удаляю GPO: '$displayName' (GUID: $guid)" -ForegroundColor Cyan
        Remove-GPO -Guid $guid -Domain $CurrentDomain -Confirm:$false
        Write-Host "Успешно удалено." -ForegroundColor Green
    }
    catch {
        Write-Host "Ошибка при удалении GPO '$displayName': $($_.Exception.Message)" -ForegroundColor Red
    }
}