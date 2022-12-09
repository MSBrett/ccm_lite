param (
  [string]$Scope,
  [string]$Metric,
  [string]$Subscription,
  [string]$StorageAccount,
  [string]$Container,
  [string]$Folder,
  [bool]$StartExport = $false,
  [int]$TimeOutMinutes = 30,
  [int]$SleepInterval = 10,
  [string]$Prefix = "ccm"
)

function Write-DebugInfo {
  param (
    $DebugParams
  )

  Write-Host ("{0}    {1}    {2}" -f (Get-Date), $DebugParams.Name, $DebugParams.DefinitionTimeframe)
}

function Set-CostManagementApi {
  param (
    $ApiParams
  )

  $uri = "https://management.azure.com/{0}/providers/Microsoft.CostManagement/exports/{1}?api-version=2021-10-01" -f $ApiParams.Scope, $ApiParams.Name
  Remove-AzCostManagementExport -Name $ApiParams.Name -Scope $ApiParams.Scope -ErrorAction SilentlyContinue
  $payload = '{
    "properties": {
      "schedule": {
        "status": "Active",
        "recurrence": "{7}",
        "recurrencePeriod": {
          "from": "{6}",
          "to": "2099-10-31T00:00:00Z"
        }
      },
      "partitionData": "{5}",
      "format": "Csv",
      "deliveryInfo": {
        "destination": {
          "resourceId": "{0}",
          "container": "{1}",
          "rootFolderPath": "{2}"
        }
      },
      "definition": {
        "type": "{3}",
        "timeframe": "{4}",
        "dataSet": {
          "granularity": "Daily"
        }
      }
    }
  }' 
  
  $payload = $payload.Replace("{0}", $ApiParams.DestinationResourceId)
  $payload = $payload.Replace("{1}", $ApiParams.DestinationContainer)
  $payload = $payload.Replace("{2}", $ApiParams.DestinationRootFolderPath)
  $payload = $payload.Replace("{3}", $ApiParams.DefinitionType)
  $payload = $payload.Replace("{4}", $ApiParams.DefinitionTimeframe)
  $payload = $payload.Replace("{5}", $ApiParams.PartitionData)
  $payload = $payload.Replace("{6}", $ApiParams.RecurrencePeriodFrom)
  $payload = $payload.Replace("{7}", $ApiParams.ScheduleRecurrence)
  $apiResult = Invoke-AzRestMethod -Uri $uri -Method PUT -Payload $payload
  if ($apiResult.StatusCode -ne "201") {
    $apiResult
    Throw "Cost Management API call failed"
  }
}

function Set-CostManagementExport {
  param (
    $ExportParams,
    [bool]$Start = $false
  )

  Write-DebugInfo $ExportParams
  Set-CostManagementApi -ApiParams $ExportParams
  if ($Start) {
    Start-Sleep -Seconds $SleepInterval
    Invoke-AzCostManagementExecuteExport -ExportName $ExportParams.Name -Scope $ExportParams.Scope
    Start-Sleep -Seconds $SleepInterval
    $currentStatus = $null
    $currentStatus = (Get-AzCostManagementExport -Name $ExportParams.Name -Scope $ExportParams.Scope -Expand runHistory).RunHistory.Value[0].Status
    [int]$loop = 0
    while ($currentStatus -eq "InProgress") {
      if ($loop -ge $TimeOutMinutes) {
        $currentStatus = "TimedOut"
      }
      else {
        Start-Sleep -Seconds 60
        $loop++
        $currentStatus = (Get-AzCostManagementExport -Name $ExportParams.Name -Scope $ExportParams.Scope -Expand runHistory).RunHistory.Value[0].Status
        Write-Host ("{0}    {1}    {2}" -f (get-date), $ExportParams.Name, $currentStatus)
      }
    }

    Write-Host ("{0}    {1}    {2}" -f (get-date), $ExportParams.Name, $currentStatus)
  }
}

$today = Get-Date
$nextMonth = $today.AddDays(-$today.Day + 5).AddMonths(1)
[string]$dateFrom = "{0}-{1}-{2}T10:00:00Z" -f $nextMonth.Year, $nextMonth.Month, $nextMonth.Day

# Last Billing Month
$Params = @{
  Name                      = ("{0}_closed_{1}" -f $Prefix, $Metric)
  DefinitionType            = $Metric
  DataSetGranularity        = 'Daily'
  Scope                     = $Scope
  DestinationResourceId     = $StorageAccount
  DestinationContainer      = $Container
  DefinitionTimeframe       = 'TheLastBillingMonth'
  ScheduleRecurrence        = 'Monthly'
  RecurrencePeriodFrom      = $dateFrom
  RecurrencePeriodTo        = "2099-12-31T00:00:00Z"
  ScheduleStatus            = 'Active'
  DestinationRootFolderPath = $Folder
  Format                    = 'Csv'
  PartitionData             = $true
}

Set-CostManagementExport -ExportParams $Params -Start $StartExport

# Billing Month To Date
$tomorrow = (Get-Date).AddDays(1)
[string]$dateFrom = "{0}-{1}-{2}T10:00:00Z" -f $tomorrow.Year, $tomorrow.Month, $tomorrow.Day
$Params = @{
  Name                      = ("{0}_open_{1}" -f $Prefix, $Metric)
  DefinitionType            = $Metric
  DataSetGranularity        = 'Daily'
  Scope                     = $Scope
  DestinationResourceId     = $StorageAccount
  DestinationContainer      = $Container
  DefinitionTimeframe       = 'BillingMonthToDate'
  ScheduleRecurrence        = 'Daily'
  RecurrencePeriodFrom      = $dateFrom
  RecurrencePeriodTo        = "2099-12-31T00:00:00Z"
  ScheduleStatus            = 'Active'
  DestinationRootFolderPath = $Folder
  Format                    = 'Csv'
  PartitionData             = $true
}

Set-CostManagementExport -ExportParams $Params -Start $StartExport