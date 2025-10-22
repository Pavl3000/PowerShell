CLS


# Получаем все включенные серверы Windows из AD
$servers = Get-ADComputer -Filter {
    OperatingSystem -like "Windows Server*" -and 
    Enabled -eq $true
} | Select-Object -ExpandProperty Name

# Инициализируем списки
$onlineServers = @()
$offlineServers = @()

# Проверяем каждый сервер
foreach ($server in $servers) {
    # Используем -Timeout 1000 (1000 миллисекунд = 1 секунда)
    if (Test-Connection -ComputerName $server -Count 1 -Quiet) {
        $onlineServers += $server
    } else {
        $offlineServers += $server
    }
}

# Выводим результаты
Write-Host "Включенные серверы ($($onlineServers.Count)):" -ForegroundColor Green
$onlineServers | Sort-Object | ForEach-Object { Write-Host "- $_" }

Write-Host "`nВыключенные серверы ($($offlineServers.Count)):" -ForegroundColor Red
$offlineServers | Sort-Object | ForEach-Object { Write-Host "- $_" }