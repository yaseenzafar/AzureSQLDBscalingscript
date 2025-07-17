# Azure SQL AutoScaler

## 🚀 Overview

This repository contains PowerShell automation scripts to **dynamically scale Azure SQL Database vCores** up or down based on CPU utilization and performance thresholds. The primary objective is to **reduce Azure cloud costs** during low-usage periods and **ensure performance** during high-demand scenarios.

These scripts are designed to be executed via **Azure Automation Runbooks** and integrated with **Azure Monitor Alerts**, supporting:

- Automatic **scale-up** on high CPU usage.
- Scheduled or triggered **scale-down** when demand is low.
- **Slack notifications** for full visibility of all scaling operations.
- Support for **primary** and **replica** databases.
- Full **trigger context tracking** for audit purposes.

---

## 📂 Files Included

| Script | Purpose |
|--------|---------|
| `scaleup.ps1` | Scales up Azure SQL database cores based on alerts and time-window restrictions. |
| `scaledown.ps1` | Scales down Azure SQL database cores with detailed trigger tracking and context. |

---

## 💡 Features

- 📉 **Cost Optimization**: Reduce cores during low usage windows.
- 📈 **Performance Scaling**: Automatically increase capacity when CPU usage spikes.
- ⏰ **Time-based Guardrails**: Restrict scale-up operations to allowed hours only.
- 📡 **Slack Integration**: Notifications sent for start, success, failure, and warnings.
- 🔍 **Audit Trail**: All executions are traceable with execution IDs and metadata.
- ♻️ **Replica Awareness**: Scales replicas first, then the primary.

---

## 📦 Prerequisites

- Azure Automation Account with **System-Assigned Managed Identity**.
- PowerShell environment with:
  - `Az.Accounts`
  - `Az.Sql`
- Azure SQL Database(s) on **GP_Gen5 SKU**.
- Slack Webhook (optional, for notifications).

---

## 🛠️ Usage

### 1. Setup Automation

Import the scripts into **Azure Automation Runbooks**.

### 2. Parameters (Common)

| Parameter | Description |
|----------|-------------|
| `databaseName` | Name of the SQL database |
| `databaseServer` | Azure SQL Server name |
| `databaseResourceGroup` | Resource group of the SQL Server |
| `subscription` | Azure subscription ID |
| `numCores` | Number of cores to scale by |
| `maxCores` | Maximum allowed cores |
| `minCores` | Minimum allowed cores |
| `replicas` | (Optional) List of replica server names |

### 3. Triggering

You can execute the scripts via:
- **Azure Alerts (via Webhook or Action Group)**
- **Scheduled Jobs**
- **Manual Runbook Execution**

---

## 📘 Examples

**Scale Up by 2 vCores**
```powershell
.\scaleup.ps1 `
  -databaseName "mydb" `
  -databaseServer "sql-prod-server" `
  -databaseResourceGroup "prod-rg" `
  -subscription "xxxxx-xxxx-xxxx" `
  -numCores 2 `
  -maxCores 16 `
  -minCores 4 `
  -direction "up"
