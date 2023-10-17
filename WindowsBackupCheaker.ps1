# Указываем путь к папке WindowsImageBackup
$backupFolderPath = "D:\backups\WindowsImageBackup"

# Создаем пустой текстовый файл для записи результата
$resultFilePath = "C:\Users\User\Desktop\backuptest.txt"
New-Item -ItemType File -Path $resultFilePath -Force | Out-Null

# Функция для записи результата в текстовый файл
function Write-Log {
    param (
        [string]$message
    )
    $message | Out-File -Append -FilePath $resultFilePath -Encoding Unicode
}

# Функция для проверки наличия обязательных папок
function Check-RequiredFolders {
    param (
        [string]$computerFolder
    )
    $requiredFolders = @("Catalog", "Logs", "SPPMetadataCache")
    $missingFolders = @()

    foreach ($requiredFolder in $requiredFolders) {
        $folderPath = Join-Path -Path $computerFolder -ChildPath $requiredFolder
        if (-not (Test-Path -Path $folderPath -PathType Container)) {
            $missingFolders += $requiredFolder
        }
    }

    return $missingFolders
}

# Функция для проверки виртуальных образов
function Check-VHDXFiles {
    param (
        [string]$backupFolder,
        [ref]$flag
    )
    $vhdxFiles = Get-ChildItem -Path $backupFolder -Filter "*.vhdx"
    
    if ($vhdxFiles.Count -ge 3) {
        Write-Log "Found $($vhdxFiles.Count) .vhdx files in $($backupFolder)."
        foreach ($vhdxFile in $vhdxFiles) {
            try {
                $result = Test-VHD -Path $vhdxFile.FullName -ErrorAction Stop
                if ($result -eq $true) {
                    Write-Log "VHD file $($vhdxFile.Name) is valid."
                } else {
                    Write-Log "VHD file $($vhdxFile.Name) is invalid."
                    $flag = 0  # Если хотя бы одна проверка не выполнится на True, устанавливаем флаг в 0
                }
            } catch {
                $flag = 0
                Write-Log "Failed to check the integrity of $($vhdxFile.Name). Error: $($_.Exception.Message)"

            }
        }
    } else {
        Write-Log "Found only $($vhdxFiles.Count) .vhdx files in $($backupFolder). Need at least 3."
        $flag = 0  # Если меньше 3 vhdx файлов, устанавливаем флаг в 0
    }
    return $flag
}

# Проверка наличия папки WindowsImageBackup
if (Test-Path $backupFolderPath -PathType Container) {
    Write-Log "WindowsImageBackup is present."

    
    # Поиск вложенных папок с резервными копиями
    $computerFolders = Get-ChildItem -Path $backupFolderPath -Directory

    if ($computerFolders.Count -eq 0) {
        Write-Log "No backup copies in the WindowsImageBackup folder."
    } else {
        $flag = 1  

        # Перебираем все папки компьютеров
        foreach ($computerFolder in $computerFolders) {
            $flag = 1
            $lastBackupTime = (Get-Item $computerFolder.FullName).LastWriteTime
            Write-Log "Computer name: $($computerFolder.Name)"
            Write-Log "Last backup time: $lastBackupTime"

            # Проверка наличия файла MediaId в текущей папке компьютера
            $mediaIdFilePath = Join-Path -Path $computerFolder.FullName -ChildPath "MediaId"
            if (Test-Path -Path $mediaIdFilePath -PathType Leaf) {
                Write-Log "MediaId in folder $($computerFolder.Name)."
            } else {
                Write-Log "MediaId file is missing in folder $($computerFolder.Name)."
                $flag = 0  # Если файл MediaId отсутствует, устанавливаем флаг в 0
            }

            # Поиск папки "Backup" в текущей папке компьютера
            $backupFolders = Get-ChildItem -Path $computerFolder.FullName -Directory | Where-Object { $_.Name -match "^Backup \d{4}-\d{2}-\d{2} \d{6}$" }

            if ($backupFolders.Count -eq 0) {
                Write-Log "No folders with the 'Backup' pattern inside the computer folder."
                $flag = 0  # Если папки "Backup" отсутствуют, устанавливаем флаг в 0
            } else {
                # Перебираем все папки бэкапов компьютера
                foreach ($backupFolder in $backupFolders) {
                    Write-Log "Backup $backupCounter in folder $($backupFolder.Name):"

                    # Проверка наличия обязательных папок в текущей папке компьютера
                    $missingFolders = Check-RequiredFolders -computerFolder $computerFolder.FullName

                    if ($missingFolders.Count -eq 0) {
                        Write-Log "Required folders are present."
                    } else {
                        Write-Log "Missing required folders in $($computerFolder.Name): $($missingFolders -join ', ')"
                        $flag = 0  # Если одна из обязательных папок отсутствует, устанавливаем флаг в 0
                    }

                    # Проверка VHDX файлов
                    $flag = Check-VHDXFiles -backupFolder $backupFolder.FullName -flag ([ref]$flag)

                    # Проверка флага 
                    if ($flag.Value -eq 0) {
                        Write-Log "$($computerFolder.Name) Backup failed verification"
                    } else {
                        Write-Log "$($computerFolder.Name) Backup has been verified."

                    }

                    Write-Log "" 
                }
            }
        }
    }
} else {
    Write-Log "The WindowsImageBackup folder is missing."
}

Write-Log "Check completed."
