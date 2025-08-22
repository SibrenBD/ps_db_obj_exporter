# run this first to install the module
# Install-Module -Name SqlServer -Scope CurrentUser -AllowClobber

Import-Module SqlServer

# Configuration
$serverName = "localhost"
$databaseName = ""
$outputDir = ""

# Create main output directory if it doesn't exist
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
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
        }
    }
}

# Export each object type to its designated subdirectory
Export-Objects -typeName "Table" -objects $database.Tables -isTable $true
Export-Objects -typeName "View" -objects $database.Views
Export-Objects -typeName "StoredProcedure" -objects $database.StoredProcedures
Export-Objects -typeName "User defined function" -objects $database.UserDefinedFunctions
Export-Objects -typeName "Schema" -objects $database.Schemas
Export-Objects -typeName "User" -objects $database.Users
Export-Objects -typeName "Role" -objects $database.Roles
Export-Objects -typeName "SqlAssembly" -objects $database.Assemblies

Write-Host "`nExport complete. Files saved to: $outputDir"