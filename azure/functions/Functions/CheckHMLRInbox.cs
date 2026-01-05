using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Graph;
using Microsoft.Graph.Models;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using LandRegFunctions.Models;

namespace LandRegFunctions.Functions;

/// <summary>
/// Timer-triggered function that checks the HMLR response inbox every 15 minutes.
/// Identifies RPMSG (Excel) and ZIP (title deeds) emails and pairs them for processing.
/// </summary>
public class CheckHMLRInbox
{
    private readonly ILogger<CheckHMLRInbox> _logger;
    private readonly GraphServiceClient _graphClient;
    private readonly BlobServiceClient _blobClient;
    private readonly MailboxSettings _mailboxSettings;

    public CheckHMLRInbox(
        ILogger<CheckHMLRInbox> logger,
        GraphServiceClient graphClient,
        BlobServiceClient blobClient,
        MailboxSettings mailboxSettings)
    {
        _logger = logger;
        _graphClient = graphClient;
        _blobClient = blobClient;
        _mailboxSettings = mailboxSettings;
    }

    /// <summary>
    /// Runs every 15 minutes to check for new HMLR response emails
    /// </summary>
    [Function("CheckHMLRInbox")]
    public async Task Run([TimerTrigger("0 */15 * * * *")] TimerInfo timerInfo)
    {
        _logger.LogInformation("CheckHMLRInbox function started at: {Time}", DateTime.UtcNow);

        try
        {
            // Get unread emails from HMLR
            var hmlrEmails = await GetUnreadHMLREmails();

            if (hmlrEmails.Count == 0)
            {
                _logger.LogInformation("No new HMLR emails found");
                return;
            }

            _logger.LogInformation("Found {Count} HMLR emails to process", hmlrEmails.Count);

            // Process each email
            foreach (var email in hmlrEmails)
            {
                await ProcessIncomingEmail(email);
            }

            // Check for paired emails ready for processing
            await CheckForPairedEmails();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking HMLR inbox");
            throw;
        }
    }

    /// <summary>
    /// HTTP trigger for manual inbox check (useful for testing)
    /// </summary>
    [Function("CheckHMLRInboxManual")]
    public async Task<Microsoft.Azure.Functions.Worker.Http.HttpResponseData> RunManual(
        [HttpTrigger(AuthorizationLevel.Function, "post")] Microsoft.Azure.Functions.Worker.Http.HttpRequestData req)
    {
        _logger.LogInformation("Manual inbox check triggered");

        try
        {
            // Get unread emails from HMLR
            var hmlrEmails = await GetUnreadHMLREmails();
            _logger.LogInformation("Found {Count} HMLR emails", hmlrEmails.Count);

            // Process each email
            foreach (var email in hmlrEmails)
            {
                await ProcessIncomingEmail(email);
            }

            // Check for paired emails
            var pairs = await CheckForPairedEmails();

            var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
            await response.WriteAsJsonAsync(new
            {
                Success = true,
                EmailsFound = hmlrEmails.Count,
                PairsReady = pairs.Count,
                CheckedAt = DateTime.UtcNow
            });
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in manual inbox check");
            var response = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            await response.WriteAsJsonAsync(new { Success = false, Error = ex.Message });
            return response;
        }
    }

    /// <summary>
    /// Get unread emails from HMLR senders
    /// </summary>
    private async Task<List<Message>> GetUnreadHMLREmails()
    {
        var emails = new List<Message>();

        try
        {
            // Build filter for unread emails from HMLR
            var senderFilters = string.Join(" or ",
                MailboxSettings.HMLRSenderAddresses.Select(addr => $"from/emailAddress/address eq '{addr}'"));
            var filter = $"isRead eq false and ({senderFilters})";

            _logger.LogInformation("Querying mailbox {Mailbox} with filter: {Filter}",
                _mailboxSettings.MailboxAddress, filter);

            // Query the mailbox
            var messages = await _graphClient.Users[_mailboxSettings.MailboxAddress]
                .Messages
                .GetAsync(config =>
                {
                    config.QueryParameters.Filter = filter;
                    config.QueryParameters.Select = new[] { "id", "subject", "from", "receivedDateTime", "hasAttachments" };
                    config.QueryParameters.Expand = new[] { "attachments" };
                    config.QueryParameters.Top = 50;
                    config.QueryParameters.Orderby = new[] { "receivedDateTime desc" };
                });

            if (messages?.Value != null)
            {
                emails.AddRange(messages.Value);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error querying mailbox for HMLR emails");
            throw;
        }

        return emails;
    }

    /// <summary>
    /// Process an incoming email - identify type and store for pairing
    /// </summary>
    private async Task ProcessIncomingEmail(Message email)
    {
        _logger.LogInformation("Processing email: {Subject} from {From} received {Received}",
            email.Subject,
            email.From?.EmailAddress?.Address,
            email.ReceivedDateTime);

        if (email.Attachments == null || email.Attachments.Count == 0)
        {
            _logger.LogWarning("Email {EmailId} has no attachments, skipping", email.Id);
            return;
        }

        // Identify email type based on attachments
        HMLREmailType? emailType = null;
        string? attachmentName = null;
        byte[]? attachmentContent = null;

        foreach (var attachment in email.Attachments)
        {
            if (attachment is FileAttachment fileAttachment)
            {
                var fileName = fileAttachment.Name?.ToLowerInvariant() ?? "";
                _logger.LogInformation("Found attachment: {Name}, ContentType: {ContentType}",
                    fileAttachment.Name, fileAttachment.ContentType);

                if (fileName.EndsWith(".rpmsg") || fileName.EndsWith(".xlsx") || fileName.EndsWith(".xls"))
                {
                    // This is the Excel results email (may be RPMSG encrypted or plain Excel)
                    emailType = HMLREmailType.ExcelResults;
                    attachmentName = fileAttachment.Name;
                    attachmentContent = fileAttachment.ContentBytes;
                    break;
                }
                else if (fileName.EndsWith(".zip"))
                {
                    // This is the title deeds ZIP email
                    emailType = HMLREmailType.TitleDeedsZip;
                    attachmentName = fileAttachment.Name;
                    attachmentContent = fileAttachment.ContentBytes;
                    break;
                }
            }
        }

        if (emailType == null)
        {
            _logger.LogWarning("Could not identify email type for {EmailId} with subject {Subject}",
                email.Id, email.Subject);
            return;
        }

        // Store the pending email
        var pendingEmail = new PendingHMLREmail
        {
            EmailId = email.Id!,
            Subject = email.Subject ?? "",
            ReceivedDateTime = email.ReceivedDateTime?.UtcDateTime ?? DateTime.UtcNow,
            FromAddress = email.From?.EmailAddress?.Address ?? "",
            EmailType = emailType.Value,
            AttachmentName = attachmentName
        };

        // Store attachment in blob storage
        if (attachmentContent != null)
        {
            pendingEmail.TempBlobPath = await StoreAttachmentTemporarily(
                email.Id!,
                attachmentName!,
                attachmentContent);
        }

        // Save pending email metadata
        await SavePendingEmail(pendingEmail);

        // Mark email as read
        await MarkEmailAsRead(email.Id!);

        _logger.LogInformation("Stored pending {Type} email: {EmailId}", emailType, email.Id);
    }

    /// <summary>
    /// Store attachment in temporary blob storage
    /// </summary>
    private async Task<string> StoreAttachmentTemporarily(string emailId, string fileName, byte[] content)
    {
        var containerClient = _blobClient.GetBlobContainerClient(MailboxSettings.PendingEmailsContainer);
        await containerClient.CreateIfNotExistsAsync();

        var blobPath = $"{emailId}/{fileName}";
        var blobClient = containerClient.GetBlobClient(blobPath);

        using var stream = new MemoryStream(content);
        await blobClient.UploadAsync(stream, overwrite: true);

        _logger.LogInformation("Stored attachment at: {Path}", blobPath);
        return blobPath;
    }

    /// <summary>
    /// Save pending email metadata to blob storage
    /// </summary>
    private async Task SavePendingEmail(PendingHMLREmail pendingEmail)
    {
        var containerClient = _blobClient.GetBlobContainerClient(MailboxSettings.PendingEmailsContainer);
        await containerClient.CreateIfNotExistsAsync();

        var metadataPath = $"{pendingEmail.EmailId}/metadata.json";
        var blobClient = containerClient.GetBlobClient(metadataPath);

        var json = JsonSerializer.Serialize(pendingEmail, new JsonSerializerOptions { WriteIndented = true });
        using var stream = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(json));
        await blobClient.UploadAsync(stream, overwrite: true);
    }

    /// <summary>
    /// Mark an email as read in the mailbox
    /// </summary>
    private async Task MarkEmailAsRead(string emailId)
    {
        try
        {
            await _graphClient.Users[_mailboxSettings.MailboxAddress]
                .Messages[emailId]
                .PatchAsync(new Message { IsRead = true });

            _logger.LogInformation("Marked email {EmailId} as read", emailId);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to mark email {EmailId} as read", emailId);
        }
    }

    /// <summary>
    /// Check for paired emails that are ready for processing
    /// </summary>
    private async Task<List<HMLRResponsePair>> CheckForPairedEmails()
    {
        var pairs = new List<HMLRResponsePair>();

        try
        {
            var containerClient = _blobClient.GetBlobContainerClient(MailboxSettings.PendingEmailsContainer);

            if (!await containerClient.ExistsAsync())
            {
                return pairs;
            }

            // Load all pending emails
            var pendingEmails = new List<PendingHMLREmail>();

            await foreach (var blobItem in containerClient.GetBlobsAsync(prefix: ""))
            {
                if (blobItem.Name.EndsWith("metadata.json"))
                {
                    var blobClient = containerClient.GetBlobClient(blobItem.Name);
                    var downloadResult = await blobClient.DownloadContentAsync();
                    var json = downloadResult.Value.Content.ToString();
                    var pendingEmail = JsonSerializer.Deserialize<PendingHMLREmail>(json);
                    if (pendingEmail != null)
                    {
                        pendingEmails.Add(pendingEmail);
                    }
                }
            }

            _logger.LogInformation("Found {Count} pending emails", pendingEmails.Count);

            // Find pairs within the time window
            var excelEmails = pendingEmails.Where(e => e.EmailType == HMLREmailType.ExcelResults).ToList();
            var zipEmails = pendingEmails.Where(e => e.EmailType == HMLREmailType.TitleDeedsZip).ToList();

            foreach (var excelEmail in excelEmails)
            {
                // Find a matching ZIP email within the time window
                var matchingZip = zipEmails.FirstOrDefault(z =>
                    Math.Abs((z.ReceivedDateTime - excelEmail.ReceivedDateTime).TotalHours) <= MailboxSettings.PairingWindowHours);

                if (matchingZip != null)
                {
                    _logger.LogInformation("Found pair: Excel {ExcelId} + ZIP {ZipId}",
                        excelEmail.EmailId, matchingZip.EmailId);

                    var pair = new HMLRResponsePair
                    {
                        ExcelEmail = excelEmail,
                        ZipEmail = matchingZip,
                        PairedAt = DateTime.UtcNow
                    };

                    pairs.Add(pair);

                    // Trigger processing (call ProcessHMLRResponse function)
                    await TriggerResponseProcessing(pair);

                    // Remove from pending lists to avoid re-pairing
                    zipEmails.Remove(matchingZip);
                }
            }

            _logger.LogInformation("Found {Count} pairs ready for processing", pairs.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking for paired emails");
        }

        return pairs;
    }

    /// <summary>
    /// Trigger the response processing function
    /// </summary>
    private async Task TriggerResponseProcessing(HMLRResponsePair pair)
    {
        _logger.LogInformation("Triggering processing for pair: Excel {ExcelId} + ZIP {ZipId}",
            pair.ExcelEmail.EmailId, pair.ZipEmail.EmailId);

        // Store the pair info for the processor to pick up
        var containerClient = _blobClient.GetBlobContainerClient(MailboxSettings.PendingEmailsContainer);
        var pairPath = $"pairs/{pair.ExcelEmail.EmailId}_{pair.ZipEmail.EmailId}.json";
        var blobClient = containerClient.GetBlobClient(pairPath);

        var json = JsonSerializer.Serialize(pair, new JsonSerializerOptions { WriteIndented = true });
        using var stream = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(json));
        await blobClient.UploadAsync(stream, overwrite: true);

        _logger.LogInformation("Pair stored for processing at: {Path}", pairPath);
    }
}
