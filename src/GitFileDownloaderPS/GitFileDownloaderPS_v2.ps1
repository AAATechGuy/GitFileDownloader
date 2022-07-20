

function __logger_DownloadGitFiles ([string]$Message, [bool]$EnableVerboseLogging = $true) { if($EnableVerboseLogging) { Write-Host "DownloadGitFiles : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') : $Message"; } }

function DownloadGitFiles
(
    ### Repository URL. e.g., https://dev.azure.com/<organization>/project>/_apis/git/repositories/<repository>
    [Parameter(Mandatory = $true)][string]$AzureDevOpsRepoUrl,                  
    ### PersonalAccessToken that has access to read files in the repository. 
    [Parameter(Mandatory = $true)][string]$AzureDevOpsPAT,                      
    ### Version of repository to download files. E.g., 'main' branch
    [Parameter(Mandatory = $true)][string]$Version,                             
    ### VersionType of the Version string. Options are: branch/commit/tag. See here: https://docs.microsoft.com/en-us/rest/api/azure/devops/git/items/get-items-batch?view=azure-devops-rest-6.0#gitversiontype
    [Parameter(Mandatory = $true)][string]$VersionType,                         
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
PS> DownloadGitFiles -AzureDevOpsRepoUrl 'https://dev.azure.com/<organization>/project>/_apis/git/repositories/<repository>' -AzureDevOpsPAT $confidentialPAT -Version 'master' -VersionType 'branch' -DownloadDir 'D:\tmp\srcX' -IncludePathFilter @('folder1','/folder20/folder21') -DownloadThrottleLimit 40 -MaximumRetryCount 3 -RetryIntervalSec 1 -TimeoutSec 10 -ExcludePathFilter @('*/folder3/*','*file4.bat') -EnableDevOpsProgressUpdate $true
#>
    $PSBoundParameters.Keys | foreach { __logger_DownloadGitFiles "parameter: $_ = $($PSBoundParameters[$_])" $EnableVerboseLogging }; # display parameters

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
    if($psVersion -ge 7) {
        $result = Invoke-RestMethod -Uri $urlGetFileList -Method Post -Headers $AzureDevOpsAuthenicationHeader -Body $body -ContentType "application/json" -TimeoutSec $TimeoutSec -MaximumRetryCount $MaximumRetryCount -RetryIntervalSec $RetryIntervalSec; 
    }
    else {
        $result = Invoke-RestMethod -Uri $urlGetFileList -Method Post -Headers $AzureDevOpsAuthenicationHeader -Body $body -ContentType "application/json" -TimeoutSec $TimeoutSec; 
    }

    $allFiles = $result.value | %{ $_ };
    $allFilesCount = $allFiles.Count;
    __logger_DownloadGitFiles "found $($result.Count) batches and $allFilesCount files" $EnableVerboseLogging;

    $downloadGitFileFunc = $global:__downloadGitFileFunc;

    if($psVersion -ge 7) {
        # create concurrent queue
        $fileQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new();
        $allFiles | %{ $fileQueue.Enqueue($_); };

        # this is needed because scripts cannot be passed into -Parallel via $using:
        $script_downloadGitFileFunc = $downloadGitFileFunc.ToString();

        # start parallel downloads
        1..$DownloadThrottleLimit | ForEach-Object -ThrottleLimit $DownloadThrottleLimit -Parallel {
            
            # this is needed because scripts cannot be passed into -Parallel via $using:
            $script_downloadGitFileFunc = $using:script_downloadGitFileFunc; 
            $downloadGitFileFunc = [Scriptblock]::Create($script_downloadGitFileFunc); 
            
            # fetch item from queue
            $downloadItem = '';
            $fileQueue = $using:fileQueue;
            while($fileQueue.TryDequeue([ref]$downloadItem)) {
                $downloadGitFileFunc.Invoke($downloadItem, $using:downloadDir, $using:ExcludePathFilter, $using:stats, $using:psVersion, $using:AzureDevOpsAuthenicationHeader, $using:TimeoutSec, $using:MaximumRetryCount, $using:RetryIntervalSec, $using:enableDevOpsProgressUpdate, $using:allFilesCount, $using:EnableVerboseLogging);
            }
        }
    }
    else {
        $allFiles | ForEach-Object { 
            $downloadItem = $_;
            $downloadGitFileFunc.Invoke($downloadItem, $downloadDir, $ExcludePathFilter, $stats, $psVersion, $AzureDevOpsAuthenicationHeader, $TimeoutSec, $MaximumRetryCount, $RetryIntervalSec, $enableDevOpsProgressUpdate, $allFilesCount, $EnableVerboseLogging);
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
$global:__downloadGitFileFunc = {
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
        }
    }

    if($enableDevOpsProgressUpdate) {
        $progressIndex = ([int]( ([float]$stats['Downloaded'] + $stats['Skipped'] + $stats['Failed']) * 100 / ([float]$allFilesCount) ));
        if(($progressIndex % 10) -eq 1) {
            Write-Host "##vso[task.setprogress value=$progressIndex;]DownloadGitFiles"
        }
    }
}
