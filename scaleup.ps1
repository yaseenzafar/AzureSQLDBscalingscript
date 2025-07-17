param (
    [Parameter(Mandatory = $true)]
    [string] $databaseName,

    [Parameter(Mandatory = $true)]
    [string] $databaseServer,

    [Parameter(Mandatory = $true)]
    [string] $databaseResourceGroup,

    [Parameter(Mandatory = $true)]
    [string] $subscription,

    [Parameter(Mandatory = $true)]
    [int] $maxCores,

    [Parameter(Mandatory = $true)]
    [int] $minCores,

    [Parameter(Mandatory = $true)]
    [int] $numCores,

    [Parameter(Mandatory = $true)]
    [ValidateSet("up", "down")]
    [string]$direction,

    [Parameter(Mandatory = $false)]
    [object[]]$replicas,

    [Parameter(Mandatory = $false)]
    [string]$slackWebhookUrl = "https://hooks.slack.com/services/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",

    [Parameter(Mandatory = $false)]
    [int]$timezoneOffset = 5,

    [Parameter(Mandatory = $false)]
    [int[]]$allowedHours = @(8,9,10,11,12,13,14,15,16,17,18,19,20,21,22)
)

# Global error handling
$ErrorActionPreference = "Stop"

# Configuration
$Script:Config = @{
    SlackWebhookUrl = $slackWebhookUrl
    TimezoneOffset = $timezoneOffset
    AllowedHours = $allowedHours
    SupportedSKUs = @("GP_Gen5")
}

#region Helper Functions

function Send-SlackNotification {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$WebhookUrl = $Script:Config.SlackWebhookUrl
    )
    
    try {
        $jsonPayload = @{ "text" = $Message } | ConvertTo-Json -Depth 3
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $jsonPayload -ContentType "application/json" -ErrorAction Stop
        Write-Verbose "Slack notification sent successfully"
    }
    catch {
        Write-Warning "Failed to send Slack notification: $($_.Exception.Message)"
    }
}

function Test-ScalingTimeWindow {
    $currentHour = (Get-Date).AddHours($Script:Config.TimezoneOffset).Hour
    Write-Output "Current time in hour is $currentHour"
    
    if ($Script:Config.AllowedHours -contains $currentHour) {
        Write-Output "Proceeding with scaling ops"
        return $true
    }
    else {
        $alertMessage = @"
*AZURE ALERT: CloudOps Team, Usage is high for $databaseName, scaleup is only enabled from $($Script:Config.AllowedHours[0]) to $($Script:Config.AllowedHours[-1]). Please proceed manually if needed*

*Resource:* /subscriptions/$subscription/resourceGroups/$databaseResourceGroup/providers/Microsoft.Sql/servers/$databaseServer/databases/$databaseName
*Status:* Fired
*UTC Time:* $((Get-Date).ToUniversalTime().ToString())
*Metric:* cpu_percentage
*Threshold:* above 90

*CloudOps Team, Usage is high for $databaseName, scaleup is only enabled from $($Script:Config.AllowedHours[0]) to $($Script:Config.AllowedHours[-1]). Please proceed manually if needed*
"@
        
        Send-SlackNotification -Message $alertMessage
        Write-Output "Current Time is : $currentHour Cannot perform scaling ops outside allowed time window"
        return $false
    }
}

function Get-TargetCoreCount {
    param(
        [int]$CurrentCores,
        [string]$Direction,
        [int]$NumCores,
        [int]$MaxCores,
        [int]$MinCores
    )
    
    $targetCores = switch ($Direction) {
        "up" { $CurrentCores + $NumCores }
        "down" { $CurrentCores - $NumCores }
    }
    
    # Validate against limits
    if ($targetCores -gt $MaxCores) {
        throw "Target cores ($targetCores) exceeds maximum allowed ($MaxCores)"
    }
    
    if ($targetCores -lt $MinCores) {
        throw "Target cores ($targetCores) is below minimum allowed ($MinCores)"
    }
    
    return $targetCores
}

#endregion

#region Main Functions

function Scale-Database {
    param(
        [string]$DbName,
        [string]$DbServer,
        [string]$ResourceGroup,
        [int]$TargetCores
    )
    
    try {
        Write-Output "Starting scaling process for $DbName on $DbServer"
        
        # Get current database
        $database = Get-AzSqlDatabase -ServerName $DbServer -DatabaseName $DbName -ResourceGroupName $ResourceGroup -ErrorAction Stop
        
        $currentCoreCount = $database.Capacity
        $skuName = $database.SkuName
        $resourceId = $database.ResourceId
        
        Write-Output "Current SKU: $skuName, Current Cores: $currentCoreCount, Target Cores: $TargetCores"
        
        # Validate SKU compatibility
        if ($skuName -notin $Script:Config.SupportedSKUs) {
            $errorMessage = @"
*AZURE ALERT: SCALING FAILED for $DbName*

*Resource:* $resourceId
*Status:* Failed
*UTC Time:* $((Get-Date).ToUniversalTime().ToString())
*Reason:* Unsupported SKU '$skuName'. Supported SKUs: $($Script:Config.SupportedSKUs -join ', ')

Please change service tier from Azure portal.
"@
            Send-SlackNotification -Message $errorMessage
            throw "Unsupported SKU: $skuName"
        }
        
        # Send pre-scaling notification
        $preScalingMessage = @"
*AZURE ALERT: SCALING $($direction.ToUpper()) $DbName*

*Resource:* $resourceId
*Status:* Starting
*UTC Time:* $((Get-Date).ToUniversalTime().ToString())
*Current Cores:* $currentCoreCount
*Target Cores:* $TargetCores
*SKU:* $skuName
"@
        Send-SlackNotification -Message $preScalingMessage
        
        # Perform scaling
        Write-Output "Executing scaling operation..."
        Set-AzSqlDatabase -ResourceGroupName $ResourceGroup -ServerName $DbServer -DatabaseName $DbName -VCore $TargetCores -ErrorAction Stop
        
        # Verify scaling success
        Start-Sleep -Seconds 30  # Wait for scaling to complete
        $updatedDatabase = Get-AzSqlDatabase -ServerName $DbServer -DatabaseName $DbName -ResourceGroupName $ResourceGroup -ErrorAction Stop
        
        if ($updatedDatabase.Capacity -eq $TargetCores) {
            $successMessage = @"
*AZURE ALERT: SCALING SUCCESS for $DbName*

*Resource:* $resourceId
*Status:* Completed Successfully
*UTC Time:* $((Get-Date).ToUniversalTime().ToString())
*Previous Cores:* $currentCoreCount
*New Cores:* $($updatedDatabase.Capacity)
*License Type:* $($updatedDatabase.LicenseType)
*Tier:* $($updatedDatabase.Edition)
"@
            Send-SlackNotification -Message $successMessage
            Write-Output "Scaling completed successfully"
        }
        else {
            throw "Scaling verification failed. Expected: $TargetCores, Actual: $($updatedDatabase.Capacity)"
        }
    }
    catch {
        $errorMessage = @"
*AZURE ALERT: SCALING FAILED for $DbName*

*Resource:* /subscriptions/$subscription/resourceGroups/$ResourceGroup/providers/Microsoft.Sql/servers/$DbServer/databases/$DbName
*Status:* Failed
*UTC Time:* $((Get-Date).ToUniversalTime().ToString())
*Error:* $($_.Exception.Message)

Manual intervention required.
"@
        Send-SlackNotification -Message $errorMessage
        Write-Error "Scaling failed: $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Main Script Execution

try {
    # Validate time window
    if (-not (Test-ScalingTimeWindow)) {
        exit 1
    }
    
    # Connect to Azure and set context
    Write-Output "Connecting to Azure..."
    Connect-AzAccount -Identity -ErrorAction Stop
    Set-AzContext -SubscriptionId $subscription -ErrorAction Stop
    
    # Get current database to calculate target cores
    $currentDatabase = Get-AzSqlDatabase -ServerName $databaseServer -DatabaseName $databaseName -ResourceGroupName $databaseResourceGroup -ErrorAction Stop
    $targetCoreCount = Get-TargetCoreCount -CurrentCores $currentDatabase.Capacity -Direction $direction -NumCores $numCores -MaxCores $maxCores -MinCores $minCores
    
    # Define scaling sign for logging
    $scalingSign = if ($direction -eq "up") { "+" } else { "-" }
    
    # Execute scaling based on replica configuration
    if (-not $replicas) {
        Write-Output "Single database with no replicas specified."
        Write-Output "Scaling $databaseName by $scalingSign$numCores cores to $targetCoreCount total cores."
        
        Scale-Database -DbName $databaseName -DbServer $databaseServer -ResourceGroup $databaseResourceGroup -TargetCores $targetCoreCount
    }
    else {
        Write-Output "Database with replica(s) specified. Scaling replicas first, then primary."
        
        # Scale replicas first
        foreach ($replica in $replicas) {
            Write-Output "Scaling replica: $databaseName on $replica by $scalingSign$numCores cores to $targetCoreCount total cores."
            try {
                # ✅ Attempt to scale the replica within its own try/catch block.
                Scale-Database -DbName $databaseName -DbServer $replica -ResourceGroup $databaseResourceGroup -TargetCores $targetCoreCount
            }
            catch {
                # ✅ If a single replica fails, log the warning and continue to the next one.
                Write-Warning "Failed to scale replica on server '$replica'. Error: $($_.Exception.Message). Continuing with other operations."
                # Optionally, send a non-critical Slack notification for the specific replica failure here.
            }
        }
        
        # Scale primary database last
        Write-Output "Scaling primary: $databaseName on $databaseServer by $scalingSign$numCores cores to $targetCoreCount total cores."
        Scale-Database -DbName $databaseName -DbServer $databaseServer -ResourceGroup $databaseResourceGroup -TargetCores $targetCoreCount
    }
    
    Write-Output "All scaling operations completed successfully."
}
catch {
    $criticalErrorMessage = @"
*CRITICAL: Azure SQL Scaling Script Failed*

*Database:* $databaseName
*Server:* $databaseServer
*UTC Time:* $((Get-Date).ToUniversalTime().ToString())
*Error:* $($_.Exception.Message)

Immediate attention required.
"@
    Send-SlackNotification -Message $criticalErrorMessage
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}

#endregion
