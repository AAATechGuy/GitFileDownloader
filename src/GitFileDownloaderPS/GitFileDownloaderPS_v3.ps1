
function __logger_DownloadGitFiles ([string]$Message, [bool]$EnableVerboseLogging = $true) { if($EnableVerboseLogging) { Write-Host "DownloadGitFiles : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') : $Message"; } }

function Import-GitFiles
(
    ### Repository URL. e.g., https://dev.azure.com/<organization>/project>/_apis/git/repositories/<repository>
    [Parameter(Mandatory = $true)][string]$RepoUrl,                  
    ### PersonalAccessToken that has access to read files in the repository. 
    [Parameter(Mandatory = $true)][string]$RepoPersonalAccessToken,                      
    ### Version of repository to download files. E.g., 'main' branch
    [Parameter(Mandatory = $true)][string]$RepoVersion,                             
    ### VersionType of the Version string. Options are: branch/commit/tag. See here: https://docs.microsoft.com/en-us/rest/api/azure/devops/git/items/get-items-batch?view=azure-devops-rest-6.0#gitversiontype
    [Parameter(Mandatory = $true)][string]$RepoVersionType,                         
    ### Directory to download the files to. 
    [Parameter(Mandatory = $true)][string]$DownloadDir,                         
    ### Folders to include for download. E.g., @('subFolder1','/subFolder20/subFolder23')
    [Parameter(Mandatory = $false)][string[]]$IncludePathFilter = @('/'),       
    ### Maximum threads to enable parallel downloads. Only available for PS7.0+
    [Parameter(Mandatory = $false)][int]$DownloadThrottleLimit=1,               
    ### Retry count when calling REST API. Only available for PS7.0+
    [Parameter(Mandatory = $false)][int]$MaximumRetryCount=1,                   
    ### Retry interval in seconds when calling REST API. Only available for PS7.0+
    [Parameter(Mandatory = $false)][int]$RetryIntervalSec=0,                    
    ### Timeout in seconds when calling each REST API.
    [Parameter(Mandatory = $false)][int]$TimeoutSec = 30,                       
    ### Folders to exclude from download. E.g., @('*/folder1/*','*file1.ext')
    [Parameter(Mandatory = $false)][string[]]$ExcludePathFilter = $null,        
    ### If true, emits best-effort progress indicator used in Azure Pipelines via API at https://docs.microsoft.com/en-us/azure/devops/pipelines/scripts/logging-commands?view=azure-devops&tabs=bash#setprogress-show-percentage-completed
    [Parameter(Mandatory = $false)][bool]$EnableDevOpsProgressUpdate = $false,
    ### If true, logs verbose logs
    [Parameter(Mandatory = $false)][bool]$EnableVerboseLogging = $true
)
{
<#
.SYNOPSIS
Downloads files from Azure Git respository. 
.DESCRIPTION
Downloads files from Azure Git respository. 
.LINK
https://github.com/AAATechGuy/GitFileDownloader 
.EXAMPLE
PS> Import-GitFiles -RepoUrl 'https://dev.azure.com/<organization>/project>/_apis/git/repositories/<repository>' -RepoPersonalAccessToken $confidentialPAT -RepoVersion 'master' -RepoVersionType 'branch' -DownloadDir 'D:\tmp\srcX' -IncludePathFilter @('folder1','/folder20/folder21') -DownloadThrottleLimit 40 -MaximumRetryCount 3 -RetryIntervalSec 1 -TimeoutSec 10 -ExcludePathFilter @('*/folder3/*','*file4.bat') -EnableDevOpsProgressUpdate $true
#>
    $PSBoundParameters.Keys | where { $_ -ne 'RepoPersonalAccessToken' } | foreach { __logger_DownloadGitFiles "parameter: $_ = $($PSBoundParameters[$_])" $EnableVerboseLogging }; # display parameters

    $AzureDevOpsRepoUrl = $RepoUrl;
    $AzureDevOpsPAT = $RepoPersonalAccessToken;
    $Version = $RepoVersion;
    $VersionType = $RepoVersionType;

    $psVersion = (get-host).Version.Major;
    __logger_DownloadGitFiles "executing on powershellVersion: $psVersion" $EnableVerboseLogging;
    if($psVersion -lt 7) {
        __logger_DownloadGitFiles "WARNING: parameters DownloadThrottleLimit/MaximumRetryCount/RetryIntervalSec - only supported for PS version 7+" $EnableVerboseLogging;
    }

    # validate parameters
    if(!$AzureDevOpsRepoUrl) {
        throw 'invalid parameter AzureDevOpsRepoUrl';
    }
    if(!$AzureDevOpsPAT) {
        throw 'invalid parameter AzureDevOpsPAT';
    }
    if(!$Version) {
        throw 'invalid parameter Version';
    }
    if(!$VersionType) {
        throw 'invalid parameter VersionType';
    }
    if(!$DownloadDir) {
        throw 'invalid parameter DownloadDir';
    }
    if(!$IncludePathFilter) {
        throw 'invalid parameter IncludePathFilter';
    }
    if(!$DownloadThrottleLimit -or $DownloadThrottleLimit -lt 1) {
        throw 'invalid parameter DownloadThrottleLimit';
    }
    if(!$MaximumRetryCount -or $MaximumRetryCount -lt 0) {
        throw 'invalid parameter MaximumRetryCount';
    }
    if(!$RetryIntervalSec -or $RetryIntervalSec -lt 0) {
        throw 'invalid parameter RetryIntervalSec';
    }
    if(!$TimeoutSec -or $TimeoutSec -lt 1) {
        throw 'invalid parameter TimeoutSec';
    }

    # init
    $startTime = (Get-Date);

    if(!$IncludePathFilter) {
        $IncludePathFilter = @('/');
    }

    $stats = [hashtable]::Synchronized(@{ Downloaded = 0; Failed = 0; Skipped = 0; Folders = 0; });

    # create auth header
    $AzureDevOpsAuthenicationHeader = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$AzureDevOpsPAT")) };
    
    # to list files, see https://docs.microsoft.com/en-us/rest/api/azure/devops/git/items/get%20items%20batch?view=azure-devops-rest-6.0#gititemdescriptor
    $itemDescriptors = @();
    foreach($path in $includePathFilter) {
        $itemDescriptors += 
               @{
                    "path" = $path
                    "version" = $version
                    "versionType" = $versionType
                    "versionOptions" = "none"
                    "recursionLevel" = "full"
                };
    }

    $body = @{
            "itemDescriptors" = $itemDescriptors
            "includeContentMetadata" = "true"
    } | ConvertTo-Json -Depth 3;

    $urlGetFileList = "$AzureDevOpsRepoUrl/itemsbatch?api-version=6.0"; 

    $SavedProgressPreference = $ProgressPreference; 
    $ProgressPreference = 'SilentlyContinue'; 
    try
    {
        if($psVersion -ge 7) {
            $result = Invoke-RestMethod -Uri $urlGetFileList -Method Post -Headers $AzureDevOpsAuthenicationHeader -Body $body -ContentType "application/json" -TimeoutSec $TimeoutSec -MaximumRetryCount $MaximumRetryCount -RetryIntervalSec $RetryIntervalSec; 
        }
        else {
            $result = Invoke-RestMethod -Uri $urlGetFileList -Method Post -Headers $AzureDevOpsAuthenicationHeader -Body $body -ContentType "application/json" -TimeoutSec $TimeoutSec; 
        }
    } finally {
        $ProgressPreference = $SavedProgressPreference;
    }

    $allFiles = $result.value | %{ $_ };
    $allFilesCount = $allFiles.Count;
    __logger_DownloadGitFiles "found $($result.Count) batches and $allFilesCount files" $EnableVerboseLogging;

    if($psVersion -ge 7) {
        # create concurrent queue
        $fileQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new();
        $allFiles | %{ $fileQueue.Enqueue($_); };

        # this is needed because scripts cannot be passed into -Parallel via $using:
        $funcDef__DownloadGitFileFunc = $function:__DownloadGitFileFunc.ToString();

        # start parallel downloads
        1..$DownloadThrottleLimit | ForEach-Object -ThrottleLimit $DownloadThrottleLimit -Parallel {
            # this is needed because scripts cannot be passed into -Parallel via $using:
            $function:__DownloadGitFileFunc = $using:funcDef__DownloadGitFileFunc;
            
            # fetch item from queue
            $downloadItem = '';
            $fileQueue = $using:fileQueue;
            while($fileQueue.TryDequeue([ref]$downloadItem)) {
                __DownloadGitFileFunc $downloadItem $using:downloadDir $using:ExcludePathFilter $using:stats $using:psVersion $using:AzureDevOpsAuthenicationHeader $using:TimeoutSec $using:MaximumRetryCount $using:RetryIntervalSec $using:enableDevOpsProgressUpdate $using:allFilesCount $using:EnableVerboseLogging;
            }
        }
    }
    else {
        $allFiles | ForEach-Object { 
            $downloadItem = $_;
            __DownloadGitFileFunc $downloadItem $downloadDir $ExcludePathFilter $stats $psVersion $AzureDevOpsAuthenicationHeader $TimeoutSec $MaximumRetryCount $RetryIntervalSec $enableDevOpsProgressUpdate $allFilesCount $EnableVerboseLogging;
        }
    }

    if($enableDevOpsProgressUpdate) {
        Write-Host "##vso[task.setprogress value=100;]DownloadGitFiles"
    }

    # update elapsed stat
    $stats['ElapsedSec'] = ((Get-Date) - $startTime).TotalSeconds;

    __logger_DownloadGitFiles 'download stats below (approx)...' $EnableVerboseLogging;
    $stats.Keys | sort | %{ __logger_DownloadGitFiles "$_`t~ $($stats[$_])" $EnableVerboseLogging; };
}

### script to download a git file
function __DownloadGitFileFunc {
    # must ensure no global variables are used
    param($downloadItem, $downloadDir, $ExcludePathFilter, $stats, $psVersion, $AzureDevOpsAuthenicationHeader, $TimeoutSec, $MaximumRetryCount, $RetryIntervalSec, $enableDevOpsProgressUpdate, $allFilesCount, $EnableVerboseLogging);
    
    function __logger_DownloadGitFiles ([string]$Message, [bool]$EnableVerboseLogging = $true) { if($EnableVerboseLogging) { Write-Host "DownloadGitFiles : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') : $Message"; } }

    if(!$downloadItem) {
        throw 'invalid parameters';
    }
    
    $downloadPath = $downloadItem.path;
    $localPath = Join-Path $downloadDir $downloadPath;
    if($downloadItem.isFolder) {
        ### no action for folders; they are auto-created for files
        $stats['Folders']++; ## todo: improve lock, accuracy in multi-threaded scripts
    }
    else {
        # skip specific files
        if($ExcludePathFilter -and ($ExcludePathFilter | where { $downloadPath -like $_ })) {
            __logger_DownloadGitFiles "skip     : $downloadPath" $EnableVerboseLogging;
            $stats['Skipped']++; ## todo: improve lock, accuracy in multi-threaded scripts
            return;
        }
        __logger_DownloadGitFiles "download : $downloadPath" $EnableVerboseLogging;
        $localDir = Split-Path -Parent $localPath;
        New-Item -Path $localDir -ItemType Directory -Force -ErrorAction SilentlyContinue >$null;

        $SavedProgressPreference = $ProgressPreference; 
        $ProgressPreference = 'SilentlyContinue'; 
        try {
            # To download each file, see https://docs.microsoft.com/en-us/rest/api/azure/devops/git/items/get?view=azure-devops-rest-6.0#gitversiontype
            if($psVersion -ge 7) {
                Invoke-RestMethod -Uri $downloadItem.url -Method Get -Headers $AzureDevOpsAuthenicationHeader -OutFile $localPath -TimeoutSec $TimeoutSec -MaximumRetryCount $MaximumRetryCount -RetryIntervalSec $RetryIntervalSec;
            }
            else {
                Invoke-RestMethod -Uri $downloadItem.url -Method Get -Headers $AzureDevOpsAuthenicationHeader -OutFile $localPath -TimeoutSec $TimeoutSec;
            }
            $stats['Downloaded']++; ## todo: improve lock, accuracy in multi-threaded scripts
        }
        catch {
            __logger_DownloadGitFiles "error    : $downloadPath : $($_.Exception)" $EnableVerboseLogging;
            $stats['Failed']++; ## todo: improve lock, accuracy in multi-threaded scripts
        } finally {
            $ProgressPreference = $SavedProgressPreference;
        }
    }

    if($enableDevOpsProgressUpdate) {
        $progressIndex = ([int]( ([float]$stats['Downloaded'] + $stats['Skipped'] + $stats['Failed']) * 100 / ([float]$allFilesCount) ));
        if(($progressIndex % 10) -eq 1) {
            Write-Host "##vso[task.setprogress value=$progressIndex;]DownloadGitFiles"
        }
    }
}

function __DownloadAndLoadGitModules_internal(
    [string[]]$modules,
    [string]$repoUrl,
    [string[]]$repoPathFilter,
    [string]$repoVersion,
    [string]$repoVersionType,
    [string]$repoPersonalAccessToken,
    [string]$downloadDir,
    [bool]$ForceDownload=$false)
{
    if(!$modules -or $modules.Count -le 0) {
        throw 'Import-GitModules: Exiting; invalid param modules';
    }

    $modulesInfo = $modules | %{
        $moduleNameSplit = $_ -split ':',2;
        if($moduleNameSplit.Length -eq 2) {
            return @{ Name = $moduleNameSplit[1]; Prefix = $moduleNameSplit[0]; };
        } else {
            return @{ Name = $moduleNameSplit[0]; Prefix = ''; };
        }
    }

    $moduleNames = $modulesInfo | %{ $_.Name } | unique; # we don't check if specific prefix was loaded or not.

    $moduleSearch = (Get-Module) | where { $_.Name -in $moduleNames };
    if(($moduleSearch.Count -ge $moduleNames.Count) -and !$ForceDownload) {
        Write-Host "Import-GitModules: Exiting; all $($moduleNames.Count) modules previously imported; no action required.";
        return;
    }

    if(!$repoUrl -or !$repoPathFilter -or $repoPathFilter.Count -le 0) {
        throw 'Import-GitModules: Exiting; invalid param repoUrl or repoPathFilter';
    }

    if(!$downloadDir) {
        $downloadDir='.';
    }

    $repoTag = $repoUrl -replace 'https://','' -replace '.azure.com','' -replace '/_apis/git/repositories/','-' -replace '/','-';
    $repoDownloadDir = (join-path $downloadDir $repoTag);
    $moduleEnvSeparator = ';';
    if ([System.Environment]::OSVersion.Platform -eq "Unix") {          
        $moduleEnvSeparator = ':';
    }

    $repoPathFilter | %{
        $repoDownloadSubDir = Join-Path $repoDownloadDir $_;
        $env:PSModulePath += "$moduleEnvSeparator$repoDownloadSubDir"; # todo global update
    }

    $modulesInfo | %{ 
        Import-Module -Prefix $_.Prefix -Name $_.Name -Global -Force -PassThru -ErrorAction SilentlyContinue;
    } | select -Property Prefix,Name,Version,ExportedCommands | Out-Host;

    $moduleSearch = (Get-Module) | where { $_.Name -in $moduleNames };
    if(($moduleSearch.Count -ge $moduleNames.Count) -and !$ForceDownload) {
        Write-Host "Import-GitModules: Exiting; all $($moduleNames.Count) modules loaded.";
        return;
    }

    if(!$repoPersonalAccessToken) { throw "Import-GitModules: Unable to download modules, Azure PersonalAccessToken not exists. SYSTEM_ACCESSTOKEN/PAT/AZUREDEVOPSPAT environment variable not found in environment"; }          

    if(!$repoVersion) { throw "Import-GitModules: Unable to download modules, Azure PersonalAccessToken not exists. SYSTEM_ACCESSTOKEN/PAT/AZUREDEVOPSPAT environment variable not found in environment"; }          

    if(!$repoVersionType) { throw "Import-GitModules: Unable to download modules, Azure PersonalAccessToken not exists. SYSTEM_ACCESSTOKEN/PAT/AZUREDEVOPSPAT environment variable not found in environment"; }          

    Write-Host "Import-GitModules: Module script starting to download..";            
    Import-GitFiles -RepoUrl $repoUrl `
        -RepoPersonalAccessToken $repoPersonalAccessToken `
        -RepoVersion $repoVersion `
        -RepoVersionType $repoVersionType `
        -DownloadDir $repoDownloadDir `
        -IncludePathFilter $repoPathFilter `
        -DownloadThrottleLimit 40 `
        -MaximumRetryCount 3 `
        -RetryIntervalSec 1 `
        -TimeoutSec 10 `
        -ExcludePathFilter @("NA") `
        -EnableDevOpsProgressUpdate $true `
        -EnableVerboseLogging $true;      

    $modulesInfo | %{ 
        Import-Module -Prefix $_.Prefix -Name $_.Name -Global -Force -PassThru -ErrorAction Stop;
    } | select -Property Prefix,Name,Version,ExportedCommands | Out-Host;

    $moduleSearch = (Get-Module) | where { $_.Name -in $moduleNames };
    if($moduleSearch.Count -lt $moduleNames.Count) {
        throw "Import-GitModules: unable to load all $($moduleNames.Count) modules.";
    }
}

function Import-GitModules
(
    ### Modules to load in the format, <ModuleName> or <ModulePrefix>:<ModuleName>
    [Parameter(Mandatory = $true)][string[]]$Modules,
    ### Repository URL. e.g., https://dev.azure.com/<organization>/project>/_apis/git/repositories/<repository>
    [Parameter(Mandatory = $true)][string]$RepoUrl,
    ### PersonalAccessToken that has access to read files in the repository. 
    [Parameter(Mandatory = $true)][string]$RepoPersonalAccessToken,
    ### relative paths in repo where module folders are located.
    [Parameter(Mandatory = $true)][string[]]$RepoPathFilter,
    ### Version of repository to download files. E.g., 'main' branch
    [Parameter(Mandatory = $true)][string]$RepoVersion,
    ### VersionType of the Version string. Options are: branch/commit/tag. See here: https://docs.microsoft.com/en-us/rest/api/azure/devops/git/items/get-items-batch?view=azure-devops-rest-6.0#gitversiontype
    [Parameter(Mandatory = $true)][string]$RepoVersionType,
    ### Directory to download the files to. 
    [Parameter(Mandatory = $true)][string]$DownloadDir,                         
    ### force redownloads.
    [Parameter(Mandatory = $false)][switch]$Force=$false)
{
<#
.SYNOPSIS
Downloads required files from Azure Git respository and load powershell modules. 
.DESCRIPTION
Downloads required files from Azure Git respository and load powershell modules. 
.LINK
https://github.com/AAATechGuy/GitFileDownloader 
.EXAMPLE
PS> Import-GitModules -Modules @('BingAdsDevOpsUtils','BingAds:BingAdsSecrets','BingAds:BingAdsUtils') 
      -RepoUrl 'https://dev.azure.com/msasg/Bing_Ads/_apis/git/repositories/AdsApps_CloudTest' 
      -RepoPathFilter @('private/Deployer/tools') -RepoVersion 'master' -RepoVersionType 'branch' -RepoPersonalAccessToken $repoPersonalAccessToken -$DownloadDir 'tmp' -Force; 
#>
    $PSBoundParameters.Keys | where { $_ -ne 'RepoPersonalAccessToken' } | foreach { Write-Host "Import-GitModules: parameter: $_ = $($PSBoundParameters[$_])" $EnableVerboseLogging }; # display parameters

    $measure = Measure-Command { 
        __DownloadAndLoadGitModules_internal -modules $modules -repoUrl $repoUrl -repoPathFilter $repoPathFilter -repoVersion $repoVersion -repoVersionType $repoVersionType -repoPersonalAccessToken $repoPersonalAccessToken -downloadDir $DownloadDir -Force $Force | Out-Host
    };
    Write-Host "Import-GitModules: completed in $($measure.TotalSeconds) sec";
}
