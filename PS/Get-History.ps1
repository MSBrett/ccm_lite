param (
  [string]$Scope,
  [string]$Metric,
  [string]$Subscription,
  [string]$StorageAccount,
  [string]$Container,
  [string]$Folder,
  [datetime]$StartDate,
  [datetime]$EndDate,
  [int]$TimeOutMinutes = 30,
  [int]$SleepInterval = 10,
  [string]$Prefix = "ccm"
)

function Write-DebugInfo {
  param (
    $DebugParams
  )

  Write-Host ("{0}    {1}    {2}" -f (Get-Date), $DebugParams.Name, $DebugParams.TimePeriodFrom)
}

function Set-CostManagementApi {
  param (
    $ApiParams
  )

  $uri = "https://management.azure.com/{0}/providers/Microsoft.CostManagement/exports/{1}?api-version=2021-10-01" -f $ApiParams.Scope, $ApiParams.Name
  Remove-AzCostManagementExport -Name $ApiParams.Name -Scope $ApiParams.Scope -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 10
  $payload = '{
    "properties": {
      "schedule": {
        "status": "Inactive",
        "recurrence": "daily",
        "recurrencePeriod": {
          "from": "2099-06-01T00:00:00Z",
          "to": "2099-10-31T00:00:00Z"
        }
      },
      "partitionData": "true",
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
        "timeframe": "Custom",
        "timePeriod" : {
          "from" : "{4}",
          "to" : "{5}"
        },
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
  $payload = $payload.Replace("{4}", $ApiParams.TimePeriodFrom)
  $payload = $payload.Replace("{5}", $ApiParams.TimePeriodTo)
  $payload = $payload.Replace("{6}", $ApiParams.PartitionData)
  
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
    [string]$currentStatus = "Queued"
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

# Historical pull
[string]$dateFrom = "{0}-{1}-{2}T00:00:00Z" -f $StartDate.Year, $StartDate.Month, $StartDate.Day
[string]$dateTo = "{0}-{1}-{2}T23:59:59Z" -f $EndDate.Year, $EndDate.Month, $EndDate.Day
[datetime]$currentDate = $StartDate
while ($currentDate -le $EndDate) {
  [datetime]$nextDate = $currentDate.AddDays(-$currentDate.Day + 1).AddMonths(1).AddDays(-1)
  [string]$dateFrom = "{0}-{1}-{2}T00:00:00Z" -f $currentDate.Year, $currentDate.Month, $currentDate.Day
  [string]$dateTo = "{0}-{1}-{2}T23:59:59Z" -f $nextDate.Year, $nextDate.Month, $nextDate.Day

  $Params = @{
    Name                      = ("{0}_custom_{1}" -f $Prefix, $Metric)
    DefinitionType            = $Metric
    DataSetGranularity        = 'Daily'
    Scope                     = $Scope
    DestinationResourceId     = $StorageAccount
    DestinationContainer      = $Container
    DefinitionTimeframe       = 'Custom'
    ScheduleRecurrence        = 'Daily'
    TimePeriodFrom            = $dateFrom
    TimePeriodTo              = $dateTo
    RecurrencePeriodFrom      = "2099-12-31T00:00:00Z"
    RecurrencePeriodTo        = "2099-12-31T00:00:00Z"
    ScheduleStatus            = 'Inactive'
    DestinationRootFolderPath = $Folder
    Format                    = 'Csv'
    PartitionData             = $true
  }

  Set-CostManagementExport -ExportParams $Params -Start $true
  $currentDate = $currentDate.AddDays(-$currentDate.Day + 1).AddMonths(1)
}