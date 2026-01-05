using System.Text;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Azure.Communication.Email;
using Azure.Security.KeyVault.Secrets;
using Azure.Storage.Blobs;
using LandRegFunctions.Models;

namespace LandRegFunctions.Functions;

/// <summary>
/// Sends notification emails to the compliance team after HMLR responses are processed
/// </summary>
public class NotifyComplianceTeam
{
    private readonly ILogger<NotifyComplianceTeam> _logger;
    private readonly EmailClient _emailClient;
    private readonly SecretClient _secretClient;
    private readonly BlobServiceClient _blobClient;

    // Notification recipients
    private const string PrimaryRecipient = "karen.spriggs@tdsgroup.uk";
    private static readonly string[] CcRecipients = new[]
    {
        "omar.lodhi@tdsgroup.uk",
        "adrian.delaporte@tdsgroup.uk"
    };

    public NotifyComplianceTeam(
        ILogger<NotifyComplianceTeam> logger,
        EmailClient emailClient,
        SecretClient secretClient,
        BlobServiceClient blobClient)
    {
        _logger = logger;
        _emailClient = emailClient;
        _secretClient = secretClient;
        _blobClient = blobClient;
    }

    /// <summary>
    /// HTTP trigger to send notification (can be called after processing)
    /// </summary>
    [Function("NotifyComplianceTeam")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData req)
    {
        _logger.LogInformation("NotifyComplianceTeam function started");

        try
        {
            var requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            var result = JsonSerializer.Deserialize<HMLRProcessingResult>(requestBody);

            if (result == null)
            {
                var badResponse = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                await badResponse.WriteAsJsonAsync(new { Error = "Invalid request body" });
                return badResponse;
            }

            await SendNotificationEmail(result);

            var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
            await response.WriteAsJsonAsync(new { Success = true, Message = "Notification sent" });
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error sending notification");
            var errorResponse = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            await errorResponse.WriteAsJsonAsync(new { Error = ex.Message });
            return errorResponse;
        }
    }

    /// <summary>
    /// Blob trigger to automatically send notification when processing result is stored
    /// </summary>
    [Function("NotifyComplianceTeamFromBlob")]
    public async Task RunFromBlob(
        [BlobTrigger("pending-hmlr-emails/results/{name}", Connection = "AzureWebJobsStorage")]
        Stream blobStream,
        string name)
    {
        _logger.LogInformation("Processing result blob detected: {Name}", name);

        try
        {
            using var reader = new StreamReader(blobStream);
            var json = await reader.ReadToEndAsync();
            var result = JsonSerializer.Deserialize<HMLRProcessingResult>(json);

            if (result == null)
            {
                _logger.LogError("Invalid processing result in blob: {Name}", name);
                return;
            }

            await SendNotificationEmail(result);

            // Clean up the result blob after notification
            var containerClient = _blobClient.GetBlobContainerClient(HMLRMailboxConfig.PendingEmailsContainer);
            var blobClient = containerClient.GetBlobClient($"results/{name}");
            await blobClient.DeleteIfExistsAsync();

            _logger.LogInformation("Notification sent and result blob cleaned up");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing notification from blob {Name}", name);
            throw;
        }
    }

    /// <summary>
    /// Send the notification email
    /// </summary>
    private async Task SendNotificationEmail(HMLRProcessingResult result)
    {
        var senderEmail = _secretClient.GetSecret("acs-sender-email").Value.Value;

        var subject = result.Success
            ? $"HMLR Response Processed - {result.TotalRows} Records"
            : "HMLR Response Processing Failed";

        var htmlBody = BuildEmailBody(result);
        var plainTextBody = BuildPlainTextBody(result);

        var emailMessage = new EmailMessage(
            senderAddress: senderEmail,
            content: new EmailContent(subject)
            {
                Html = htmlBody,
                PlainText = plainTextBody
            },
            recipients: new EmailRecipients(
                to: new List<EmailAddress> { new EmailAddress(PrimaryRecipient) },
                cc: CcRecipients.Select(email => new EmailAddress(email)).ToList()
            )
        );

        _logger.LogInformation("Sending notification email to {Recipient}", PrimaryRecipient);

        var operation = await _emailClient.SendAsync(Azure.WaitUntil.Completed, emailMessage);

        _logger.LogInformation("Notification email sent. Status: {Status}, MessageId: {Id}",
            operation.Value.Status, operation.Value.Id);
    }

    /// <summary>
    /// Build HTML email body
    /// </summary>
    private string BuildEmailBody(HMLRProcessingResult result)
    {
        var sb = new StringBuilder();

        sb.AppendLine("<!DOCTYPE html>");
        sb.AppendLine("<html><head><style>");
        sb.AppendLine("body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }");
        sb.AppendLine(".container { max-width: 600px; margin: 0 auto; padding: 20px; }");
        sb.AppendLine(".header { background-color: #003087; color: white; padding: 20px; text-align: center; }");
        sb.AppendLine(".content { padding: 20px; background-color: #f5f5f5; }");
        sb.AppendLine(".stats { display: flex; justify-content: space-around; margin: 20px 0; }");
        sb.AppendLine(".stat-box { text-align: center; padding: 15px; background: white; border-radius: 5px; min-width: 100px; }");
        sb.AppendLine(".stat-number { font-size: 24px; font-weight: bold; }");
        sb.AppendLine(".stat-label { font-size: 12px; color: #666; }");
        sb.AppendLine(".matched { color: #28a745; }");
        sb.AppendLine(".review { color: #ffc107; }");
        sb.AppendLine(".nomatch { color: #dc3545; }");
        sb.AppendLine(".error { background-color: #f8d7da; border: 1px solid #f5c6cb; padding: 10px; border-radius: 5px; }");
        sb.AppendLine(".footer { text-align: center; padding: 10px; font-size: 12px; color: #666; }");
        sb.AppendLine("</style></head><body>");

        sb.AppendLine("<div class='container'>");

        // Header
        sb.AppendLine("<div class='header'>");
        sb.AppendLine("<h1>HMLR Response Processed</h1>");
        sb.AppendLine($"<p>Received: {result.EmailReceivedAt:dd MMM yyyy HH:mm}</p>");
        sb.AppendLine("</div>");

        // Content
        sb.AppendLine("<div class='content'>");

        if (result.Success)
        {
            // Stats boxes
            sb.AppendLine("<div class='stats'>");

            sb.AppendLine("<div class='stat-box'>");
            sb.AppendLine($"<div class='stat-number'>{result.TotalRows}</div>");
            sb.AppendLine("<div class='stat-label'>Total Records</div>");
            sb.AppendLine("</div>");

            sb.AppendLine("<div class='stat-box'>");
            sb.AppendLine($"<div class='stat-number matched'>{result.MatchedRecords}</div>");
            sb.AppendLine("<div class='stat-label'>Matched</div>");
            sb.AppendLine("</div>");

            sb.AppendLine("<div class='stat-box'>");
            sb.AppendLine($"<div class='stat-number review'>{result.UnderReviewRecords}</div>");
            sb.AppendLine("<div class='stat-label'>Under Review</div>");
            sb.AppendLine("</div>");

            sb.AppendLine("<div class='stat-box'>");
            sb.AppendLine($"<div class='stat-number nomatch'>{result.NoMatchRecords}</div>");
            sb.AppendLine("<div class='stat-label'>No Match</div>");
            sb.AppendLine("</div>");

            sb.AppendLine("</div>");

            // Action items
            if (result.UnderReviewRecords > 0)
            {
                sb.AppendLine("<h3>Action Required</h3>");
                sb.AppendLine($"<p>{result.UnderReviewRecords} record(s) require manual review. ");
                sb.AppendLine("Please check Salesforce for records with status 'Under Review'.</p>");
            }

            if (result.NoMatchRecords > 0)
            {
                sb.AppendLine($"<p>{result.NoMatchRecords} record(s) had no property match. ");
                sb.AppendLine("These may need further investigation.</p>");
            }

            // Skipped rows warning
            if (result.SkippedRows > 0)
            {
                sb.AppendLine("<div class='error'>");
                sb.AppendLine($"<strong>Warning:</strong> {result.SkippedRows} row(s) were skipped due to errors.");
                sb.AppendLine("</div>");
            }
        }
        else
        {
            // Error state
            sb.AppendLine("<div class='error'>");
            sb.AppendLine("<h3>Processing Failed</h3>");
            sb.AppendLine($"<p>{result.ErrorMessage}</p>");
            sb.AppendLine("</div>");
        }

        sb.AppendLine("</div>");

        // Footer
        sb.AppendLine("<div class='footer'>");
        sb.AppendLine($"<p>Processed at: {result.ProcessedAt:dd MMM yyyy HH:mm:ss} UTC</p>");
        sb.AppendLine("<p>This is an automated message from the Land Registry Compliance System.</p>");
        sb.AppendLine("</div>");

        sb.AppendLine("</div>");
        sb.AppendLine("</body></html>");

        return sb.ToString();
    }

    /// <summary>
    /// Build plain text email body
    /// </summary>
    private string BuildPlainTextBody(HMLRProcessingResult result)
    {
        var sb = new StringBuilder();

        sb.AppendLine("HMLR RESPONSE PROCESSED");
        sb.AppendLine("=======================");
        sb.AppendLine();
        sb.AppendLine($"Email Received: {result.EmailReceivedAt:dd MMM yyyy HH:mm}");
        sb.AppendLine($"Processed At: {result.ProcessedAt:dd MMM yyyy HH:mm:ss} UTC");
        sb.AppendLine();

        if (result.Success)
        {
            sb.AppendLine("SUMMARY");
            sb.AppendLine("-------");
            sb.AppendLine($"Total Records: {result.TotalRows}");
            sb.AppendLine($"Matched: {result.MatchedRecords}");
            sb.AppendLine($"Under Review: {result.UnderReviewRecords}");
            sb.AppendLine($"No Match: {result.NoMatchRecords}");

            if (result.SkippedRows > 0)
            {
                sb.AppendLine($"Skipped (Errors): {result.SkippedRows}");
            }

            sb.AppendLine();

            if (result.UnderReviewRecords > 0)
            {
                sb.AppendLine("ACTION REQUIRED");
                sb.AppendLine("---------------");
                sb.AppendLine($"{result.UnderReviewRecords} record(s) require manual review.");
                sb.AppendLine("Please check Salesforce for records with status 'Under Review'.");
                sb.AppendLine();
            }

            if (result.NoMatchRecords > 0)
            {
                sb.AppendLine($"{result.NoMatchRecords} record(s) had no property match.");
                sb.AppendLine("These may need further investigation.");
            }
        }
        else
        {
            sb.AppendLine("PROCESSING FAILED");
            sb.AppendLine("-----------------");
            sb.AppendLine($"Error: {result.ErrorMessage}");
        }

        sb.AppendLine();
        sb.AppendLine("---");
        sb.AppendLine("This is an automated message from the Land Registry Compliance System.");

        return sb.ToString();
    }
}
