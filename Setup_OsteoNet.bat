<# :
@echo off
chcp 65001 > nul
setlocal
cd /d "%~dp0"

:: Check for Admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo [!] Requesting Admin rights...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~dpnx0\"\"' -Verb RunAs"
    exit /b
)

:: Launch PowerShell part
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0'))"
exit /b
#>

# ==============================================================================================
#  OSTEO NET INSTALLER (PowerShell GUI)
# ==============================================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Configuration ---
$ProjectUrl = "https://github.com/Grilly-r/Osteoarthritis/archive/refs/heads/main.zip"
$ZipName = "project.zip"
$AppName = "Osteonet"
$ScriptFile = "app.pyw"
$IconFile = "data/icon.ico"
$RequirementsFile = "requirements.txt"
$TrainScript = "train_model.py"

# --- GUI Setup ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Установка: $AppName"
$form.Size = New-Object System.Drawing.Size(500, 400)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::White

# Fonts
$fontHeader = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$fontNormal = New-Object System.Drawing.Font("Segoe UI", 10)
$fontSmall = New-Object System.Drawing.Font("Segoe UI", 9)

# Header
$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Text = $AppName
$lblHeader.Font = $fontHeader
$lblHeader.AutoSize = $true
$lblHeader.Location = New-Object System.Drawing.Point(20, 20)
$lblHeader.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215) # Blue
$form.Controls.Add($lblHeader)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "Автоматическая установка и настройка"
$lblSub.Font = $fontNormal
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(22, 50)
$lblSub.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($lblSub)

# Status Area
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$txtLog.Location = New-Object System.Drawing.Point(20, 90)
$txtLog.Size = New-Object System.Drawing.Size(445, 160)
$txtLog.Font = $fontSmall
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$txtLog.Text = "Готов к установке..."
$form.Controls.Add($txtLog)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 260)
$progressBar.Size = New-Object System.Drawing.Size(445, 20)
$progressBar.Style = "Continuous"
$form.Controls.Add($progressBar)

# Checkbox
$chkShortcut = New-Object System.Windows.Forms.CheckBox
$chkShortcut.Text = "Создать ярлык на рабочем столе"
$chkShortcut.Checked = $true
$chkShortcut.Font = $fontNormal
$chkShortcut.AutoSize = $true
$chkShortcut.Location = New-Object System.Drawing.Point(20, 290)
$form.Controls.Add($chkShortcut)

# Button
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Начать установку"
$btnInstall.Font = $fontNormal
$btnInstall.Location = New-Object System.Drawing.Point(150, 320)
$btnInstall.Size = New-Object System.Drawing.Size(180, 35)
$btnInstall.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnInstall.ForeColor = [System.Drawing.Color]::White
$btnInstall.FlatStyle = "Flat"
$form.Controls.Add($btnInstall)

# --- Helper Functions ---
function Log($message) {
    $form.Invoke([Action]{ 
        $txtLog.AppendText([Environment]::NewLine + $message) 
        $txtLog.SelectionStart = $txtLog.Text.Length
        $txtLog.ScrollToCaret()
    })
}

function Set-Progress($value, $style="Continuous") {
    $form.Invoke([Action]{ 
        $progressBar.Style = $style
        if ($style -eq "Continuous") { $progressBar.Value = $value }
    })
}

function Enable-Controls($enable) {
    $form.Invoke([Action]{ 
        $btnInstall.Enabled = $enable 
        $chkShortcut.Enabled = $enable
    })
}

# --- Installation Logic ---
$action = {
    param($form, $txtLog, $progressBar, $btnInstall, $chkShortcut, $ProjectUrl, $ZipName, $AppName, $ScriptFile, $IconFile, $RequirementsFile, $TrainScript)
    
    # Helper for inner logging (since we are in a different runspace/thread context effectively, but here strictly inside Click event)
    # Actually, we will run this async.
    
    $CurrentDir = [System.IO.Directory]::GetCurrentDirectory()
    
    # 1. Check Python
    Log "Проверка Python..."
    Set-Progress 10
    
    try {
        $pyVersion = python --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Log "Python не найден. Скачивание..."
            Set-Progress 15 "Marquee"
            
            $pyInstaller = "python_installer.exe"
            $pyUrl = "https://www.python.org/ftp/python/3.11.5/python-3.11.5-amd64.exe"
            
            Invoke-WebRequest -Uri $pyUrl -OutFile $pyInstaller
            
            Log "Установка Python (это может занять пару минут)..."
            Start-Process -FilePath $pyInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait
            
            Remove-Item $pyInstaller -ErrorAction SilentlyContinue
            
            # Update Path for this session
            $env:Path = "$env:ProgramFiles\Python311\Scripts;$env:ProgramFiles\Python311;$env:Path"
            Log "Python установлен."
        } else {
            Log "Python найден: $pyVersion"
        }
    } catch {
        Log "Ошибка при проверке Python: $_"
        Enable-Controls $true
        return
    }

    # 2. Download Project (if needed)
    Set-Progress 30 "Continuous"
    if (-not (Test-Path $ScriptFile)) {
        Log "Скачивание файлов проекта..."
        try {
            # Use TLS 1.2
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $ProjectUrl -OutFile $ZipName
            
            Log "Распаковка..."
            Expand-Archive -Path $ZipName -DestinationPath . -Force
            Remove-Item $ZipName
            
            # Move files from subdirectory
            $subDirs = Get-ChildItem -Directory
            foreach ($dir in $subDirs) {
                if (Test-Path "$($dir.FullName)\$ScriptFile") {
                    Log "Перемещение файлов из $($dir.Name)..."
                    Copy-Item -Path "$($dir.FullName)\*" -Destination . -Recurse -Force
                    Remove-Item $dir.FullName -Recurse -Force
                }
            }
            
            if (Test-Path "DISTRIBUTION.txt") { Remove-Item "DISTRIBUTION.txt" }
            
        } catch {
            Log "Ошибка скачивания: $_"
            Enable-Controls $true
            return
        }
    } else {
        Log "Файлы проекта уже на месте."
    }

    # 3. Install Requirements
    Log "Установка зависимостей (pip)..."
    Set-Progress 50 "Marquee"
    
    try {
        $pipProc = Start-Process -FilePath "python" -ArgumentList "-m pip install -r $RequirementsFile" -NoNewWindow -PassThru -Wait
        if ($pipProc.ExitCode -ne 0) {
            Log "ВНИМАНИЕ: Возможна ошибка при установке библиотек."
        } else {
            Log "Библиотеки установлены."
        }
    } catch {
        Log "Ошибка pip: $_"
    }

    # 4. Train Model
    Log "Настройка нейросети (обучение)..."
    Set-Progress 70 "Marquee"
    try {
        if (Test-Path $TrainScript) {
            $trainProc = Start-Process -FilePath "python" -ArgumentList $TrainScript -NoNewWindow -PassThru -Wait
            if ($trainProc.ExitCode -ne 0) {
                Log "Ошибка при обучении модели."
            } else {
                Log "Модель успешно настроена."
            }
        }
    } catch {
        Log "Ошибка обучения: $_"
    }

    # 5. Create Shortcut
    Set-Progress 90 "Continuous"
    if ($chkShortcut.Checked) {
        Log "Создание ярлыка..."
        try {
            $WshShell = New-Object -comObject WScript.Shell
            $DesktopPath = [Environment]::GetFolderPath("Desktop")
            $Shortcut = $WshShell.CreateShortcut("$DesktopPath\$AppName.lnk")
            
            # Target pythonw.exe to run without console
            # Find pythonw path
            $pythonPath = (Get-Command python).Source
            $pythonwPath = $pythonPath.Replace("python.exe", "pythonw.exe")
            
            $Shortcut.TargetPath = $pythonwPath
            $Shortcut.Arguments = """$CurrentDir\$ScriptFile"""
            $Shortcut.WorkingDirectory = $CurrentDir
            
            if (Test-Path "$CurrentDir\$IconFile") {
                $Shortcut.IconLocation = "$CurrentDir\$IconFile"
            }
            
            $Shortcut.Save()
            Log "Ярлык создан на рабочем столе."
        } catch {
            Log "Ошибка создания ярлыка: $_"
        }
    }

    Set-Progress 100
    Log "УСТАНОВКА ЗАВЕРШЕНА!"
    
    $form.Invoke([Action]{ 
        [System.Windows.Forms.MessageBox]::Show("Установка успешно завершена!", "Готово", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        $form.Close()
    })
}

$btnInstall.Add_Click({
    Enable-Controls $false
    
    # Run in background to keep UI responsive
    $scriptBlock = $action
    $params = @($form, $txtLog, $progressBar, $btnInstall, $chkShortcut, $ProjectUrl, $ZipName, $AppName, $ScriptFile, $IconFile, $RequirementsFile, $TrainScript)
    
    # Note: Running async with GUI updates is tricky in pure script. 
    # For simplicity/robustness in a single file, we'll use Force.DoEvents() or just run synchronously but repaint.
    # To avoid "Not Responding", we should use a job or runspace, but passing UI controls to a job is hard.
    # We will use a simpler approach: Process events inside the loop if possible, 
    # BUT since most commands are external (Start-Process -Wait), the UI will freeze.
    # To fix this, we'll use Start-Process WITHOUT -Wait inside a loop checking HasExited.
    
    # RE-IMPLEMENTING LOGIC FOR RESPONSIVE UI
    
    $CurrentDir = [System.IO.Directory]::GetCurrentDirectory()
    
    # 1. Check Python
    Log "Проверка Python..."
    $form.Refresh()
    
    $hasPython = $false
    try {
        $proc = Start-Process -FilePath "python" -ArgumentList "--version" -NoNewWindow -PassThru
        $proc.WaitForExit()
        if ($proc.ExitCode -eq 0) { $hasPython = $true }
    } catch {}
    
    if (-not $hasPython) {
        Log "Python не найден. Скачивание..."
        $form.Refresh()
        
        $pyUrl = "https://www.python.org/ftp/python/3.11.5/python-3.11.5-amd64.exe"
        $pyInstaller = "python_installer.exe"
        
        # Async download is hard, doing sync
        Invoke-WebRequest -Uri $pyUrl -OutFile $pyInstaller
        
        Log "Установка Python..."
        $form.Refresh()
        $proc = Start-Process -FilePath $pyInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -PassThru
        while (-not $proc.HasExited) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
        
        Remove-Item $pyInstaller -ErrorAction SilentlyContinue
        $env:Path = "$env:ProgramFiles\Python311\Scripts;$env:ProgramFiles\Python311;$env:Path"
    } else {
        Log "Python найден."
    }
    
    # 2. Download Project
    if (-not (Test-Path $ScriptFile)) {
        Log "Скачивание проекта..."
        $form.Refresh()
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $ProjectUrl -OutFile $ZipName
        
        Log "Распаковка..."
        $form.Refresh()
        Expand-Archive -Path $ZipName -DestinationPath . -Force
        Remove-Item $ZipName
        
        $subDirs = Get-ChildItem -Directory
        foreach ($dir in $subDirs) {
            if (Test-Path "$($dir.FullName)\$ScriptFile") {
                Copy-Item -Path "$($dir.FullName)\*" -Destination . -Recurse -Force
                Remove-Item $dir.FullName -Recurse -Force
            }
        }
        if (Test-Path "DISTRIBUTION.txt") { Remove-Item "DISTRIBUTION.txt" }
    }
    
    # 3. Pip Install
    Log "Установка библиотек (pip)..."
    $form.Refresh()
    $proc = Start-Process -FilePath "python" -ArgumentList "-m pip install -r $RequirementsFile" -NoNewWindow -PassThru
    while (-not $proc.HasExited) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
    
    # 4. Train
    Log "Обучение нейросети..."
    $form.Refresh()
    if (Test-Path $TrainScript) {
        $proc = Start-Process -FilePath "python" -ArgumentList $TrainScript -NoNewWindow -PassThru
        while (-not $proc.HasExited) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
    }
    
    # 5. Shortcut
    if ($chkShortcut.Checked) {
        Log "Создание ярлыка..."
        $WshShell = New-Object -comObject WScript.Shell
        $DesktopPath = [Environment]::GetFolderPath("Desktop")
        $Shortcut = $WshShell.CreateShortcut("$DesktopPath\$AppName.lnk")
        
        try {
             $pythonPath = (Get-Command python).Source
             $pythonwPath = $pythonPath.Replace("python.exe", "pythonw.exe")
        } catch {
             $pythonwPath = "pythonw.exe"
        }
        
        $Shortcut.TargetPath = $pythonwPath
        $Shortcut.Arguments = """$CurrentDir\$ScriptFile"""
        $Shortcut.WorkingDirectory = $CurrentDir
        if (Test-Path "$CurrentDir\$IconFile") {
            $Shortcut.IconLocation = "$CurrentDir\$IconFile"
        }
        $Shortcut.Save()
    }
    
    Log "ГОТОВО!"
    $progressBar.Value = 100
    [System.Windows.Forms.MessageBox]::Show("Установка успешно завершена!", "Готово", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    $form.Close()
})

$form.ShowDialog() | Out-Null
