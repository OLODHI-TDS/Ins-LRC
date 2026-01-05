using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Azure.Storage.Blobs;

namespace LandRegFunctions.Functions;

/// <summary>
/// Serves title deed PDFs from blob storage.
/// Used by Salesforce to display PDFs in the UI.
/// </summary>
public class GetTitleDeed
{
    private readonly ILogger<GetTitleDeed> _logger;
    private readonly BlobServiceClient _blobClient;

    private const string TitleDeedsContainer = "title-deeds";

    public GetTitleDeed(
        ILogger<GetTitleDeed> logger,
        BlobServiceClient blobClient)
    {
        _logger = logger;
        _blobClient = blobClient;
    }

    /// <summary>
    /// Get a title deed PDF by title number
    /// </summary>
    /// <param name="req">HTTP request</param>
    /// <param name="titleNumber">The title number (e.g., "AGL264342")</param>
    /// <returns>PDF file or error response</returns>
    [Function("GetTitleDeed")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "get", Route = "titledeeds/{titleNumber}")] HttpRequestData req,
        string titleNumber)
    {
        _logger.LogInformation("GetTitleDeed request for: {TitleNumber}", titleNumber);

        if (string.IsNullOrWhiteSpace(titleNumber))
        {
            var badRequest = req.CreateResponse(HttpStatusCode.BadRequest);
            await badRequest.WriteAsJsonAsync(new { Error = "Title number is required" });
            return badRequest;
        }

        try
        {
            // Sanitize title number to prevent path traversal
            var sanitizedTitleNumber = SanitizeTitleNumber(titleNumber);

            var containerClient = _blobClient.GetBlobContainerClient(TitleDeedsContainer);

            // Try the standard path: {titleNumber}/{titleNumber}.pdf
            var blobPath = $"{sanitizedTitleNumber}/{sanitizedTitleNumber}.pdf";
            var blobClient = containerClient.GetBlobClient(blobPath);

            if (!await blobClient.ExistsAsync())
            {
                _logger.LogWarning("Title deed not found: {TitleNumber}", sanitizedTitleNumber);
                var notFound = req.CreateResponse(HttpStatusCode.NotFound);
                await notFound.WriteAsJsonAsync(new { Error = $"Title deed not found: {sanitizedTitleNumber}" });
                return notFound;
            }

            // Download the PDF
            var downloadResult = await blobClient.DownloadContentAsync();
            var pdfContent = downloadResult.Value.Content.ToArray();

            _logger.LogInformation("Serving title deed: {TitleNumber} ({Size} bytes)",
                sanitizedTitleNumber, pdfContent.Length);

            // Return PDF with appropriate headers
            var response = req.CreateResponse(HttpStatusCode.OK);
            response.Headers.Add("Content-Type", "application/pdf");
            response.Headers.Add("Content-Disposition", $"inline; filename=\"{sanitizedTitleNumber}.pdf\"");
            response.Headers.Add("Cache-Control", "private, max-age=3600"); // Cache for 1 hour

            await response.Body.WriteAsync(pdfContent);
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving title deed: {TitleNumber}", titleNumber);
            var errorResponse = req.CreateResponse(HttpStatusCode.InternalServerError);
            await errorResponse.WriteAsJsonAsync(new { Error = "Failed to retrieve title deed" });
            return errorResponse;
        }
    }

    /// <summary>
    /// Sanitize title number to prevent path traversal attacks
    /// </summary>
    private static string SanitizeTitleNumber(string titleNumber)
    {
        // Remove any path separators or dangerous characters
        return titleNumber
            .Replace("/", "")
            .Replace("\\", "")
            .Replace("..", "")
            .Trim();
    }
}
