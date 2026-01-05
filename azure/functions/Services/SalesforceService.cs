using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Azure.Security.KeyVault.Secrets;

namespace LandRegFunctions.Services;

/// <summary>
/// Service for interacting with Salesforce REST API
/// </summary>
public class SalesforceService
{
    private readonly ILogger<SalesforceService> _logger;
    private readonly SecretClient _secretClient;
    private readonly HttpClient _httpClient;

    private string? _accessToken;
    private DateTime _tokenExpiry = DateTime.MinValue;
    private string? _instanceUrl;

    private const string ApiVersion = "v59.0";

    public SalesforceService(
        ILogger<SalesforceService> logger,
        SecretClient secretClient,
        HttpClient httpClient)
    {
        _logger = logger;
        _secretClient = secretClient;
        _httpClient = httpClient;
    }

    /// <summary>
    /// Ensure we have a valid access token
    /// </summary>
    private async Task EnsureAuthenticatedAsync()
    {
        if (!string.IsNullOrEmpty(_accessToken) && DateTime.UtcNow < _tokenExpiry)
        {
            return; // Token is still valid
        }

        _logger.LogInformation("Authenticating with Salesforce...");

        // Get credentials from Key Vault
        var consumerKey = (await _secretClient.GetSecretAsync("sf-consumer-key")).Value.Value;
        var consumerSecret = (await _secretClient.GetSecretAsync("sf-consumer-secret")).Value.Value;
        var loginUrl = (await _secretClient.GetSecretAsync("sf-login-url")).Value.Value;
        _instanceUrl = (await _secretClient.GetSecretAsync("sf-instance-url")).Value.Value;

        // OAuth2 client credentials flow (username-password flow for connected app)
        var tokenEndpoint = $"{loginUrl}/services/oauth2/token";

        var requestContent = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            { "grant_type", "client_credentials" },
            { "client_id", consumerKey },
            { "client_secret", consumerSecret }
        });

        var response = await _httpClient.PostAsync(tokenEndpoint, requestContent);
        var responseContent = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            _logger.LogError("Salesforce authentication failed: {Response}", responseContent);
            throw new Exception($"Salesforce authentication failed: {responseContent}");
        }

        var tokenResponse = JsonSerializer.Deserialize<SalesforceTokenResponse>(responseContent);

        if (tokenResponse == null || string.IsNullOrEmpty(tokenResponse.AccessToken))
        {
            throw new Exception("Failed to parse Salesforce token response");
        }

        _accessToken = tokenResponse.AccessToken;
        _tokenExpiry = DateTime.UtcNow.AddHours(1); // Tokens typically last 2 hours, refresh at 1

        // Use instance URL from token response if available, otherwise use configured one
        if (!string.IsNullOrEmpty(tokenResponse.InstanceUrl))
        {
            _instanceUrl = tokenResponse.InstanceUrl;
        }

        _logger.LogInformation("Salesforce authentication successful. Instance: {InstanceUrl}", _instanceUrl);
    }

    /// <summary>
    /// Query Salesforce records using SOQL
    /// </summary>
    public async Task<List<T>> QueryAsync<T>(string soql) where T : class
    {
        await EnsureAuthenticatedAsync();

        var encodedQuery = Uri.EscapeDataString(soql);
        var queryUrl = $"{_instanceUrl}/services/data/{ApiVersion}/query?q={encodedQuery}";

        var request = new HttpRequestMessage(HttpMethod.Get, queryUrl);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _accessToken);

        var response = await _httpClient.SendAsync(request);
        var responseContent = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            _logger.LogError("Salesforce query failed: {Response}", responseContent);
            throw new Exception($"Salesforce query failed: {responseContent}");
        }

        var queryResult = JsonSerializer.Deserialize<SalesforceQueryResult<T>>(responseContent);
        return queryResult?.Records ?? new List<T>();
    }

    /// <summary>
    /// Update a Salesforce record
    /// </summary>
    public async Task<bool> UpdateRecordAsync(string objectName, string recordId, object updateData)
    {
        await EnsureAuthenticatedAsync();

        var updateUrl = $"{_instanceUrl}/services/data/{ApiVersion}/sobjects/{objectName}/{recordId}";

        var jsonContent = JsonSerializer.Serialize(updateData, new JsonSerializerOptions
        {
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
        });

        var request = new HttpRequestMessage(HttpMethod.Patch, updateUrl)
        {
            Content = new StringContent(jsonContent, Encoding.UTF8, "application/json")
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _accessToken);

        var response = await _httpClient.SendAsync(request);

        if (!response.IsSuccessStatusCode)
        {
            var responseContent = await response.Content.ReadAsStringAsync();
            _logger.LogError("Salesforce update failed for {ObjectName}/{RecordId}: {Response}",
                objectName, recordId, responseContent);
            return false;
        }

        _logger.LogInformation("Successfully updated {ObjectName}/{RecordId}", objectName, recordId);
        return true;
    }

    /// <summary>
    /// Bulk update multiple records using Composite API
    /// </summary>
    public async Task<int> BulkUpdateRecordsAsync(string objectName, List<(string RecordId, object UpdateData)> updates)
    {
        if (updates.Count == 0) return 0;

        await EnsureAuthenticatedAsync();

        var successCount = 0;

        // Composite API allows up to 25 subrequests
        var batches = updates.Chunk(25);

        foreach (var batch in batches)
        {
            var compositeRequest = new
            {
                allOrNone = false,
                compositeRequest = batch.Select((u, index) => new
                {
                    method = "PATCH",
                    url = $"/services/data/{ApiVersion}/sobjects/{objectName}/{u.RecordId}",
                    referenceId = $"ref{index}",
                    body = u.UpdateData
                }).ToArray()
            };

            var compositeUrl = $"{_instanceUrl}/services/data/{ApiVersion}/composite";

            var jsonContent = JsonSerializer.Serialize(compositeRequest, new JsonSerializerOptions
            {
                DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
            });

            var request = new HttpRequestMessage(HttpMethod.Post, compositeUrl)
            {
                Content = new StringContent(jsonContent, Encoding.UTF8, "application/json")
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _accessToken);

            var response = await _httpClient.SendAsync(request);
            var responseContent = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogError("Salesforce composite update failed: {Response}", responseContent);
                continue;
            }

            var compositeResponse = JsonSerializer.Deserialize<SalesforceCompositeResponse>(responseContent);
            if (compositeResponse?.CompositeResponse != null)
            {
                successCount += compositeResponse.CompositeResponse.Count(r => r.HttpStatusCode >= 200 && r.HttpStatusCode < 300);
            }
        }

        _logger.LogInformation("Bulk update completed: {Success}/{Total} records updated",
            successCount, updates.Count);

        return successCount;
    }
}

#region Salesforce Response Models

public class SalesforceTokenResponse
{
    [JsonPropertyName("access_token")]
    public string? AccessToken { get; set; }

    [JsonPropertyName("instance_url")]
    public string? InstanceUrl { get; set; }

    [JsonPropertyName("token_type")]
    public string? TokenType { get; set; }
}

public class SalesforceQueryResult<T>
{
    [JsonPropertyName("totalSize")]
    public int TotalSize { get; set; }

    [JsonPropertyName("done")]
    public bool Done { get; set; }

    [JsonPropertyName("records")]
    public List<T>? Records { get; set; }
}

public class SalesforceCompositeResponse
{
    [JsonPropertyName("compositeResponse")]
    public List<CompositeSubResponse>? CompositeResponse { get; set; }
}

public class CompositeSubResponse
{
    [JsonPropertyName("httpStatusCode")]
    public int HttpStatusCode { get; set; }

    [JsonPropertyName("referenceId")]
    public string? ReferenceId { get; set; }
}

#endregion
