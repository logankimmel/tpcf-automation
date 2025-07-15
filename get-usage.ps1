# PowerShell script to get CF usage summary (AIs and SIs) for all organizations
# Usage: .\Get-CFUsageSummary.ps1

# Enable strict error handling
$ErrorActionPreference = "Stop"

# Function to load all pages from CF API
function Get-AllPages {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )
    
    $AllData = @()
    $CurrentUrl = $Url
    
    while ($CurrentUrl -ne "null" -and $null -ne $CurrentUrl) {
        try {
            $Response = cf curl $CurrentUrl | ConvertFrom-Json
            if ($LASTEXITCODE -ne 0) {
                throw "cf curl failed with exit code $LASTEXITCODE"
            }
            
            # Add resources to our collection
            $AllData += $Response.resources
            
            # Get next URL
            $CurrentUrl = $Response.pagination.next.href
            if ([string]::IsNullOrEmpty($CurrentUrl)) {
                $CurrentUrl = "null"
            }
        }
        catch {
            Write-Error "Failed to fetch data from CF API endpoint: $CurrentUrl - $($_.Exception.Message)"
            throw
        }
    }
    
    return $AllData
}

# Function to safely execute cf curl and return JSON
function Invoke-CfCurl {
    param([string]$Endpoint)
    
    try {
        $result = cf curl $Endpoint
        if ($LASTEXITCODE -ne 0) {
            throw "cf curl failed with exit code $LASTEXITCODE"
        }
        return $result | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to fetch data from CF API endpoint: $Endpoint - $($_.Exception.Message)"
        throw
    }
}

# Function to check prerequisites
function Test-Prerequisites {
    # Check if cf CLI is installed
    try {
        $null = Get-Command cf -ErrorAction Stop
    }
    catch {
        Write-Error "cf CLI is required but not installed. Please install cf CLI first."
        exit 1
    }
    
    # Test CF API access
    try {
        $null = cf curl "/v3/info" 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "CF API access failed"
        }
    }
    catch {
        Write-Error "Unable to access CF API. Please ensure you're logged in with 'cf login'"
        exit 1
    }
}

# Main script execution
try {
    Write-Host "Starting CF Usage Summary script..."
    
    # Test prerequisites
    Test-Prerequisites
    
    # Get all organizations
    Write-Host "Fetching all organizations..."
    $AllOrgs = Get-AllPages -Url "/v3/organizations"
    
    # Extract organization names
    $OrgNames = $AllOrgs | ForEach-Object { $_.name }
    
    # Initialize totals
    $TotalAIs = 0
    $TotalSIs = 0
    
    # Loop through organizations
    foreach ($OrgName in $OrgNames) {
        # Skip the system org
        if ($OrgName -ne "system") {
            # Output current org being processed
            Write-Host "Processing $OrgName..."
            
            # Get organization GUID
            $OrgGuid = ($AllOrgs | Where-Object { $_.name -eq $OrgName }).guid
            
            if ([string]::IsNullOrEmpty($OrgGuid)) {
                Write-Warning "Could not find GUID for organization: $OrgName"
                continue
            }
            
            # Get the usage summary for this organization
            try {
                $Summary = Invoke-CfCurl -Endpoint "/v3/organizations/$OrgGuid/usage_summary"
                
                # Extract AIs and SIs
                $AIs = $Summary.usage_summary.started_instances
                $SIs = $Summary.usage_summary.service_instances
                
                # Handle null values
                if ($null -eq $AIs) { $AIs = 0 }
                if ($null -eq $SIs) { $SIs = 0 }
                
                # Output AIs and SIs for this org
                Write-Host "AIs: $AIs"
                Write-Host "SIs: $SIs"
                Write-Host ""
                
                # Add to totals
                $TotalAIs += $AIs
                $TotalSIs += $SIs
            }
            catch {
                Write-Warning "Failed to get usage summary for organization $OrgName ($OrgGuid): $($_.Exception.Message)"
                continue
            }
        }
    }
    
    # Output final totals
    Write-Host "Total AIs: $TotalAIs"
    Write-Host "Total SIs: $TotalSIs"
    
    Write-Host "Script completed successfully."
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}
