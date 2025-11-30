<#
.Synopsis
   Generate create script for one or more database objects.
.DESCRIPTION
   <ToDo>
.PARAMETER parObjectType
   Tables, Views, UserDefinedFunctions, StoredProcedures, Users, Roles, Schemas
.EXAMPLE
   GenerateDbScript -parServerName msd-bi01 -parDatabaseName dbBiDwh -parObjectName DimLeerweg
#>

# 2025-11-26:1414, booo01;


param(
	[Parameter(Mandatory=$true)][ValidateSet("MSD-BI01", "MSD-CC01")][string]$parServerName
	,[Parameter(Mandatory=$true)]
	[ValidateSet(  #ArgumentCompletions
		"dbBiCon"
		,"dbBiDwh"
		,"dbBiExc"
		,"dbBiRpt"
		,"dbBiStg"
		,"MondriaanDWH_RAP"
		,"MondriaanDWH_DATAVAULT"
		,"MondriaanDWH_RAP_ExtraComptabel"
		,"MondriaanDWH_RAP_Staging"
		,"dbMiReport"
		,"dbOpleidingenaanbod"
		,"dbMiBron"
	)]
	[string]$parDatabaseName
	,[string]$parObjectName
	,[ValidateSet("Tables", "Views", "UserDefinedFunctions", "StoredProcedures", "Users", "Roles", "Schemas")][string]$parObjectType
	,[string]$parOutputDir = "C:\Users\adm_booo01\src\dbExport"
)

# $parServerName = "msd-bi01"
# $parDatabaseName = "dbBiDwh"
# $parObjectName = ""
# $parObjectType = ""
# $parOutputDir = "C:\Users\adm_booo01\src\dbExport"

#Import-Module SqlServer

# Reserved device names in Windows
$reservedNames = @("CON","PRN","AUX","NUL","COM1","COM2","COM3","COM4","COM5","COM6","COM7","COM8","COM9","LPT1","LPT2","LPT3","LPT4","LPT5","LPT6","LPT7","LPT8","LPT9")

# Database objects without schema
# $databaseLevelObjects = @("Schema", "User", "Role", "SqlAssembly")

# Built-in database roles
$builtInRoles = @(
	"db_owner","db_securityadmin","db_accessadmin","db_backupoperator",
	"db_ddladmin","db_datawriter","db_datareader",
	"db_denydatawriter","db_denydatareader", "public"
)

# Create main output directory if it doesn't exist
if (-not (Test-Path $parOutputDir)) {
	New-Item -ItemType Directory -Path $paroutputDir | Out-Null
} else {
	Remove-Item "$parOutputDir\*" -Recurse -Force
}

# Connect to SQL Server
# Load required assemblies (if not already loaded)
Add-Type -AssemblyName "Microsoft.SqlServer.Smo"
Add-Type -AssemblyName "Microsoft.SqlServer.ConnectionInfo"
Add-Type -AssemblyName "Microsoft.SqlServer.Management.Sdk.Sfc"

# Create connection string
$connectionString = "Data Source=$parServername;Initial Catalog=$parDatabaseName;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;"

# Create a ServerConnection using the connection string
$connection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection
$connection.ConnectionString = $connectionString

# Create the SMO Server object
$server = New-Object Microsoft.SqlServer.Management.Smo.Server($connection)

$database = $server.Databases[$parDatabaseName]
if (-not $database) {
	Write-Error "Database '$parDatabaseName' not found on server '$parServerName'."
	exit
}


# Create scripter
$scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter($server)
$scripter.Options.ScriptForCreateOrAlter = $true
$scripter.Options.IncludeHeaders = $true
$scripter.Options.SchemaQualify = $true

# Collections map
$collections = @{
	"Tables"              = $database.Tables
	"Views"               = $database.Views
	"StoredProcedures"    = $database.StoredProcedures
	"UserDefinedFunctions"= $database.UserDefinedFunctions
	"Users"            = $database.Users
	"Schemas"            = $database.Schemas
	"Roles"            = $database.Roles
}


function Export-Object($obj) {
	
	# Skip builtin roles
	if ($builtInRoles -contains $obj.Name) {
		return
	}

	# Get object type
	$ObjectType = $obj.GetType().Name

	# Create subdirectory for object type
	$typeDir = Join-Path $parOutputDir $ObjectType
	if (-not (Test-Path $typeDir)) {
		New-Item -ItemType Directory -Path $typeDir | Out-Null
	}

	# Sanitize names
	$schemaSafe = ($obj.Schema -replace '[\\/:*?"<>|]', '_')
	$nameSafe   = ($obj.Name   -replace '[\\/:*?"<>|]', '_')
	if ($reservedNames -contains $nameSafe) {  # windows does not allow a file to start with "con."
		$nameSafe = "$($nameSafe)_"  # add underscore
	}

	# Build filename
	$fileName =	switch ($schemaSafe) {
		"" {"$($nameSafe).$($ObjectType).sql"}
		Default {"$($schemaSafe).$($nameSafe).$($ObjectType).sql"}
	}
	# Write-Host $fileName
	# return
			
	# Create Scripter instance
	$scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter($server)

	# Configure scripter start options
	$scripter.Options.FileName = Join-Path $typeDir $fileName
	$scripter.Options.Encoding = New-Object System.Text.UTF8Encoding($false)  # UTF-8 without BOM
	$scripter.Options.ScriptBatchTerminator = $true
	$scripter.Options.IncludeDatabaseContext = $true
	$scripter.Options.ToFileOnly = $true
	$scripter.Options.AppendToFile = $false
	$scripter.Options.Permissions = $true

	# Configure scripter drop options
	$scripter.Options.IncludeIfNotExists = $true
	$scripter.Options.ScriptDrops = $true

	# Generate drop, only when 'create or alter' is not supported
	if ($ObjectType -in @("Schema", "User", "DatabaseRole")) {
		$scripter.Script($obj)
	}

	# Configure scripter create options
	$scripter.Options.IncludeIfNotExists = $false
	$scripter.Options.ScriptDrops = $false
	$scripter.Options.AppendToFile = $true

	# Modify options per object type, if neccessary
	switch ($ObjectType) {
		"Table" {
			$scripter.Options.IncludeDatabaseContext = $true
			$scripter.Options.Bindings = $true  # column defaults
			$scripter.Options.DriAll = $true  # all keys, ref. constaints
			$scripter.Options.ClusteredIndexes = $true
			$scripter.Options.NonClusteredIndexes = $true
			$scripter.Options.ColumnStoreIndexes = $true
			$scripter.Options.Triggers = $true
		}
		{$_ -in @("View", "UserDefinedFunction", "StoredProcedure")} {
			$scripter.Options.IncludeDatabaseContext = $true
			$scripter.Options.ScriptForCreateOrAlter = $true  # ipv drop en create; permissions blijven intakt;
			$scripter.Options.EnforceScriptingOptions = $true  # apparently needed for ScriptForCreateOrAlter to work
		}
		{$_ -in @("Schema", "User", "DatabaseRole")} {
			$scripter.Options.IncludeDatabaseContext = $false
		}
		"User" {
			$scripter.Options.IncludeDatabaseRoleMemberships = $true
		}
		Default {}
	}

	# Generate create
	$scripter.Script($obj)

	Write-Host("Exported file: $($scripter.Options.FileName)")
}

# Logic
if ($parObjectType) {
	if ($collections.ContainsKey($parObjectType)) {
		if ($parObjectName) {
			$found = $false
			foreach ($obj in $collections[$parObjectType]) {
				if ($obj.Name -eq $parObjectName -and -not $obj.IsSystemObject) {
					Export-Object $obj
					$found = $true
				}
			}
			if (-not $found) {
				Write-Error "Object '$parObjectName' not found in $parObjectType."
			}
		} else {
			foreach ($obj in $collections[$parObjectType]) {
				if (-not $obj.IsSystemObject) {
					Export-Object $obj
				}
			}
		}
	} else {
		Write-Error "Invalid parObjectType '$parObjectType'. Valid types: $($collections.Keys -join ', ')"
	}
}
elseif ($parObjectName) {
	$found = $false
	foreach ($key in $collections.Keys) {
	    foreach ($obj in $collections[$key]) {
	        if ($obj.Name -eq $parObjectName -and -not $obj.IsSystemObject) {
				Export-Object $obj
				$found = $true
			}
		}
	}
	if (-not $found) {
		Write-Error "Object '$parObjectName' not found in any collection."
	}
}
else {
	foreach ($key in $collections.Keys) {
		foreach ($obj in $collections[$key]) {
			if (-not $obj.IsSystemObject) {
				Export-Object $obj
			}
		}
	}
}