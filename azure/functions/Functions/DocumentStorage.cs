using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;
using LandRegFunctions.Models;

namespace LandRegFunctions.Functions;

/// <summary>
/// Azure Functions for document storage operations (title deed PDFs)
/// Storage structure: title-deeds/{batch-id}/{record-id}/{title-number}.pdf
/// </summary>
public class DocumentStorage
{
    private readonly ILogger<DocumentStorage> _logger;
    private readonly BlobServiceClient _blobServiceClient;
    private const string ContainerName = "title-deeds";

    public DocumentStorage(
        ILogger<DocumentStorage> logger,
        BlobServiceClient blobServiceClient)
    {
        _logger = logger;
        _blobServiceClient = blobServiceClient;
    }

    /// <summary>
    /// Upload a document (PDF) to blob storage
    /// </summary>
    [Function("UploadDocument")]
    public async Task<HttpResponseData> UploadDocument(
        [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData req)
    {
        _logger.LogInformation("UploadDocument function triggered");

        try
        {
            var request = await req.ReadFromJsonAsync<DocumentUploadRequest>();
            if (request == null)
            {
                return await CreateErrorResponse(req, HttpStatusCode.BadRequest,
                    "Invalid request body");
            }

            // Validate required fields
            if (string.IsNullOrWhiteSpace(request.BatchId) ||
                string.IsNullOrWhiteSpace(request.RecordId) ||
                string.IsNullOrWhiteSpace(request.TitleNumber))
            {
                return await CreateErrorResponse(req, HttpStatusCode.BadRequest,
                    "BatchId, RecordId, and TitleNumber are required");
            }

            if (string.IsNullOrWhiteSpace(request.DocumentBase64))
            {
                return await CreateErrorResponse(req, HttpStatusCode.BadRequest,
                    "DocumentBase64 is required");
            }

            // Decode base64 content
            byte[] documentBytes;
            try
            {
                documentBytes = Convert.FromBase64String(request.DocumentBase64);
            }
            catch (FormatException)
            {
                return await CreateErrorResponse(req, HttpStatusCode.BadRequest,
                    "Invalid Base64 encoding for DocumentBase64");
            }

            _logger.LogInformation(
                "Uploading document for Batch: {BatchId}, Record: {RecordId}, Title: {TitleNumber}, Size: {Size} bytes",
                request.BatchId, request.RecordId, request.TitleNumber, documentBytes.Length);

            // Build blob path: {batch-id}/{record-id}/{title-number}.pdf
            var sanitizedTitleNumber = SanitizeFileName(request.TitleNumber);
            var blobPath = $"{request.BatchId}/{request.RecordId}/{sanitizedTitleNumber}.pdf";

            // Get container and blob client
            var containerClient = _blobServiceClient.GetBlobContainerClient(ContainerName);
            await containerClient.CreateIfNotExistsAsync();

            var blobClient = containerClient.GetBlobClient(blobPath);

            // Upload with metadata
            var metadata = new Dictionary<string, string>
            {
                { "BatchId", request.BatchId },
                { "RecordId", request.RecordId },
                { "TitleNumber", request.TitleNumber },
                { "UploadedAt", DateTime.UtcNow.ToString("O") }
            };

            if (!string.IsNullOrWhiteSpace(request.FileName))
            {
                metadata["OriginalFileName"] = request.FileName;
            }

            using var stream = new MemoryStream(documentBytes);
            await blobClient.UploadAsync(stream, new BlobUploadOptions
            {
                HttpHeaders = new BlobHttpHeaders
                {
                    ContentType = request.ContentType
                },
                Metadata = metadata
            });

            _logger.LogInformation("Document uploaded successfully: {BlobPath}", blobPath);

            // Create success response
            var responseBody = new DocumentUploadResponse
            {
                Success = true,
                BlobPath = blobPath,
                BlobUrl = blobClient.Uri.ToString(),
                FileSizeBytes = documentBytes.Length,
                UploadedAt = DateTime.UtcNow
            };

            var response = req.CreateResponse(HttpStatusCode.OK);
            await response.WriteAsJsonAsync(responseBody);
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error uploading document");
            return await CreateErrorResponse(req, HttpStatusCode.InternalServerError,
                $"Error uploading document: {ex.Message}");
        }
    }

    /// <summary>
    /// Get a time-limited SAS URL for viewing a document
    /// </summary>
    [Function("GetDocumentUrl")]
    public async Task<HttpResponseData> GetDocumentUrl(
        [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData req)
    {
        _logger.LogInformation("GetDocumentUrl function triggered");

        try
        {
            var request = await req.ReadFromJsonAsync<DocumentAccessRequest>();
            if (request == null)
            {
                return await CreateErrorResponse(req, HttpStatusCode.BadRequest,
                    "Invalid request body");
            }

            // Determine blob path
            string blobPath;
            if (!string.IsNullOrWhiteSpace(request.BlobPath))
            {
                blobPath = request.BlobPath;
            }
            else if (!string.IsNullOrWhiteSpace(request.BatchId) &&
                     !string.IsNullOrWhiteSpace(request.RecordId) &&
                     !string.IsNullOrWhiteSpace(request.TitleNumber))
            {
                var sanitizedTitleNumber = SanitizeFileName(request.TitleNumber);
                blobPath = $"{request.BatchId}/{request.RecordId}/{sanitizedTitleNumber}.pdf";
            }
            else
            {
                return await CreateErrorResponse(req, HttpStatusCode.BadRequest,
                    "Either BlobPath or (BatchId, RecordId, TitleNumber) are required");
            }

            _logger.LogInformation("Generating SAS URL for: {BlobPath}", blobPath);

            // Get container and blob client
            var containerClient = _blobServiceClient.GetBlobContainerClient(ContainerName);
            var blobClient = containerClient.GetBlobClient(blobPath);

            // Check if blob exists
            if (!await blobClient.ExistsAsync())
            {
                return await CreateErrorResponse(req, HttpStatusCode.NotFound,
                    $"Document not found: {blobPath}");
            }

            // Generate SAS URL
            var expiryMinutes = request.ExpiryMinutes > 0 ? request.ExpiryMinutes : 60;
            var expiresAt = DateTimeOffset.UtcNow.AddMinutes(expiryMinutes);

            // Use user delegation key if using managed identity, otherwise service SAS
            string sasUrl;
            if (blobClient.CanGenerateSasUri)
            {
                var sasBuilder = new BlobSasBuilder
                {
                    BlobContainerName = ContainerName,
                    BlobName = blobPath,
                    Resource = "b",
                    ExpiresOn = expiresAt
                };
                sasBuilder.SetPermissions(BlobSasPermissions.Read);

                sasUrl = blobClient.GenerateSasUri(sasBuilder).ToString();
            }
            else
            {
                // Fallback: return the blob URL (would need other auth mechanism)
                _logger.LogWarning("Cannot generate SAS URI - returning blob URL without SAS");
                sasUrl = blobClient.Uri.ToString();
            }

            _logger.LogInformation("SAS URL generated, expires at: {ExpiresAt}", expiresAt);

            // Create success response
            var responseBody = new DocumentAccessResponse
            {
                Success = true,
                SasUrl = sasUrl,
                BlobPath = blobPath,
                ExpiresAt = expiresAt.UtcDateTime
            };

            var response = req.CreateResponse(HttpStatusCode.OK);
            await response.WriteAsJsonAsync(responseBody);
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error generating document URL");
            return await CreateErrorResponse(req, HttpStatusCode.InternalServerError,
                $"Error generating document URL: {ex.Message}");
        }
    }

    /// <summary>
    /// List all documents for a batch or record
    /// </summary>
    [Function("ListDocuments")]
    public async Task<HttpResponseData> ListDocuments(
        [HttpTrigger(AuthorizationLevel.Function, "get")] HttpRequestData req)
    {
        _logger.LogInformation("ListDocuments function triggered");

        try
        {
            // Get query parameters
            var query = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
            var batchId = query["batchId"];
            var recordId = query["recordId"];

            if (string.IsNullOrWhiteSpace(batchId))
            {
                return await CreateErrorResponse(req, HttpStatusCode.BadRequest,
                    "batchId query parameter is required");
            }

            // Build prefix for listing
            string prefix = batchId;
            if (!string.IsNullOrWhiteSpace(recordId))
            {
                prefix = $"{batchId}/{recordId}";
            }

            _logger.LogInformation("Listing documents with prefix: {Prefix}", prefix);

            // Get container client
            var containerClient = _blobServiceClient.GetBlobContainerClient(ContainerName);

            // List blobs
            var documents = new List<DocumentInfo>();
            await foreach (var blobItem in containerClient.GetBlobsAsync(prefix: prefix))
            {
                documents.Add(new DocumentInfo
                {
                    BlobPath = blobItem.Name,
                    FileName = Path.GetFileName(blobItem.Name),
                    FileSizeBytes = blobItem.Properties.ContentLength ?? 0,
                    UploadedAt = blobItem.Properties.CreatedOn?.UtcDateTime,
                    ContentType = blobItem.Properties.ContentType ?? "application/pdf"
                });
            }

            _logger.LogInformation("Found {Count} documents", documents.Count);

            // Create success response
            var responseBody = new DocumentListResponse
            {
                Success = true,
                Documents = documents
            };

            var response = req.CreateResponse(HttpStatusCode.OK);
            await response.WriteAsJsonAsync(responseBody);
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error listing documents");
            return await CreateErrorResponse(req, HttpStatusCode.InternalServerError,
                $"Error listing documents: {ex.Message}");
        }
    }

    /// <summary>
    /// Delete a document from blob storage
    /// </summary>
    [Function("DeleteDocument")]
    public async Task<HttpResponseData> DeleteDocument(
        [HttpTrigger(AuthorizationLevel.Function, "delete")] HttpRequestData req)
    {
        _logger.LogInformation("DeleteDocument function triggered");

        try
        {
            var request = await req.ReadFromJsonAsync<DocumentAccessRequest>();
            if (request == null)
            {
                return await CreateErrorResponse(req, HttpStatusCode.BadRequest,
                    "Invalid request body");
            }

            // Determine blob path
            string blobPath;
            if (!string.IsNullOrWhiteSpace(request.BlobPath))
            {
                blobPath = request.BlobPath;
            }
            else if (!string.IsNullOrWhiteSpace(request.BatchId) &&
                     !string.IsNullOrWhiteSpace(request.RecordId) &&
                     !string.IsNullOrWhiteSpace(request.TitleNumber))
            {
                var sanitizedTitleNumber = SanitizeFileName(request.TitleNumber);
                blobPath = $"{request.BatchId}/{request.RecordId}/{sanitizedTitleNumber}.pdf";
            }
            else
            {
                return await CreateErrorResponse(req, HttpStatusCode.BadRequest,
                    "Either BlobPath or (BatchId, RecordId, TitleNumber) are required");
            }

            _logger.LogInformation("Deleting document: {BlobPath}", blobPath);

            // Get container and blob client
            var containerClient = _blobServiceClient.GetBlobContainerClient(ContainerName);
            var blobClient = containerClient.GetBlobClient(blobPath);

            // Delete blob
            var deleted = await blobClient.DeleteIfExistsAsync();

            if (!deleted)
            {
                return await CreateErrorResponse(req, HttpStatusCode.NotFound,
                    $"Document not found: {blobPath}");
            }

            _logger.LogInformation("Document deleted successfully: {BlobPath}", blobPath);

            var response = req.CreateResponse(HttpStatusCode.OK);
            await response.WriteAsJsonAsync(new { Success = true, DeletedPath = blobPath });
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting document");
            return await CreateErrorResponse(req, HttpStatusCode.InternalServerError,
                $"Error deleting document: {ex.Message}");
        }
    }

    /// <summary>
    /// Sanitize filename to be safe for blob storage
    /// </summary>
    private static string SanitizeFileName(string fileName)
    {
        // Remove or replace invalid characters
        var invalid = Path.GetInvalidFileNameChars();
        var sanitized = new string(fileName.Where(c => !invalid.Contains(c)).ToArray());

        // Replace spaces with underscores
        sanitized = sanitized.Replace(' ', '_');

        return sanitized;
    }

    private async Task<HttpResponseData> CreateErrorResponse(
        HttpRequestData req,
        HttpStatusCode statusCode,
        string errorMessage)
    {
        var response = req.CreateResponse(statusCode);
        await response.WriteAsJsonAsync(new DocumentUploadResponse
        {
            Success = false,
            ErrorMessage = errorMessage
        });
        return response;
    }
}
