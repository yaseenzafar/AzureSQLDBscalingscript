# Azure SQL Database Scaling Script with Enhanced Trigger Tracking
# Purpose: Scales Azure SQL Database cores down based on performance metrics
# Enhanced: Includes detailed trigger context and audit trail

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
    [string]$direction,

    [Parameter(Mandatory = $false)]
    [object[]]$replicas,

    # Enhanced trigger context parameters
    [Parameter(Mandatory = $false)]
    [string]$triggerSource = "Unknown",  # Manual, Alert, Schedule, Webhook

    [Parameter(Mandatory = $false)]
    [string]$alertRuleName = "",

    [Parameter(Mandatory = $false)]
    [string]$alertResourceId = "",

    [Parameter(Mandatory = $false)]
    [string]$automationJobId = "",

    [Parameter(Mandatory = $false)]
    [string]$automationAccountName = "",

    [Parameter(Mandatory = $false)]
    [string]$runbookName = "",

    [Parameter(Mandatory = $false)]
    [string]$triggeredBy = "",  # User email or system

    [Parameter(Mandatory = $false)]
    [hashtable]$alertContext = @{},

    [Parameter(Mandatory = $false)]
    [string]$originalMetricValue = "",

    [Parameter(Mandatory = $false)]
    [string]$thresholdValue = "",

    [Parameter(Mandatory = $false)]
    [string]$correlationId = ""
)

# Global configuration
$ErrorActionPreference = "Stop"
$slackWebhookUrl = "https://hooks.slack.com/services/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"

#region Enhanced Helper Functions

function Get-TriggerContext {
    <#
    .SYNOPSIS
    Gathers comprehensive trigger context information
    #>
    
    $context = @{
        TriggerSource = $triggerSource
        AlertRuleName = $alertRuleName
        AlertResourceId = $alertResourceId
        AutomationJobId = if ([string]::IsNullOrEmpty($automationJobId)) { $env:AZURE_AUTOMATION_JobId } else { $automationJobId }
        AutomationAccountName = if ([string]::IsNullOrEmpty($automationAccountName)) { $env:AZURE_AUTOMATION_AccountName } else { $automationAccountName }
        RunbookName = if ([string]::IsNullOrEmpty($runbookName)) { $env:AZURE_AUTOMATION_RunbookName } else { $runbookName }
        TriggeredBy = $triggeredBy
        OriginalMetricValue = $originalMetricValue
        ThresholdValue = $thresholdValue
        CorrelationId = if ([string]::IsNullOrEmpty($correlationId)) { [System.Guid]::NewGuid().ToString() } else { $correlationId }
        ExecutionStartTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss UTC")
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        AzureContext = ""
    }
    
    # Try to get Azure context
    try {
        $azContext = Get-AzContext
        if ($azContext) {
            $context.AzureContext = "$($azContext.Account.Id) - $($azContext.Subscription.Name)"
        }
    }
    catch {
        $context.AzureContext = "Not available"
    }
    
    return $context
}

function Format-TriggerDetails {
    <#
    .SYNOPSIS
    Formats trigger context into readable Slack message section
    #>
    param(
        [hashtable]$TriggerContext
    )
    
    $triggerSection = @"

*🔄 TRIGGER CONTEXT*
*Source:* $($TriggerContext.TriggerSource)
*Execution ID:* $($TriggerContext.CorrelationId)
*Started:* $($TriggerContext.ExecutionStartTime)
"@

    if (![string]::IsNullOrEmpty($TriggerContext.AlertRuleName)) {
        $triggerSection += @"

*📊 ALERT DETAILS*
*Alert Rule:* $($TriggerContext.AlertRuleName)
*Resource:* $($TriggerContext.AlertResourceId)
*Metric Value:* $($TriggerContext.OriginalMetricValue)
*Threshold:* $($TriggerContext.ThresholdValue)
"@
    }

    if (![string]::IsNullOrEmpty($TriggerContext.AutomationJobId)) {
        $triggerSection += @"

*🤖 AUTOMATION DETAILS*
*Job ID:* $($TriggerContext.AutomationJobId)
*Account:* $($TriggerContext.AutomationAccountName)
*Runbook:* $($TriggerContext.RunbookName)
*Triggered By:* $($TriggerContext.TriggeredBy)
"@
    }

    $triggerSection += @"

*☁️ EXECUTION CONTEXT*
*Azure Account:* $($TriggerContext.AzureContext)
*PowerShell:* $($TriggerContext.PowerShellVersion)
"@

    return $triggerSection
}

function Send-EnhancedSlackNotification {
    <#
    .SYNOPSIS
    Enhanced Slack notification with trigger context
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$TriggerContext,
        
        [Parameter(Mandatory = $false)]
        [string]$MessageType = "INFO",  # INFO, WARNING, ERROR, SUCCESS
        
        [Parameter(Mandatory = $false)]
        [string]$WebhookUrl = $slackWebhookUrl
    )
    
    # Add emoji based on message type
    $emoji = switch ($MessageType) {
        "INFO" { "ℹ️" }
        "WARNING" { "⚠️" }
        "ERROR" { "❌" }
        "SUCCESS" { "✅" }
        default { "📝" }
    }
    
    # Combine message with trigger context
    $triggerDetails = Format-TriggerDetails -TriggerContext $TriggerContext
    $fullMessage = "$emoji $Message$triggerDetails"
    
    try {
        $jsonPayload = @{ 
            "text" = $fullMessage
            "username" = "Azure SQL Scaler"
        } | ConvertTo-Json -Depth 3
        
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $jsonPayload -ContentType "application/json" -ErrorAction Stop
        Write-Verbose "Enhanced Slack notification sent successfully"
    }
    catch {
        Write-Warning "Failed to send Slack notification: $($_.Exception.Message)"
    }
}

function Send-ExecutionSummary {
    <#
    .SYNOPSIS
    Sends comprehensive execution summary
    #>
    param(
        [hashtable]$TriggerContext,
        [hashtable]$ExecutionResults
    )
    
    $summaryMessage = @"
*📋 EXECUTION SUMMARY*

*Operation:* Azure SQL Database Scaling
*Direction:* $direction ($numCores cores)
*Database:* $databaseName
*Server:* $databaseServer
*Resource Group:* $databaseResourceGroup

*📊 RESULTS*
*Status:* $($ExecutionResults.Status)
*Databases Processed:* $($ExecutionResults.DatabasesProcessed)
*Replicas Processed:* $($ExecutionResults.ReplicasProcessed)
*Total Duration:* $($ExecutionResults.Duration)
*Final Core Count:* $($ExecutionResults.FinalCoreCount)
"@

    if ($ExecutionResults.Errors.Count -gt 0) {
        $summaryMessage += @"

*⚠️ ERRORS ENCOUNTERED*
$($ExecutionResults.Errors -join "`n")
"@
    }

    Send-EnhancedSlackNotification -Message $summaryMessage -TriggerContext $TriggerContext -MessageType $ExecutionResults.Status
}

#endregion

#region Enhanced Main Functions

function Scale-Database {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DbName,
        
        [Parameter(Mandatory = $true)]
        [string]$DbServer,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,

        [Parameter(Mandatory = $true)]
        [hashtable]$TriggerContext
    )

    try {
        Write-Output "Starting scaling process for database: $DbName on server: $DbServer"

        # Get current database configuration
        $database = Get-AzSqlDatabase -ServerName $DbServer -DatabaseName $DbName -ResourceGroupName $ResourceGroup -ErrorAction Stop
        
        $currentCoreCount = $database.Capacity
        $skuName = $database.SkuName
        $resourceId = $database.ResourceId
        
        Write-Output "Current database specs - Cores: $currentCoreCount, SKU: $skuName"

        # Check minimum core requirement
        if (-not (Test-MinimumCoreRequirement -CurrentCores $currentCoreCount -DbName $DbName -TriggerContext $TriggerContext)) {
            return $false
        }

        # Validate SKU
        if ($skuName -ne "GP_Gen5") {
            $errorMessage = @"
*❌ SCALING FAILED - INCOMPATIBLE SKU*

*Database:* $DbName
*Current SKU:* $skuName
*Required SKU:* GP_Gen5
*Action Required:* Change service tier to General Purpose
"@
            Send-EnhancedSlackNotification -Message $errorMessage -TriggerContext $TriggerContext -MessageType "ERROR"
            throw "Cannot proceed with scaling as SKU is $skuName instead of GP_Gen5"
        }

        # Calculate target cores
        $targetCoreCount = [Math]::Max($currentCoreCount - $numCores, $minCores)
        $actualReduction = $currentCoreCount - $targetCoreCount

        # Send pre-scaling notification
        $preScalingMessage = @"
*🔽 STARTING DATABASE SCALING*

*Database:* $DbName ($DbServer)
*Current Cores:* $currentCoreCount
*Target Cores:* $targetCoreCount
*Reduction:* $actualReduction cores
*Resource ID:* $resourceId
"@
        Send-EnhancedSlackNotification -Message $preScalingMessage -TriggerContext $TriggerContext -MessageType "INFO"

        # Perform scaling
        Write-Output "Executing scaling: $currentCoreCount → $targetCoreCount cores"
        Set-AzSqlDatabase -ResourceGroupName $ResourceGroup -ServerName $DbServer -DatabaseName $DbName -VCore $targetCoreCount -ErrorAction Stop
        
        # Wait and verify
        Write-Output "Waiting for scaling completion..."
        Start-Sleep -Seconds 120
        
        $updatedDatabase = Get-AzSqlDatabase -ServerName $DbServer -DatabaseName $DbName -ResourceGroupName $ResourceGroup -ErrorAction Stop

        if ($updatedDatabase.Capacity -eq $targetCoreCount) {
            $successMessage = @"
*✅ SCALING COMPLETED SUCCESSFULLY*

*Database:* $DbName ($DbServer)
*Previous Cores:* $currentCoreCount
*New Cores:* $($updatedDatabase.Capacity)
*Service Objective:* $($updatedDatabase.CurrentServiceObjectiveName)
*License Type:* $($updatedDatabase.LicenseType)
"@
            Send-EnhancedSlackNotification -Message $successMessage -TriggerContext $TriggerContext -MessageType "SUCCESS"
            return $true
        }
        else {
            throw "Scaling verification failed. Expected: $targetCoreCount, Actual: $($updatedDatabase.Capacity)"
        }
    }
    catch {
        $errorMessage = @"
*❌ DATABASE SCALING FAILED*

*Database:* $DbName
*Server:* $DbServer
*Error:* $($_.Exception.Message)
*Action:* Manual intervention required
"@
        Send-EnhancedSlackNotification -Message $errorMessage -TriggerContext $TriggerContext -MessageType "ERROR"
        throw
    }
}

function Test-MinimumCoreRequirement {
    param(
        [int]$CurrentCores,
        [string]$DbName,
        [hashtable]$TriggerContext
    )
    
    Write-Output "Validating minimum core requirement - Current: $CurrentCores, Minimum: $minCores"
    
    if ($CurrentCores -le $minCores) {
        $minimumCoreMessage = @"
*⏹️ SCALING SKIPPED - AT MINIMUM CORES*

*Database:* $DbName
*Current Cores:* $CurrentCores
*Minimum Allowed:* $minCores
*Requested Reduction:* $numCores cores
*Result:* No action taken
"@
        Send-EnhancedSlackNotification -Message $minimumCoreMessage -TriggerContext $TriggerContext -MessageType "WARNING"
        return $false
    }
    return $true
}

#endregion

#region Enhanced Main Execution

try {
    # Initialize execution context
    $executionStartTime = Get-Date
    $triggerContext = Get-TriggerContext
    $executionResults = @{
        Status = "UNKNOWN"
        DatabasesProcessed = 0
        ReplicasProcessed = 0
        Duration = ""
        FinalCoreCount = 0
        Errors = @()
    }

    # Send initial execution notification
    $startMessage = @"
*🚀 AZURE SQL SCALING INITIATED*

*Operation:* Scale $direction by $numCores cores
*Database:* $databaseName
*Server:* $databaseServer
*Resource Group:* $databaseResourceGroup
*Min/Max Cores:* $minCores / $maxCores
"@
    Send-EnhancedSlackNotification -Message $startMessage -TriggerContext $triggerContext -MessageType "INFO"

    Write-Output "Starting Azure SQL Database scaling with enhanced tracking"
    
    # Connect to Azure
    Write-Output "Connecting to Azure..."
    Connect-AzAccount -Identity -ErrorAction Stop
    Set-AzContext -SubscriptionId $subscription -ErrorAction Stop

    # Pre-validation
    $primaryDatabase = Get-AzSqlDatabase -ServerName $databaseServer -DatabaseName $databaseName -ResourceGroupName $databaseResourceGroup -ErrorAction Stop
    
    if (-not (Test-MinimumCoreRequirement -CurrentCores $primaryDatabase.Capacity -DbName $databaseName -TriggerContext $triggerContext)) {
        if ($replicas) {
            $allAtMinimum = $true
            foreach ($replica in $replicas) {
                $replicaDatabase = Get-AzSqlDatabase -ServerName $replica -DatabaseName $databaseName -ResourceGroupName $databaseResourceGroup -ErrorAction Stop
                if ($replicaDatabase.Capacity -gt $minCores) {
                    $allAtMinimum = $false
                    break
                }
            }
            if ($allAtMinimum) {
                $executionResults.Status = "SKIPPED"
                Send-ExecutionSummary -TriggerContext $triggerContext -ExecutionResults $executionResults
                exit 0
            }
        }
        else {
            $executionResults.Status = "SKIPPED"
            Send-ExecutionSummary -TriggerContext $triggerContext -ExecutionResults $executionResults
            exit 0
        }
    }

    # Execute scaling
    if (-not $replicas) {
        Write-Output "Scaling single database"
        $success = Scale-Database -DbName $databaseName -DbServer $databaseServer -ResourceGroup $databaseResourceGroup -TriggerContext $triggerContext
        if ($success) { $executionResults.DatabasesProcessed = 1 }
    }
    else {
        Write-Output "Scaling database with replicas"
        
        # Scale replicas first
        foreach ($replica in $replicas) {
            try {
                $success = Scale-Database -DbName $databaseName -DbServer $replica -ResourceGroup $databaseResourceGroup -TriggerContext $triggerContext
                if ($success) { $executionResults.ReplicasProcessed++ }
            }
            catch {
                $executionResults.Errors += "Replica $replica failed: $($_.Exception.Message)"
                Write-Warning "Failed to scale replica on $replica"
            }
        }
        
        # Scale primary
        try {
            $success = Scale-Database -DbName $databaseName -DbServer $databaseServer -ResourceGroup $databaseResourceGroup -TriggerContext $triggerContext
            if ($success) { $executionResults.DatabasesProcessed = 1 }
        }
        catch {
            $executionResults.Errors += "Primary database failed: $($_.Exception.Message)"
            throw
        }
    }

    # Final status
    $finalDatabase = Get-AzSqlDatabase -ServerName $databaseServer -DatabaseName $databaseName -ResourceGroupName $databaseResourceGroup -ErrorAction Stop
    $executionResults.FinalCoreCount = $finalDatabase.Capacity
    $executionResults.Duration = "{0:mm} minutes {0:ss} seconds" -f ((Get-Date) - $executionStartTime)
    $executionResults.Status = if ($executionResults.Errors.Count -eq 0) { "SUCCESS" } else { "PARTIAL_SUCCESS" }

    Send-ExecutionSummary -TriggerContext $triggerContext -ExecutionResults $executionResults
    Write-Output "All scaling operations completed"
}
catch {
    $executionResults.Status = "FAILED"
    $executionResults.Errors += $_.Exception.Message
    $executionResults.Duration = "{0:mm} minutes {0:ss} seconds" -f ((Get-Date) - $executionStartTime)
    
    $criticalErrorMessage = @"
*🚨 CRITICAL: SCALING SCRIPT FAILED*

*Database:* $databaseName
*Server:* $databaseServer
*Error:* $($_.Exception.Message)
*Immediate Action Required*
"@
    Send-EnhancedSlackNotification -Message $criticalErrorMessage -TriggerContext $triggerContext -MessageType "ERROR"
    Send-ExecutionSummary -TriggerContext $triggerContext -ExecutionResults $executionResults
    
    exit 1
}

#endregion
