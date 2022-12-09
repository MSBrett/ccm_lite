param(
    [string]$EnrollmentId = '123456',
    [string]$Subscription = "Non-Prod-Workloads",
    [string]$Location = "westus",
    [string]$Suffix = $null,
    [string]$Prefix = "ccm",
    [string]$ResourceGroupName = ("{0}-pipeline-{1}" -f $prefix, $EnrollmentId),
    [datetime]$StartDate = "2020-01-01",
    [datetime]$EndDate = "2022-11-30",
    [bool]$History = $false,
    [bool]$Future = $false,
    [bool]$DeployPipeline = $false,
    [int]$TimeOutMinutes = 15
)
$ErrorActionPreference = "Stop"

# MAIN #
$azAccount = set-azcontext -Subscription $Subscription
if ([string]::IsNullOrEmpty($Suffix)) { 
    $Suffix = $EnrollmentId
}

$Suffix = $Suffix.ToLowerInvariant()
$Prefix = $Prefix.ToLowerInvariant()

[string]$StorageAccountName = ("{0}sa{1}" -f $Prefix, $Suffix)
[string]$ContainerName = ("{0}{1}" -f $Prefix, $Suffix)
[string]$scope = "providers/Microsoft.Billing/billingAccounts/{0}" -f $EnrollmentId
[string]$exportFolderName = ("ccmexports/{0}" -f $EnrollmentId)
[string]$deploymentName = ("{0}-PIPELINE-{1}" -f $Prefix, $Suffix)
[string]$keyVaultName = ("{0}kv{1}" -f $Prefix, $Suffix)
[string]$dataFactoryName = ("{0}df{1}" -f $Prefix, $Suffix)

 
if ($DeployPipeline) {
    Write-Host ("{0}    {1}" -f (get-date), "Deploy Pileline")
    Write-Host ("{0}    {1}" -f (get-date), "Resource Group")
    $ccmResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if ($null -eq $ccmResourceGroup) {
        $ccmResourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
    }

    Write-Host ("{0}    {1}" -f (get-date), "ARM Template")
    
    $armDeployment = New-AzResourceGroupDeployment -Name $deploymentName `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile .\ARM\azuredeploy.json `
        -BlobContainerName $ContainerName `
        -StorageAccountName $StorageAccountName `
        -KeyvaultName $keyVaultName `
        -DataFactoryName $dataFactoryName
    
    start-sleep -seconds 10
    Write-Host ("{0}    {1}" -f (get-date), "Start Pipeline")
    $triggerResult = Start-AzDataFactoryV2Trigger -ResourceGroupName $ResourceGroupName -DataFactoryName $dataFactoryName -Name "StorageTrigger" -Force
}

if ($History) {
    $ccmStorageAccount = Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $ccmStorageContainer = Get-AzStorageContainer -Name $ContainerName -Context $ccmStorageAccount.Context -ErrorAction SilentlyContinue
    Write-Host ("{0}    {1}" -f (get-date), "Retrieve Historical Data")
    ./PS/Set-Exports.ps1 -Scope $scope -Metric 'actualcost' -StorageAccount $ccmStorageAccount.id -Container $ccmStorageContainer.Name -Folder $exportFolderName -Subscription (get-azcontext).subscription.id -StartExport $true -TimeOutMinutes $TimeOutMinutes -Prefix $Prefix
    ./PS/Set-Exports.ps1 -Scope $scope -Metric 'amortizedcost' -StorageAccount $ccmStorageAccount.id -Container $ccmStorageContainer.Name -Folder $exportFolderName -Subscription (get-azcontext).subscription.id -StartExport $true -TimeOutMinutes $TimeOutMinutes -Prefix $Prefix
    ./PS/Get-History.ps1 -Scope $scope -Metric 'actualcost' -StorageAccount $ccmStorageAccount.id -Container $ccmStorageContainer.Name -Folder $exportFolderName -Subscription (get-azcontext).subscription.id -StartDate $StartDate -EndDate $EndDate -TimeOutMinutes $TimeOutMinutes -Prefix $Prefix
    ./PS/Get-History.ps1 -Scope $scope -Metric 'amortizedcost' -StorageAccount $ccmStorageAccount.id -Container $ccmStorageContainer.Name -Folder $exportFolderName -Subscription (get-azcontext).subscription.id -StartDate $StartDate -EndDate $EndDate -TimeOutMinutes $TimeOutMinutes -Prefix $Prefix
}

if ($Future) {
    $ccmStorageAccount = Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $ccmStorageContainer = Get-AzStorageContainer -Name $ContainerName -Context $ccmStorageAccount.Context -ErrorAction SilentlyContinue
    Write-Host ("{0}    {1}" -f (get-date), "Set Recurring Exports")
    ./PS/Set-Exports.ps1 -Scope $scope -Metric 'actualcost' -StorageAccount $ccmStorageAccount.id -Container $ccmStorageContainer.Name -Folder $exportFolderName -Subscription (get-azcontext).subscription.id -StartExport $false -Prefix $Prefix
    ./PS/Set-Exports.ps1 -Scope $scope -Metric 'amortizedcost' -StorageAccount $ccmStorageAccount.id -Container $ccmStorageContainer.Name -Folder $exportFolderName -Subscription (get-azcontext).subscription.id -StartExport $false -Prefix $Prefix
}