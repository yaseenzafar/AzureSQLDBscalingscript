# Azure SQL Database Auto-Scaler

This repository contains two PowerShell scripts designed for **automatic scaling of Azure SQL Databases** using **Azure Automation Runbooks** and **Action Groups**. The goal is to **optimize cloud cost** by automatically scaling database cores up or down based on CPU usage metrics.

---

## 🔍 Purpose

Managing performance and cost in cloud-based environments is crucial. This solution enables:

- **Automatic scale-up** during peak usage hours
- **Automatic scale-down** during off-peak hours or underutilization
- **Cost optimization** by right-sizing compute resources
- **Slack notifications** for visibility and auditing
- **Enhanced traceability** when run via alerts, schedules, or manually

---

## 📁 Scripts Overview

| Script Name             | Description |
|------------------------|-------------|
| `scaleup.ps1`          | Scales up the Azure SQL database VCore count by a specified amount, within allowed hours. Includes replica handling and Slack alerts. |
| `scaledown.ps1`        | Scales down the VCore count with full execution traceability, enriched context about the trigger (manual, alert, webhook), and robust Slack notifications. |

---

## ⚙️ Integration with Azure Automation

Both scripts are designed to run as **Azure Automation Runbooks** using a system-assigned managed identity for secure, passwordless authentication.

### ✅ Prerequisites

- An [Azure Automation Account](https://learn.microsoft.com/en-us/azure/automation/automation-create-standalone-account)
- Managed Identity enabled for the Automation Account
- Access granted to the target SQL resources
- Slack Incoming Webhook URL (optional but recommended)
- Alert Rules configured for CPU percentage

### 🔄 Example Use Cases

| Scenario | Setup |
|----------|-------|
| High CPU Usage (>90%) | Alert triggers `scaleup.ps1` via Action Group |
| Low CPU Usage (<30%) | Alert triggers `scaledown.ps1` via Action Group |
| Scheduled Off-Peak Hours | Time-based trigger invokes `scaledown.ps1` |
| Manual Trigger | DevOps engineer executes Runbook with parameters |

---

## 📝 Parameters (Common)

| Parameter Name       | Description |
|----------------------|-------------|
| `databaseName`       | Name of the Azure SQL database |
| `databaseServer`     | Name of the SQL server |
| `databaseResourceGroup` | Resource group of the database |
| `subscription`       | Azure subscription ID |
| `maxCores`           | Maximum allowed vCores |
| `minCores`           | Minimum allowed vCores |
| `numCores`           | Number of cores to scale up/down |
| `direction`          | `up` or `down` |
| `replicas` (optional) | List of replica server names |
| `slackWebhookUrl` (optional) | Slack webhook for notifications |
| `allowedHours` (scaleup only) | Time window in hours to allow scaling |

---

## 📢 Slack Notification Format

Slack messages sent by these scripts include:

- Operation status (Started / Success / Failed / Skipped)
- Resource name and type
- Core counts (before/after)
- Trigger context (who/what initiated it)
- Error messages (if any)

---

## 📌 Recommendations

- Set `scaleup.ps1` to only be triggerable within peak working hours.
- Set `scaledown.ps1` to run off-hours or based on low-CPU alerts.
- Use action groups with metric alerts on `cpu_percent` of the database.
- Keep scaling increments (`numCores`) moderate to avoid cost spikes.

---

## 🔐 Security & Access

These scripts are designed to use **Managed Identity** to access Azure resources. Ensure:

- The Automation Account's identity has the following roles:
  - `SQL DB Contributor` on target SQL Server
  - `Reader` on the Subscription (optional)

---

## 📄 License

MIT License

---

## 🤝 Contributions

Feel free to fork, submit issues, or raise pull requests for improvement.

---

## 📬 Contact

For questions, please contact me on [y.zafar.0504@gmail.com]
