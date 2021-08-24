using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading.Tasks;

namespace Microsoft.GitDownload
{
    public static class HttpClientExtensions
    {
        public static async Task<string> PostAsJsonAsync<TRequest>(this HttpClient httpClient, string url, TRequest data, int maxRetries, int retryDelayInMSec)
        {
            var exMessages = new List<string>();
            for (int retryCount = 0; retryCount <= maxRetries; retryCount++)
            {
                try
                {
                    using (var responseMessage = await httpClient.PostAsJsonAsync<TRequest>(url, data))
                    {
                        if (responseMessage.StatusCode == HttpStatusCode.OK)
                        {
                            var responseStr = await responseMessage.Content.ReadAsStringAsync();
                            return responseStr;
                        }

                        var exMessage = $"{responseMessage.StatusCode}|" + await responseMessage.Content.ReadAsStringAsync();
                        if (responseMessage.StatusCode == HttpStatusCode.BadRequest)
                        {
                            throw new InvalidOperationException(exMessage);
                        }

                        exMessages.Add(exMessage);
                    }
                }
                catch (Exception ex)
                when (ex.ToString().Contains("System.Net.Sockets.SocketException"))
                {
                    exMessages.Add(ex.ToString());
                }

                if (retryCount < maxRetries)
                {
                    Console.WriteLine($"retrying ");
                    await Task.Delay(retryDelayInMSec);
                }
            }

            throw new AggregateException(exMessages.Select(ex => new Exception(ex)));
        }

        private static Task<HttpResponseMessage> PostAsJsonAsync<T>(this HttpClient httpClient, string url, T data)
        {
            if (data != null)
            {
                var dataAsString = JsonConvert.SerializeObject(
                    data,
                    Formatting.Indented,
                    new JsonSerializerSettings() { TypeNameHandling = TypeNameHandling.None });

                var content = new StringContent(dataAsString);
                content.Headers.ContentType = new MediaTypeHeaderValue("application/json");

                return httpClient.PostAsync(url, content);
            }
            else
            {
                return httpClient.GetAsync(url);
            }
        }
    }
}
