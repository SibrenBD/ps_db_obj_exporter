# run this first to install the module
# Install-Module -Name SqlServer -Scope CurrentUser -AllowClobber

Import-Module SqlServer

# Configuration
$serverName = "localhost"
$databaseName = "AdventureWorks2022"
$outputDir = "C:\Users\sibre\OneDrive\Bureaublad\ps-test\export1" # Directory where everything will be exported
$timestamp = Get-Date -Format "dd-MM-yyyy_HH-mm-ss" # Timestamp for the log file name
$logFile = "C:\Users\sibre\OneDrive\Bureaublad\ps-test\Log_$timestamp.txt" # File full path. Make sure to fill in the path

# Create main output directory if it doesn't exist
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Create logs directory if it doesn't exist
$logDir = Split-Path $logFile
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force
}

# Function to write messages to the log file
function Write-Log {
    param (
        [string]$message,
        [string]$level = "INFO"
    )
    $timestamp = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    Add-Content -Path $logFile -Value $logEntry
}

# Function to script and export objects
function Export-Objects {
    param (
        [string]$typeName,
        [System.Collections.ICollection]$objects,
        [bool]$isTable = $false
    )

    # Create subdirectory for object type
    $typeDir = Join-Path $outputDir $typeName
    if (-not (Test-Path $typeDir)) {
        New-Item -ItemType Directory -Path $typeDir | Out-Null
    }

    foreach ($obj in $objects) {
        if (-not $obj.IsSystemObject) {
            $localScripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter($server)

            # Configure scripter start options
            $localScripter.Options.FileName = Join-Path $typeDir "$($obj.Schema)_$($obj.Name)_$typeName.sql"
            $localScripter.Options.ScriptBatchTerminator = $true
            $localScripter.Options.IncludeDatabaseContext = $true
            $localScripter.Options.ToFileOnly = $true
            $localScripter.Options.IncludeIfNotExists = $true
            $localScripter.Options.AppendToFile = $false

            # Generates drop
            if (-not $isTable) {
                $localScripter.Options.ScriptDrops = $true
            }
            $localScripter.Script($obj)

            # Generates create
            $localScripter.Options.IncludeIfNotExists = $false
            $localScripter.Options.ScriptDrops = $false
            $localScripter.Options.IncludeDatabaseContext = $false
            if(-not $isTable) {
                $localScripter.Options.AppendToFile = $true
            }
            $localScripter.Script($obj)

            Write-Host("Exported file: $($obj.Schema)_$($obj.Name)_$typeName.sql")
            Write-Log -message "Exported file: $($obj.Schema)_$($obj.Name)_$typeName.sql" -level "EXPORT"
        }
    }
}


function Compare-Directories {
    param (
        [string]$dir1,
        [string]$dir2
    )

    Write-Host "start compare"

    # Get all .txt files recursively
    $files1 = Get-ChildItem -Path $dir1 -Filter *.sql -Recurse -File
    $files2 = Get-ChildItem -Path $dir2 -Filter *.sql -Recurse -File

    # Create a lookup table for dir2 files by relative path
    $relativeFiles2 = @{}
    foreach ($file in $files2) {
        $relativePath = $file.FullName.Substring($dir2.Length).TrimStart('\')
        $relativeFiles2[$relativePath] = $file.FullName
    }

    foreach ($file1 in $files1) {
        $relativePath = $file1.FullName.Substring($dir1.Length).TrimStart('\')

        if ($relativeFiles2.ContainsKey($relativePath)) {
            $file2Path = $relativeFiles2[$relativePath]
            $content1 = Get-Content $file1.FullName
            $content2 = Get-Content $file2Path

            $diff = Compare-Object $content1 $content2

            if ($diff) {
                Write-Host "DIFFERENT: $relativePath"
                $diff | Format-Table InputObject, SideIndicator
            } else {
                Write-Host "MATCH: $relativePath"
            }
        } else {
            Write-Host "ONLY IN DIR1: $relativePath"
        }
    }

    # Check for files only in dir2
    foreach ($relativePath in $relativeFiles2.Keys) {
        $file1Path = Join-Path $dir1 $relativePath
        if (-not (Test-Path $file1Path)) {
            Write-Host "ONLY IN DIR2: $relativePath"
        }
    }
}

# Connect to SQL Server

# Create a custom connection string
$connectionString = "Data Source=$($serverName);Initial Catalog=$($databaseName);Integrated Security=True;Encrypt=True;TrustServerCertificate=True;"
 
# Create a ServerConnection using the connection string
$connection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection
$connection.ConnectionString = $connectionString

$server = New-Object Microsoft.SqlServer.Management.Smo.Server($connection)
$database = $server.Databases[$databaseName]

if ($null -eq $database) {
    Write-Host "Database '$databaseName' not found on server '$serverName'."
    exit
}

# Export each object type to its designated subdirectory
try {
    # Export-Objects -typeName "Table" -objects $database.Tables -isTable $true
    # Export-Objects -typeName "View" -objects $database.Views
    # Export-Objects -typeName "StoredProcedure" -objects $database.StoredProcedures
    # Export-Objects -typeName "User defined function" -objects $database.UserDefinedFunctions
    # Export-Objects -typeName "Schema" -objects $database.Schemas
    # Export-Objects -typeName "User" -objects $database.Users
    # Export-Objects -typeName "Role" -objects $database.Roles
    # Export-Objects -typeName "SqlAssembly" -objects $database.Assemblies
}
catch {
    Write-Log -message $_.Exception.Message -level "ERROR"
}

Write-log -message "Export complete. Files saved to: $outputDir"
Write-Host "`nExport complete. Files saved to: $outputDir"

# Start compare function
Compare-Directories -dir1 "$outputDir" -dir2 "C:\Users\sibre\OneDrive\Bureaublad\ps-test\export2"