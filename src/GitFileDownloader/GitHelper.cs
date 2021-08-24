using Newtonsoft.Json;
using System;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using System.Threading.Tasks.Dataflow;

namespace Microsoft.GitDownload
{
    public static class GitHelper
    {
        public static void DownloadGitFiles(
            string uriRepo,
            string azureDevOpsPAT,
            string[] downloadPathList,
            string version,
            string versionType,
            string downloadDir,
            int parallelCount)
        {
            LogInfo(@$"Running with parameters: 
AzureDevOpsRepoUrl      : {uriRepo}
AzureDevOpsPAT          : {new string('*', azureDevOpsPAT?.Length ?? 0)}
PathCsv                 : {string.Join(Environment.NewLine + new string(' ', 26), downloadPathList)}
Version                 : {version}
VersionType             : {versionType}
DownloadDir             : {downloadDir}
Parallelism             : {parallelCount}
");

            var itemsBatchRequest = new ItemsBatchRequest();
            itemsBatchRequest.includeContentMetadata = true.ToString();
            itemsBatchRequest.itemDescriptors = downloadPathList
                .Select(p => new ItemDescriptor
                {
                    path = p,
                    version = version,
                    versionType = versionType,
                    versionOptions = "none",
                    recursionLevel = "full"
                })
                .ToArray();

            var inventoryStr = PostAsync<ItemsBatchRequest>(uriRepo, "itemsbatch", azureDevOpsPAT, itemsBatchRequest).Result;
            var inventory = JsonConvert.DeserializeObject<ItemsBatchResponse>(inventoryStr);

            var filesInventory = inventory.value
                .SelectMany(x => x.Select(y => y)) // select items from sub-arrays
                .GroupBy(x => x.objectId).Select(x => x.First()) // find distinct
                .OrderBy(x => x.path)
                .ToArray();

            LogInfo($"Found {filesInventory.Length} item(s) to download.");

            var fullDownloadPath = Path.GetFullPath(Environment.ExpandEnvironmentVariables(downloadDir));
            LogInfo($"Starting download to {fullDownloadPath}");

            var taskBuffer = new ActionBlock<Value>(
                action: fileMetadata => DownloadFile(fileMetadata, azureDevOpsPAT, fullDownloadPath),
                dataflowBlockOptions: new ExecutionDataflowBlockOptions()
                {
                    MaxDegreeOfParallelism = parallelCount, // parallel threads that would process the items in queue
                });

            foreach (var fileMetadata in filesInventory)
            {
                taskBuffer.Post(fileMetadata);
            }

            taskBuffer.Complete();
            taskBuffer.Completion.Wait();

            LogInfo($"Completed download at {fullDownloadPath}");
        }

        private static async Task DownloadFile(Value fileMetadata, string azureDevOpsPAT, string downloadDir)
        {
            if (fileMetadata.isFolder) { return; }

            LogInfo($"Downloading {fileMetadata.path}");

            var fileContent = await GetAsync(fileMetadata.url, "", azureDevOpsPAT);
            var downloadFilePath = Path.GetFullPath(Path.Combine(downloadDir, fileMetadata.path.TrimStart('/', '\\')));

            var dirPath = Path.GetDirectoryName(downloadFilePath);
            if (!Directory.Exists(dirPath)) { Directory.CreateDirectory(dirPath); }

            File.WriteAllText(downloadFilePath, fileContent);
        }

        private static async Task<string> GetAsync(string uriRepo, string path, string azureDevOpsPAT, string apiVersion = "6.0", int timeoutInSec = 30)
            => await PostAsync<string>(uriRepo, path, azureDevOpsPAT, data: null, apiVersion, timeoutInSec);

        private static async Task<string> PostAsync<TRequest>(string uriRepo, string path, string azureDevOpsPAT, TRequest data, string apiVersion = "6.0", int timeoutInSec = 30)
        {
            using (var httpClient = new HttpClient())
            {
                httpClient.Timeout = TimeSpan.FromSeconds(timeoutInSec);

                var azureDevOpsAuthenicationHeaderValue = $"Basic {Convert.ToBase64String(Encoding.ASCII.GetBytes($":{azureDevOpsPAT}"))}";
                httpClient.DefaultRequestHeaders.Add("Authorization", azureDevOpsAuthenicationHeaderValue);

                var url = new Uri($"{uriRepo}/{path}");
                var querySeparator = string.IsNullOrWhiteSpace(url.Query) ? "?" : "&";
                var apiVersionQuery = $"api-version={apiVersion}";
                var urlWithQuery = $"{url.AbsoluteUri.TrimEnd('/')}{querySeparator}{apiVersionQuery}"; // find another clean way

                var responseStr = await httpClient.PostAsJsonAsync<TRequest>(urlWithQuery, data, maxRetries: 2, retryDelayInMSec: 1000);
                return responseStr;
            }
        }

        internal const string TITLE = "GitFileDownloader";

        private static void LogInfo(string message)
            => Console.WriteLine($"[{DateTime.UtcNow.ToString("u")}] {TITLE}: {message}");
    }
}
