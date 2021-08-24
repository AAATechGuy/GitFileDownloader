using System;

namespace Microsoft.GitDownload
{
    class Program
    {
        static void Main(string[] args)
        {
            try
            {
                var AzureDevOpsRepoUrl = args.Length >= 1 ? args[0] : throw new ArgumentNullException("AzureDevOpsRepoUrl");
                var AzureDevOpsPAT = args.Length >= 2 ? args[1] : throw new ArgumentNullException("AzureDevOpsPAT");
                var PathCsv = args.Length >= 3 ? args[2] : throw new ArgumentNullException("PathCsv");
                var Version = args.Length >= 4 ? args[3] : "master";
                var VersionType = args.Length >= 5 ? args[4] : "branch";
                var DownloadDir = args.Length >= 6 ? args[5] : "drop";
                var ParallelCount = args.Length >= 7 ? int.Parse(args[6]) : 1;

                var pathList = PathCsv.Split(new[] { "," }, StringSplitOptions.RemoveEmptyEntries);
                GitHelper.DownloadGitFiles(
                    AzureDevOpsRepoUrl,
                    AzureDevOpsPAT,
                    pathList,
                    Version,
                    VersionType,
                    DownloadDir,
                    ParallelCount);
            }
            catch (Exception)
            {
                PrintHelp();
                throw;
            }
        }

        private static void PrintHelp()
        {
            Console.WriteLine(@$"{new string('~', 50)}
{GitHelper.TITLE} usage: 
AzureDevOpsRepoUrl      - e.g. format: https://dev.azure.com/msasg/Bing_Ads/_apis/git/repositories/AnB
AzureDevOpsPAT          - PAT token that has code-read access on your Repo
PathCsv                 - list of files/folders to download, e.g., /private/app.config,/private/appsettings.json,/build/
Version                 - Version string identifier (name of tag/branch, SHA1 of commit). Defaults to 'master'.
VersionType             - Version type (branch, tag, or commit). Determines how Version string Id is interpreted. Defaults to 'branch'.
                          See https://docs.microsoft.com/en-us/rest/api/azure/devops/git/items/get?view=azure-devops-rest-6.0#gitversiontype
DownloadDir             - folder to download to. Defaults to 'drop'.
ParallelCount           - max thread used to download files in parallel. Defaults to '1'.
{new string('~', 50)}");
        }
    }
}
