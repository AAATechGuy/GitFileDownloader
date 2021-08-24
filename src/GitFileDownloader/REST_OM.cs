namespace Microsoft.GitDownload
{
    public class ItemsBatchRequest
    {
        public ItemDescriptor[] itemDescriptors { get; set; }
        public string includeContentMetadata { get; set; }
    }

    public class ItemDescriptor
    {
        public string path { get; set; }
        public string version { get; set; }
        public string versionType { get; set; }
        public string versionOptions { get; set; }
        public string recursionLevel { get; set; }
    }

    public class ItemsBatchResponse
    {
        public int count { get; set; }
        public Value[][] value { get; set; }
    }

    public class Value
    {
        public string objectId { get; set; }
        public string gitObjectType { get; set; }
        public string commitId { get; set; }
        public string path { get; set; }
        public bool isFolder { get; set; }
        public Contentmetadata contentMetadata { get; set; }
        public string url { get; set; }
    }

    public class Contentmetadata
    {
        public string fileName { get; set; }
        public int encoding { get; set; }
        public string contentType { get; set; }
        public string extension { get; set; }
    }
}
