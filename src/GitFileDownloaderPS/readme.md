
Bootstrap code example: 
```
  if(!$env:PAT) { 
      throw "PAT environment variable/ Azure PersonalAccessToken not found in environment"; 
  } 
  Invoke-WebRequest https://raw.githubusercontent.com/AAATechGuy/GitFileDownloader/bd0b9c191114af83fe0f5b4b4bcfe8d1302ebd9b/src/GitFileDownloaderPS/GitFileDownloaderPS_v1.ps1 -OutFile .\GitFileDownloaderPS_v1.ps1; 
  . .\GitFileDownloaderPS_v1.ps1; 
  DownloadGitFiles -AzureDevOpsRepoUrl $repoUrl -AzureDevOpsPAT $env:PAT -Version $repoBranch -VersionType "branch" -DownloadDir $moduleDir -IncludePathFilter @($toolsSrcPath) -DownloadThrottleLimit 40 -MaximumRetryCount 3 -RetryIntervalSec 1 -TimeoutSec 10 -ExcludePathFilter @("NA") -EnableDevOpsProgressUpdate $true; 
```

Detailed usage example: 
```
NAME
    DownloadGitFiles
    
SYNOPSIS
    Downloads files from Azure Git respository.
    
    
SYNTAX
    DownloadGitFiles [-AzureDevOpsRepoUrl] <String> [-AzureDevOpsPAT] <String> [-Version] <String> [-VersionType] <String> [-DownloadDir] <String> [[-IncludePathFilter] <String[]>] [[-DownloadThrottleLimit] 
    <Int32>] [[-MaximumRetryCount] <Int32>] [[-RetryIntervalSec] <Int32>] [[-TimeoutSec] <Int32>] [[-ExcludePathFilter] <String[]>] [[-EnableDevOpsProgressUpdate] <Boolean>] [<CommonParameters>]
    
    
DESCRIPTION
    Downloads files from Azure Git respository.
    

PARAMETERS
    -AzureDevOpsRepoUrl <String>
        Repository URL. e.g., https://dev.azure.com/<organization>/project>/_apis/git/repositories/<repository>
        
    -AzureDevOpsPAT <String>
        PersonalAccessToken that has access to read files in the repository.
        
    -Version <String>
        Version of repository to download files. E.g., 'main' branch
        
    -VersionType <String>
        VersionType of the Version string. Options are: branch/commit/tag. See here: https://docs.microsoft.com/en-us/rest/api/azure/devops/git/items/get-items-batch?view=azure-devops-rest-6.0#gitversiontype
        
    -DownloadDir <String>
        Directory to download the files to.
        
    -IncludePathFilter <String[]>
        Folders to include for download. E.g., @('subFolder1','/subFolder20/subFolder23')
        
    -DownloadThrottleLimit <Int32>
        Maximum threads to enable parallel downloads. Only available for PS7.0+
        
    -MaximumRetryCount <Int32>
        Retry count when calling REST API. Only available for PS7.0+
        
    -RetryIntervalSec <Int32>
        Retry interval in seconds when calling REST API. Only available for PS7.0+
        
    -TimeoutSec <Int32>
        Timeout in seconds when calling each REST API.
        
    -ExcludePathFilter <String[]>
        Folders to exclude from download. E.g., @('*/folder1/*','*file1.ext')
        
    -EnableDevOpsProgressUpdate <Boolean>
        If true, emits best-effort progress indicator used in Azure Pipelines via API at 
        https://docs.microsoft.com/en-us/azure/devops/pipelines/scripts/logging-commands?view=azure-devops&tabs=bash#setprogress-show-percentage-completed
        
    <CommonParameters>
        This cmdlet supports the common parameters: Verbose, Debug,
        ErrorAction, ErrorVariable, WarningAction, WarningVariable,
        OutBuffer, PipelineVariable, and OutVariable. For more information, see 
        about_CommonParameters (https:/go.microsoft.com/fwlink/?LinkID=113216). 
    
    -------------------------- EXAMPLE 1 --------------------------
    
    PS>DownloadGitFiles -AzureDevOpsRepoUrl 'https://dev.azure.com/<organization>/project>/_apis/git/repositories/<repository>' -AzureDevOpsPAT $confidentialPAT -Version 'master' -VersionType 'branch' 
    -DownloadDir 'D:\tmp\srcX' -IncludePathFilter @('folder1','/folder20/folder21') -DownloadThrottleLimit 40 -MaximumRetryCount 3 -RetryIntervalSec 1 -TimeoutSec 10 -ExcludePathFilter 
    @('*/folder3/*','*file4.bat') -EnableDevOpsProgressUpdate $true

```

