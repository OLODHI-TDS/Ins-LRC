using Microsoft.Extensions.Logging;
using Microsoft.Graph;
using Microsoft.Graph.Models;
using LandRegFunctions.Models;

namespace LandRegFunctions.Services;

/// <summary>
/// Service for managing email folder operations (moving processed/failed emails)
/// </summary>
public class EmailFolderService
{
    private readonly ILogger<EmailFolderService> _logger;
    private readonly GraphServiceClient _graphClient;
    private readonly HMLRMailboxConfig _mailboxConfig;

    // Cache folder IDs to avoid repeated lookups
    private string? _processedFolderId;
    private string? _failedFolderId;

    public EmailFolderService(
        ILogger<EmailFolderService> logger,
        GraphServiceClient graphClient,
        HMLRMailboxConfig mailboxConfig)
    {
        _logger = logger;
        _graphClient = graphClient;
        _mailboxConfig = mailboxConfig;
    }

    /// <summary>
    /// Ensure the Processed and Failed folders exist in the mailbox.
    /// Creates them if they don't exist.
    /// </summary>
    public async Task EnsureFoldersExistAsync()
    {
        _logger.LogInformation("Ensuring email folders exist for mailbox: {Mailbox}", _mailboxConfig.MailboxAddress);

        _processedFolderId = await GetOrCreateFolderAsync(HMLRMailboxConfig.ProcessedFolderName);
        _failedFolderId = await GetOrCreateFolderAsync(HMLRMailboxConfig.FailedFolderName);

        _logger.LogInformation(
            "Email folders ready - Processed: {ProcessedId}, Failed: {FailedId}",
            _processedFolderId, _failedFolderId);
    }

    /// <summary>
    /// Move an email to the Processed folder
    /// </summary>
    public async Task MoveEmailToProcessedAsync(string emailId)
    {
        if (string.IsNullOrEmpty(_processedFolderId))
        {
            await EnsureFoldersExistAsync();
        }

        await MoveEmailToFolderAsync(emailId, _processedFolderId!, HMLRMailboxConfig.ProcessedFolderName);
    }

    /// <summary>
    /// Move an email to the Failed folder
    /// </summary>
    public async Task MoveEmailToFailedAsync(string emailId)
    {
        if (string.IsNullOrEmpty(_failedFolderId))
        {
            await EnsureFoldersExistAsync();
        }

        await MoveEmailToFolderAsync(emailId, _failedFolderId!, HMLRMailboxConfig.FailedFolderName);
    }

    /// <summary>
    /// Move an email pair to the appropriate folder based on processing result
    /// </summary>
    public async Task MoveEmailPairAsync(string excelEmailId, string zipEmailId, bool success)
    {
        if (success)
        {
            _logger.LogInformation("Moving email pair to Processed folder");
            await MoveEmailToProcessedAsync(excelEmailId);
            await MoveEmailToProcessedAsync(zipEmailId);
        }
        else
        {
            _logger.LogInformation("Moving email pair to Failed folder");
            await MoveEmailToFailedAsync(excelEmailId);
            await MoveEmailToFailedAsync(zipEmailId);
        }
    }

    /// <summary>
    /// Get or create a mail folder in the mailbox
    /// </summary>
    private async Task<string> GetOrCreateFolderAsync(string folderName)
    {
        try
        {
            // First, try to find the folder
            var folders = await _graphClient.Users[_mailboxConfig.MailboxAddress]
                .MailFolders
                .GetAsync(config =>
                {
                    config.QueryParameters.Filter = $"displayName eq '{folderName}'";
                });

            if (folders?.Value?.Count > 0)
            {
                var existingFolder = folders.Value[0];
                _logger.LogDebug("Found existing folder: {FolderName} with ID: {FolderId}",
                    folderName, existingFolder.Id);
                return existingFolder.Id!;
            }

            // Folder doesn't exist, create it
            _logger.LogInformation("Creating mail folder: {FolderName}", folderName);

            var newFolder = new MailFolder
            {
                DisplayName = folderName
            };

            var createdFolder = await _graphClient.Users[_mailboxConfig.MailboxAddress]
                .MailFolders
                .PostAsync(newFolder);

            _logger.LogInformation("Created mail folder: {FolderName} with ID: {FolderId}",
                folderName, createdFolder?.Id);

            return createdFolder?.Id ?? throw new InvalidOperationException($"Failed to create folder: {folderName}");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting or creating folder: {FolderName}", folderName);
            throw;
        }
    }

    /// <summary>
    /// Move an email to a specific folder
    /// </summary>
    private async Task MoveEmailToFolderAsync(string emailId, string destinationFolderId, string folderName)
    {
        try
        {
            _logger.LogInformation("Moving email {EmailId} to folder {FolderName}", emailId, folderName);

            await _graphClient.Users[_mailboxConfig.MailboxAddress]
                .Messages[emailId]
                .Move
                .PostAsync(new Microsoft.Graph.Users.Item.Messages.Item.Move.MovePostRequestBody
                {
                    DestinationId = destinationFolderId
                });

            _logger.LogInformation("Successfully moved email {EmailId} to {FolderName}", emailId, folderName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to move email {EmailId} to {FolderName}", emailId, folderName);
            // Don't throw - moving emails is not critical to processing success
            // Log the error and continue
        }
    }
}
