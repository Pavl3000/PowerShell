cls




<#


.SYNOPSIS
    Скрипт для автоматизации настройки прав доступа к папкам через группы Active Directory

.DESCRIPTION


    ПРИНЦИП РАБОТЫ:
    - Создание иерархии групп безопасности в Active Directory
    - Настройка NTFS-прав на файловые ресурсы
    - Автоматическое наследование прав через групповые членства


    ОПИСАНИЕ ГРУПП:
    - Группа с суффиксом "-T" (Traverse) - права на проход по папке
    - Группа с суффиксом "-R" (Read) - права на чтение
    - Группа с суффиксом "-W" (Write) - права на запись/модификацию




     === ! ГРУППОВАЯ ИЕРАРХИЯ ! ===
    
    Корневые группы (существующие):
    │   - Корневая-T (Traverse права на верхний уровень)
    │   - Корневая-R (Read права на верхний уровень) 
    │   - Корневая-W (Write права на верхний уровень)
    │
    └── Дочерние группы (создаваемые для новой папки):
        │   - НоваяПапка-T (Она сама включена в Корневая-T)
        │   - НоваяПапка-R (В нее включена Корневая-R для сохранения доступности у членов корневой) + (Она сама включена в Корневая-T)
        │   - НоваяПапка-W (В нее включена Корневая-W для сохранения доступности у членов корневой) + (Она сама включена в Корневая-T)



    ТРЕБОВАНИЯ:
    - Установленные средства RSAT (модуль ActiveDirectory)
    - Права на создание групп в Active Directory
    - Права на изменение ACL файловых ресурсов


.AUTHOR

        __________                    .__   
        \______   \_____ ___  __ ____ |  |  
         |     ___/\__  \\  \/ // __ \|  |  
         |    |     / __ \\   /\  ___/|  |__
         |____|    (____  /\_/  \___  >____/
                        \/          \/      
#>








# Требуем модуль ActiveDirectory
if (!(Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "Модуль ActiveDirectory не установлен. Установите RSAT-AD-PowerShell." -ForegroundColor Red
    exit 1
}
Import-Module ActiveDirectory -ErrorAction Stop

Add-Type -AssemblyName System.Windows.Forms

# Настройка OU (измените при необходимости)
$OUPath = "OU=DFS Groups,OU=Groups,OU=LEGENDA,DC=storm,DC=local"

# === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ===

function Get-ADGroupsByPattern {
    param([string]$Pattern)
    try {
        $searcher = New-Object System.DirectoryServices.DirectorySearcher
        $searcher.Filter = "(&(objectCategory=group)(name=$Pattern))"
        $searcher.PropertiesToLoad.AddRange(@("name", "description"))
        $searcher.PageSize = 1000
        return $searcher.FindAll() | ForEach-Object {
            [PSCustomObject]@{
                Name        = $_.Properties["name"][0]
                Description = $_.Properties["description"][0]
            }
        }
    } catch {
        Write-Host "Ошибка поиска групп AD: $_" -ForegroundColor Red
        return @()
    }
}

function Get-ExistingGroup {
    param([string]$GroupName)
    Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue
}

function Ensure-ADGroup {
    param([string]$Name, [string]$Description)
    if (Get-ExistingGroup $Name) {
        Write-Host "Группа '$Name' уже существует."
        return
    }
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Создать группу:`n`nИмя: $Name`nОписание: $Description",
        "Подтверждение",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        New-ADGroup -Name $Name -GroupScope Universal -Path $OUPath -Description $Description -ErrorAction Stop
        Write-Host "Создана группа: $Name"
    } else {
        Write-Host "Создание группы '$Name' отменено."
    }
}

function Add-ToGroup {
    param([string]$ParentGroup, [string]$ChildGroup)
    try {
        $members = Get-ADGroupMember -Identity $ParentGroup -ErrorAction SilentlyContinue |
                   Where-Object { $_.SamAccountName -eq $ChildGroup }
        if (-not $members) {
            Add-ADGroupMember -Identity $ParentGroup -Members $ChildGroup -ErrorAction Stop
            Write-Host "Добавлено: $ChildGroup → $ParentGroup"
        }
    } catch {
        Write-Host "Ошибка при добавлении $ChildGroup в ${ParentGroup}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Set-FolderPermissions {
    param(
        [string]$FolderPath,
        [hashtable]$GroupPermissions,
        [string]$RootGroup
    )

    if (!(Test-Path $FolderPath)) {
        New-Item -ItemType Directory -Path $FolderPath -Force | Out-Null
        Write-Host "Создана папка: $FolderPath"
    }

    $Acl = Get-Acl $FolderPath
    $Acl.SetAccessRuleProtection($true, $true)

    # Удаляем старые правила от корневой группы
    $GroupsToRemove = @($RootGroup, "$RootGroup -T", "$RootGroup -R", "$RootGroup -W")
    foreach ($Group in $GroupsToRemove) {
        $Acl.Access | Where-Object { $_.IdentityReference.Value -eq $Group } | ForEach-Object {
            $Acl.RemoveAccessRule($_) | Out-Null
            Write-Host "Удалены права для $Group"
        }
    }

    # Функция определения прав (исправлена ошибка op_BitwiseOr)
    function Get-Rights {
        param([string]$Permission)
        switch ($Permission) {
            "Traverse" {
                return [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
            }
            "Read" {
                return [System.Security.AccessControl.FileSystemRights]::Read -bor
                       [System.Security.AccessControl.FileSystemRights]::ListDirectory -bor
                       [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
            }
            "Modify" {
                return [System.Security.AccessControl.FileSystemRights]::Modify
            }
            default {
                Write-Host "Неизвестный тип прав: $Permission" -ForegroundColor Yellow
                return $null
            }
        }
    }

    foreach ($GroupName in $GroupPermissions.Keys) {
        $Permission = $GroupPermissions[$GroupName]
        $Rights = Get-Rights -Permission $Permission
        if ($null -eq $Rights) { continue }

        $InheritanceFlags = if ($Permission -eq "Traverse") {
            [System.Security.AccessControl.InheritanceFlags]::None
        } else {
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
            [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        }

        $PropagationFlags = [System.Security.AccessControl.PropagationFlags]::None

        # Проверка существующего правила
        $ExistingRule = $Acl.Access | Where-Object {
            $_.IdentityReference.Value -eq $GroupName -and
            $_.FileSystemRights -eq $Rights -and
            $_.InheritanceFlags -eq $InheritanceFlags
        }

        if (-not $ExistingRule) {
            try {
                $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $GroupName,
                    $Rights,
                    $InheritanceFlags,
                    $PropagationFlags,
                    "Allow"
                )
                $Acl.AddAccessRule($AccessRule)
                Write-Host "Назначены права $Permission для $GroupName на $FolderPath"
            } catch {
                Write-Host "Ошибка ACL для ${GroupName}: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "Права $Permission уже назначены для $GroupName"
        }
    }

    Set-Acl -Path $FolderPath -AclObject $Acl
}

# === ГРАФИЧЕСКИЙ ИНТЕРФЕЙС ===

$form = New-Object System.Windows.Forms.Form
$form.Text = "Настройка прав доступа к папке"
$form.Size = New-Object System.Drawing.Size(720, 440)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# UNC-путь
$labelPath = New-Object System.Windows.Forms.Label
$labelPath.Location = New-Object System.Drawing.Point(20, 20)
$labelPath.Size = New-Object System.Drawing.Size(200, 23)
$labelPath.Text = "UNC-путь к папке:"
$form.Controls.Add($labelPath)

$textPath = New-Object System.Windows.Forms.TextBox
$textPath.Location = New-Object System.Drawing.Point(220, 20)
$textPath.Size = New-Object System.Drawing.Size(460, 23)
$textPath.Text = "\\storm.local\dfs\"
$form.Controls.Add($textPath)

# Корневая группа
$labelRoot = New-Object System.Windows.Forms.Label
$labelRoot.Location = New-Object System.Drawing.Point(20, 60)
$labelRoot.Size = New-Object System.Drawing.Size(200, 23)
$labelRoot.Text = "Корневая группа (без суффиксов):"
$form.Controls.Add($labelRoot)

$comboRoot = New-Object System.Windows.Forms.ComboBox
$comboRoot.Location = New-Object System.Drawing.Point(220, 60)
$comboRoot.Size = New-Object System.Drawing.Size(460, 23)
$comboRoot.DropDownStyle = "DropDown"
$form.Controls.Add($comboRoot)

# Загрузка корневых групп (без -T/-R/-W)
$rootTGroups = Get-ADGroupsByPattern "* -T"
$rootNames = $rootTGroups | ForEach-Object {
    if ($_.Name -match '^(.+?) -T$') { $matches[1] }
} | Sort-Object -Unique
foreach ($name in $rootNames) { $comboRoot.Items.Add($name)| Out-Null } 

# Отключаем обновление для скорости и подавляем вывод
$comboRoot.BeginUpdate()
foreach ($name in $rootNames) {
    $comboRoot.Items.Add($name) | Out-Null
}
$comboRoot.EndUpdate()



# Имя группы
$labelGroupName = New-Object System.Windows.Forms.Label
$labelGroupName.Location = New-Object System.Drawing.Point(20, 100)
$labelGroupName.Size = New-Object System.Drawing.Size(200, 23)
$labelGroupName.Text = "Имя новой группы (без суффиксов):"
$form.Controls.Add($labelGroupName)

$textGroupName = New-Object System.Windows.Forms.TextBox
$textGroupName.Location = New-Object System.Drawing.Point(220, 100)
$textGroupName.Size = New-Object System.Drawing.Size(380, 23)
$form.Controls.Add($textGroupName)

# Кнопка "Сгенерировать"
$btnGen = New-Object System.Windows.Forms.Button
$btnGen.Location = New-Object System.Drawing.Point(610, 100)
$btnGen.Size = New-Object System.Drawing.Size(70, 23)
$btnGen.Text = "Авто"
$btnGen.Add_Click({
    $path = $textPath.Text.Trim()
    $root = $comboRoot.Text.Trim()
    if (!$path -or !$root) {
        [System.Windows.Forms.MessageBox]::Show("Заполните UNC-путь и выберите корневую группу.", "Ошибка", "OK", "Error")
        return
    }
    if (!$path.StartsWith("\\")) {
        [System.Windows.Forms.MessageBox]::Show("Путь должен быть UNC (начинаться с \\).", "Ошибка", "OK", "Error")
        return
    }
    $parts = $path.TrimEnd('\').Split('\')
    if ($parts.Count -lt 4) {
        [System.Windows.Forms.MessageBox]::Show("Путь должен содержать хотя бы \\сервер\шара\папка", "Ошибка", "OK", "Error")
        return
    }
    $folderName = $parts[-1]
    $textGroupName.Text = "$root $folderName"
})
$form.Controls.Add($btnGen)

# Кнопка "Выполнить"
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Location = New-Object System.Drawing.Point(280, 150)
$btnRun.Size = New-Object System.Drawing.Size(160, 35)
$btnRun.Text = "Настроить права"
$btnRun.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 10)
$btnRun.Add_Click({
    $RootGroup = $comboRoot.Text.Trim()
    $UNCPath = $textPath.Text.Trim()
    $GroupName = $textGroupName.Text.Trim()

    if (!$RootGroup -or !$UNCPath) {
        [System.Windows.Forms.MessageBox]::Show("Заполните все обязательные поля!", "Ошибка", "OK", "Error")
        return
    }

    # Получаем базовый путь из описания корневой -T группы
    $rootTGroup = Get-ADGroup -Filter "Name -eq '$RootGroup -T'" -Properties Description -ErrorAction SilentlyContinue
    if (!$rootTGroup -or [string]::IsNullOrWhiteSpace($rootTGroup.Description)) {
        [System.Windows.Forms.MessageBox]::Show("У группы '$RootGroup -T' нет описания с путём!", "Ошибка", "OK", "Error")
        return
    }
    $basePath = $rootTGroup.Description.TrimEnd('\')
    $folderName = ($UNCPath.TrimEnd('\').Split('\'))[-1]
    $FullPath = "$basePath\$folderName"

    # Формируем имена групп
    if ([string]::IsNullOrWhiteSpace($GroupName)) {
        $GroupName = "$RootGroup $folderName"
    }
    $GroupT = "$GroupName -T"
    $GroupR = "$GroupName -R"
    $GroupW = "$GroupName -W"

    # Создание групп
    Ensure-ADGroup $GroupT $FullPath
    Ensure-ADGroup $GroupR $FullPath
    Ensure-ADGroup $GroupW $FullPath


    # Вложение групп в иерархию
    # Дочерние группы включаются в корневые Traverse
    # * Пока не понял зачем, так было сделано в старом скрипте.
    Add-ToGroup "$RootGroup -T" $GroupT
    Add-ToGroup "$RootGroup -T" $GroupR
    Add-ToGroup "$RootGroup -T" $GroupW


    # В корневые группы включаются дочерние 
    # * Для схранения доступа без наследования
    # * Пользователь в корневой группе одновременно является члоеном дочерней. 
    Add-ToGroup $GroupR "$RootGroup -R"  # GroupR → входит в Root-R
    Add-ToGroup $GroupW "$RootGroup -W"  # GroupW → входит в Root-W


    # Назначение прав
    $permissions = @{
        $GroupT = "Traverse"
        $GroupR = "Read"
        $GroupW = "Modify"
    }
    Set-FolderPermissions -FolderPath $FullPath -GroupPermissions $permissions -RootGroup $RootGroup

    [System.Windows.Forms.MessageBox]::Show("Настройка завершена!", "Готово", "OK", "Information")
    $form.Close()
})
$form.Controls.Add($btnRun)

# Запуск
[void]$form.ShowDialog()
