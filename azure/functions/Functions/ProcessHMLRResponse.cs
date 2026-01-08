using System.IO.Compression;
using System.Net;
using System.Text.Json;
using ClosedXML.Excel;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Azure.Storage.Blobs;
using LandRegFunctions.Models;
using LandRegFunctions.Services;

namespace LandRegFunctions.Functions;

/// <summary>
/// Processes paired HMLR response emails (Excel results + ZIP of title deeds)
/// </summary>
public class ProcessHMLRResponse
{
    private readonly ILogger<ProcessHMLRResponse> _logger;
    private readonly BlobServiceClient _blobClient;
    private readonly SalesforceService _salesforceService;
    private readonly TitleDeedParser _titleDeedParser;
    private readonly EmailFolderService _emailFolderService;

    // HMLR Excel column mappings (0-based index)
    private const int ColCustomerRef = 0;
    private const int ColForename = 1;
    private const int ColSurname = 2;
    private const int ColCompanyName = 3;
    private const int ColAddress1 = 4;
    private const int ColAddress2 = 5;
    private const int ColAddress3 = 6;
    private const int ColAddress4 = 7;
    private const int ColAddress5 = 8;
    private const int ColPostcode = 9;
    private const int ColAddressMatchResult = 10;
    private const int ColTitleNumber = 11;
    private const int ColNameMatchResult = 12;

    // Azure Function base URL for title deed viewer
    private static readonly string TitleDeedFunctionBaseUrl =
        Environment.GetEnvironmentVariable("TITLE_DEED_FUNCTION_URL")
        ?? "https://func-landreg-api.azurewebsites.net/api/titledeeds";

    // Function key for title deed access (stored in app settings)
    private static readonly string? TitleDeedFunctionKey =
        Environment.GetEnvironmentVariable("TITLE_DEED_FUNCTION_KEY");

    public ProcessHMLRResponse(
        ILogger<ProcessHMLRResponse> logger,
        BlobServiceClient blobClient,
        SalesforceService salesforceService,
        TitleDeedParser titleDeedParser,
        EmailFolderService emailFolderService)
    {
        _logger = logger;
        _blobClient = blobClient;
        _salesforceService = salesforceService;
        _titleDeedParser = titleDeedParser;
        _emailFolderService = emailFolderService;
    }

    /// <summary>
    /// Process a paired HMLR response (triggered by CheckHMLRInbox when pair is found)
    /// </summary>
    [Function("ProcessHMLRResponse")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData req)
    {
        _logger.LogInformation("ProcessHMLRResponse function started at: {Time}", DateTime.UtcNow);

        HMLRResponsePair? pair = null;

        try
        {
            // Read the pair info from request body
            var requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            pair = JsonSerializer.Deserialize<HMLRResponsePair>(requestBody);

            if (pair == null)
            {
                _logger.LogError("Invalid request body - could not deserialize pair");
                var badResponse = req.CreateResponse(HttpStatusCode.BadRequest);
                await badResponse.WriteAsJsonAsync(new { Error = "Invalid request body" });
                return badResponse;
            }

            // Process the response
            var result = await ProcessResponsePair(pair);

            // Clean up pending emails
            await CleanupPendingEmails(pair);

            // Move emails to appropriate folder based on success/failure
            await _emailFolderService.MoveEmailPairAsync(
                pair.ExcelEmail.EmailId,
                pair.ZipEmail.EmailId,
                result.Success);

            var response = req.CreateResponse(HttpStatusCode.OK);
            await response.WriteAsJsonAsync(result);
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing HMLR response");

            // Move emails to Failed folder on exception
            if (pair != null)
            {
                try
                {
                    await _emailFolderService.MoveEmailPairAsync(
                        pair.ExcelEmail.EmailId,
                        pair.ZipEmail.EmailId,
                        success: false);
                }
                catch (Exception moveEx)
                {
                    _logger.LogError(moveEx, "Failed to move emails to Failed folder after processing error");
                }
            }

            var errorResponse = req.CreateResponse(HttpStatusCode.InternalServerError);
            await errorResponse.WriteAsJsonAsync(new { Error = ex.Message });
            return errorResponse;
        }
    }

    /// <summary>
    /// Blob-triggered processor for paired emails stored in blob
    /// </summary>
    [Function("ProcessHMLRResponseFromBlob")]
    public async Task RunFromBlob(
        [BlobTrigger("pending-hmlr-emails/pairs/{name}", Connection = "AzureWebJobsStorage")]
        Stream blobStream,
        string name)
    {
        _logger.LogInformation("Processing paired HMLR response from blob: {Name}", name);

        HMLRResponsePair? pair = null;

        try
        {
            using var reader = new StreamReader(blobStream);
            var json = await reader.ReadToEndAsync();
            pair = JsonSerializer.Deserialize<HMLRResponsePair>(json);

            if (pair == null)
            {
                _logger.LogError("Invalid pair data in blob: {Name}", name);
                return;
            }

            var result = await ProcessResponsePair(pair);

            _logger.LogInformation(
                "Processed HMLR response: {Total} total, {Matched} matched, {UnderReview} under review, {NoMatch} no match",
                result.TotalRows, result.MatchedRecords, result.UnderReviewRecords, result.NoMatchRecords);

            // Clean up
            await CleanupPendingEmails(pair);

            // Move emails to appropriate folder based on success/failure
            await _emailFolderService.MoveEmailPairAsync(
                pair.ExcelEmail.EmailId,
                pair.ZipEmail.EmailId,
                result.Success);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing HMLR response from blob {Name}", name);

            // Try to move emails to Failed folder on exception
            if (pair != null)
            {
                try
                {
                    await _emailFolderService.MoveEmailPairAsync(
                        pair.ExcelEmail.EmailId,
                        pair.ZipEmail.EmailId,
                        success: false);
                }
                catch (Exception moveEx)
                {
                    _logger.LogError(moveEx, "Failed to move emails to Failed folder after processing error");
                }
            }

            throw;
        }
    }

    /// <summary>
    /// Process a paired response - Excel results + ZIP of PDFs
    /// </summary>
    private async Task<HMLRProcessingResult> ProcessResponsePair(HMLRResponsePair pair)
    {
        var result = new HMLRProcessingResult
        {
            EmailReceivedAt = pair.ExcelEmail.ReceivedDateTime
        };

        try
        {
            // 1. Download and parse the Excel attachment
            var excelRows = await ParseExcelAttachment(pair.ExcelEmail);
            result.TotalRows = excelRows.Count;

            _logger.LogInformation("Parsed {Count} rows from Excel", excelRows.Count);

            // 2. Download and extract the ZIP attachment
            var titleDeeds = await ExtractZipAttachment(pair.ZipEmail);
            _logger.LogInformation("Extracted {Count} title deed PDFs from ZIP", titleDeeds.Count);

            // 3. Process each row and match to Salesforce records
            var updates = new List<SalesforceRecordUpdate>();

            foreach (var row in excelRows)
            {
                try
                {
                    var update = ProcessRow(row, titleDeeds, pair.ExcelEmail.ReceivedDateTime);
                    updates.Add(update);

                    // Count by status
                    switch (update.Status)
                    {
                        case "Matched":
                            result.MatchedRecords++;
                            break;
                        case "Under Review":
                            result.UnderReviewRecords++;
                            break;
                        case "No Match":
                            result.NoMatchRecords++;
                            break;
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Error processing row for CustomerRef: {Ref}", row.CustomerRef);
                    result.Errors.Add($"Row {row.CustomerRef}: {ex.Message}");
                    result.SkippedRows++;
                }
            }

            // 4. Upload title deeds to permanent blob storage
            await StoreTitleDeeds(titleDeeds, updates);

            // 5. Update Salesforce records
            await UpdateSalesforceRecords(updates);

            // Mark as successful before storing result for notification
            result.Success = true;

            // 6. Store processing result for notification
            await StoreProcessingResult(result, pair);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process HMLR response pair");
            result.Success = false;
            result.ErrorMessage = ex.Message;
        }

        return result;
    }

    /// <summary>
    /// Parse the Excel attachment from the email
    /// </summary>
    private async Task<List<HMLRResponseRow>> ParseExcelAttachment(PendingHMLREmail email)
    {
        var rows = new List<HMLRResponseRow>();

        if (string.IsNullOrEmpty(email.TempBlobPath))
        {
            throw new InvalidOperationException("No Excel attachment path available");
        }

        var containerClient = _blobClient.GetBlobContainerClient(HMLRMailboxConfig.PendingEmailsContainer);
        var blobClient = containerClient.GetBlobClient(email.TempBlobPath);

        using var stream = new MemoryStream();
        await blobClient.DownloadToAsync(stream);
        stream.Position = 0;

        // Handle RPMSG files - for now, log warning as we need to implement decryption
        if (email.AttachmentName?.ToLowerInvariant().EndsWith(".rpmsg") == true)
        {
            _logger.LogWarning("RPMSG file detected - decryption not yet implemented. " +
                "Manual extraction may be required for: {Path}", email.TempBlobPath);
            // TODO: Implement RPMSG decryption using Graph API or other method
            throw new NotImplementedException("RPMSG decryption not yet implemented");
        }

        // Parse Excel file
        using var workbook = new XLWorkbook(stream);
        var worksheet = workbook.Worksheets.First();

        // Skip header row, start from row 2
        var lastRow = worksheet.LastRowUsed()?.RowNumber() ?? 1;

        for (int rowNum = 2; rowNum <= lastRow; rowNum++)
        {
            var row = worksheet.Row(rowNum);

            // Skip empty rows
            if (row.IsEmpty())
                continue;

            var responseRow = new HMLRResponseRow
            {
                CustomerRef = row.Cell(ColCustomerRef + 1).GetString().Trim(),
                Forename = row.Cell(ColForename + 1).GetString().Trim(),
                Surname = row.Cell(ColSurname + 1).GetString().Trim(),
                CompanyName = row.Cell(ColCompanyName + 1).GetString().Trim(),
                Address1 = row.Cell(ColAddress1 + 1).GetString().Trim(),
                Address2 = row.Cell(ColAddress2 + 1).GetString().Trim(),
                Address3 = row.Cell(ColAddress3 + 1).GetString().Trim(),
                Address4 = row.Cell(ColAddress4 + 1).GetString().Trim(),
                Address5 = row.Cell(ColAddress5 + 1).GetString().Trim(),
                Postcode = row.Cell(ColPostcode + 1).GetString().Trim(),
                AddressMatchResult = row.Cell(ColAddressMatchResult + 1).GetString().Trim(),
                TitleNumber = row.Cell(ColTitleNumber + 1).GetString().Trim(),
                NameMatchResult = row.Cell(ColNameMatchResult + 1).GetString().Trim()
            };

            // Only add rows with a customer reference
            if (!string.IsNullOrEmpty(responseRow.CustomerRef))
            {
                rows.Add(responseRow);
            }
        }

        return rows;
    }

    /// <summary>
    /// Extract title deed PDFs from the ZIP attachment
    /// </summary>
    private async Task<Dictionary<string, byte[]>> ExtractZipAttachment(PendingHMLREmail email)
    {
        var titleDeeds = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);

        if (string.IsNullOrEmpty(email.TempBlobPath))
        {
            _logger.LogWarning("No ZIP attachment path available");
            return titleDeeds;
        }

        var containerClient = _blobClient.GetBlobContainerClient(HMLRMailboxConfig.PendingEmailsContainer);
        var blobClient = containerClient.GetBlobClient(email.TempBlobPath);

        using var zipStream = new MemoryStream();
        await blobClient.DownloadToAsync(zipStream);
        zipStream.Position = 0;

        using var archive = new ZipArchive(zipStream, ZipArchiveMode.Read);

        foreach (var entry in archive.Entries)
        {
            // Skip directories
            if (string.IsNullOrEmpty(entry.Name))
                continue;

            // Only process PDF files
            if (!entry.Name.ToLowerInvariant().EndsWith(".pdf"))
                continue;

            // Extract title number from filename (e.g., "WK238552.pdf" -> "WK238552")
            var titleNumber = Path.GetFileNameWithoutExtension(entry.Name);

            using var entryStream = entry.Open();
            using var memoryStream = new MemoryStream();
            await entryStream.CopyToAsync(memoryStream);

            titleDeeds[titleNumber] = memoryStream.ToArray();
            _logger.LogInformation("Extracted title deed: {TitleNumber}", titleNumber);
        }

        return titleDeeds;
    }

    /// <summary>
    /// Process a single row and create a Salesforce update
    /// </summary>
    private SalesforceRecordUpdate ProcessRow(
        HMLRResponseRow row,
        Dictionary<string, byte[]> titleDeeds,
        DateTime emailReceivedAt)
    {
        var update = new SalesforceRecordUpdate
        {
            // RecordId will be populated when we query Salesforce
            CustomerRef = row.CustomerRef,
            Postcode = row.Postcode,
            Status = row.GetSalesforceStatus(),
            MatchType = row.GetMatchType(),
            TitleNumber = row.TitleNumber,
            HMLRResponseDate = emailReceivedAt
        };

        // Check if we have a title deed for this record
        if (!string.IsNullOrEmpty(row.TitleNumber) &&
            titleDeeds.ContainsKey(row.TitleNumber))
        {
            _logger.LogInformation(
                "Title deed available for {CustomerRef}: {TitleNumber}",
                row.CustomerRef, row.TitleNumber);
        }

        return update;
    }

    /// <summary>
    /// Store title deeds in permanent blob storage and generate URLs
    /// </summary>
    private async Task StoreTitleDeeds(
        Dictionary<string, byte[]> titleDeeds,
        List<SalesforceRecordUpdate> updates)
    {
        var containerClient = _blobClient.GetBlobContainerClient("title-deeds");
        await containerClient.CreateIfNotExistsAsync();

        foreach (var (titleNumber, content) in titleDeeds)
        {
            // Find the update that matches this title number
            var matchingUpdate = updates.FirstOrDefault(u =>
                u.TitleNumber?.Equals(titleNumber, StringComparison.OrdinalIgnoreCase) == true);

            if (matchingUpdate == null)
            {
                _logger.LogWarning("No matching record for title deed: {TitleNumber}", titleNumber);
                continue;
            }

            // Store with path: {title-number}/{title-number}.pdf
            // This allows easy retrieval by title number
            var blobPath = $"{titleNumber}/{titleNumber}.pdf";
            var blobClient = containerClient.GetBlobClient(blobPath);

            using var stream = new MemoryStream(content);
            await blobClient.UploadAsync(stream, overwrite: true);

            matchingUpdate.TitleDeedBlobPath = blobPath;

            // Generate URL for viewing the title deed via Azure Function
            // Include function key if available for authentication
            var titleDeedUrl = $"{TitleDeedFunctionBaseUrl}/{titleNumber}";
            if (!string.IsNullOrEmpty(TitleDeedFunctionKey))
            {
                titleDeedUrl += $"?code={TitleDeedFunctionKey}";
            }
            matchingUpdate.TitleDeedUrl = titleDeedUrl;

            // Extract proprietor name from PDF
            var proprietorName = _titleDeedParser.ExtractProprietorName(content, titleNumber);
            if (!string.IsNullOrWhiteSpace(proprietorName))
            {
                matchingUpdate.TitleDeedProprietorName = proprietorName;
                _logger.LogInformation("Extracted proprietor for {TitleNumber}: {Proprietor}",
                    titleNumber, proprietorName);
            }

            _logger.LogInformation("Stored title deed at: {Path}, URL: {Url}",
                blobPath, matchingUpdate.TitleDeedUrl);
        }
    }

    /// <summary>
    /// Update Salesforce records with the processing results
    /// </summary>
    private async Task UpdateSalesforceRecords(List<SalesforceRecordUpdate> updates)
    {
        if (updates.Count == 0)
        {
            _logger.LogInformation("No records to update in Salesforce");
            return;
        }

        _logger.LogInformation("Updating {Count} Salesforce records...", updates.Count);

        // Build list of CustomerRefs to query
        var customerRefs = updates
            .Select(u => u.CustomerRef)
            .Where(c => !string.IsNullOrEmpty(c))
            .Distinct()
            .ToList();

        if (customerRefs.Count == 0)
        {
            _logger.LogWarning("No CustomerRefs found in updates");
            return;
        }

        // Query Salesforce for matching records
        // We match by Landlord_ID__c (CustomerRef) and Status = 'Submitted to HMLR'
        var customerRefList = string.Join("','", customerRefs);
        var soql = $@"SELECT Id, Name, Landlord_ID__c, Property_Postcode__c, Status__c
                      FROM Land_Registry_Check__c
                      WHERE Landlord_ID__c IN ('{customerRefList}')
                      AND Status__c = 'Submitted to HMLR'";

        _logger.LogInformation("Querying Salesforce: {Query}", soql);

        List<LandRegistryCheckRecord> sfRecords;
        try
        {
            sfRecords = await _salesforceService.QueryAsync<LandRegistryCheckRecord>(soql);
            _logger.LogInformation("Found {Count} matching records in Salesforce", sfRecords.Count);

            // Debug: Log all SF records returned
            foreach (var sfRec in sfRecords)
            {
                _logger.LogInformation(
                    "SF Record: Id={Id}, Name={Name}, LandlordId='{LandlordId}' (bytes: [{Bytes}]), Postcode={Postcode}",
                    sfRec.Id, sfRec.Name, sfRec.LandlordId,
                    string.Join(",", (sfRec.LandlordId ?? "").Select(c => (int)c)),
                    sfRec.PropertyPostcode);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to query Salesforce records");
            throw;
        }

        // Match updates to Salesforce records and prepare bulk update
        var bulkUpdates = new List<(string RecordId, object UpdateData)>();

        // Debug: Log all CustomerRefs from Excel
        _logger.LogInformation("Attempting to match {Count} updates from Excel:", updates.Count);
        foreach (var upd in updates)
        {
            _logger.LogInformation(
                "  Excel row: CustomerRef='{Ref}' (bytes: [{Bytes}]), TitleNumber={Title}, Status={Status}",
                upd.CustomerRef,
                string.Join(",", (upd.CustomerRef ?? "").Select(c => (int)c)),
                upd.TitleNumber,
                upd.Status);
        }

        foreach (var update in updates)
        {
            // Find matching Salesforce record by CustomerRef
            // If multiple matches, also try to match by postcode
            var matchingRecords = sfRecords
                .Where(r => r.LandlordId == update.CustomerRef)
                .ToList();

            LandRegistryCheckRecord? matchedRecord = null;

            if (matchingRecords.Count == 1)
            {
                matchedRecord = matchingRecords[0];
            }
            else if (matchingRecords.Count > 1)
            {
                // Multiple matches - try to narrow down by postcode
                var postcodeMatch = matchingRecords
                    .FirstOrDefault(r => NormalizePostcode(r.PropertyPostcode) == NormalizePostcode(update.Postcode));

                matchedRecord = postcodeMatch ?? matchingRecords[0];

                if (postcodeMatch == null)
                {
                    _logger.LogWarning(
                        "Multiple records found for CustomerRef {Ref}, using first match. " +
                        "Postcode matching failed (Update: {UpdatePostcode})",
                        update.CustomerRef, update.Postcode);
                }
            }

            if (matchedRecord == null)
            {
                _logger.LogWarning(
                    "No Salesforce record found for CustomerRef: '{Ref}' (bytes: [{Bytes}]). " +
                    "Remaining SF records: {Count}. Their LandlordIds: [{Ids}]",
                    update.CustomerRef,
                    string.Join(",", (update.CustomerRef ?? "").Select(c => (int)c)),
                    sfRecords.Count,
                    string.Join(", ", sfRecords.Select(r => $"'{r.LandlordId}'")));
                continue;
            }

            // Prepare update payload
            var updatePayload = new LandRegistryCheckUpdate
            {
                Status = update.Status,
                MatchType = update.MatchType,
                TitleNumber = update.TitleNumber,
                TitleDeedUrl = update.TitleDeedUrl,
                HMLRResponseDate = update.HMLRResponseDate,
                TitleDeedProprietorName = update.TitleDeedProprietorName
            };

            bulkUpdates.Add((matchedRecord.Id!, updatePayload));

            _logger.LogInformation(
                "Matched CustomerRef {Ref} to SF record {RecordId}: Status={Status}, TitleNumber={TitleNumber}",
                update.CustomerRef, matchedRecord.Id, update.Status, update.TitleNumber);

            // Remove from list to avoid duplicate matching
            sfRecords.Remove(matchedRecord);
        }

        // Perform bulk update
        if (bulkUpdates.Count > 0)
        {
            try
            {
                var successCount = await _salesforceService.BulkUpdateRecordsAsync(
                    "Land_Registry_Check__c",
                    bulkUpdates);

                _logger.LogInformation(
                    "Successfully updated {Success}/{Total} Salesforce records",
                    successCount, bulkUpdates.Count);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to update Salesforce records");
                throw;
            }
        }
        else
        {
            _logger.LogWarning("No records matched for Salesforce update");
        }
    }

    /// <summary>
    /// Normalize postcode for comparison (remove spaces, uppercase)
    /// </summary>
    private static string NormalizePostcode(string? postcode)
    {
        if (string.IsNullOrEmpty(postcode))
            return string.Empty;

        return postcode.Replace(" ", "").ToUpperInvariant();
    }

    /// <summary>
    /// Store processing result for notification function
    /// </summary>
    private async Task StoreProcessingResult(HMLRProcessingResult result, HMLRResponsePair pair)
    {
        var containerClient = _blobClient.GetBlobContainerClient(HMLRMailboxConfig.PendingEmailsContainer);
        var resultPath = $"results/{pair.ExcelEmail.EmailId}_{DateTime.UtcNow:yyyyMMdd_HHmmss}.json";
        var blobClient = containerClient.GetBlobClient(resultPath);

        var json = JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true });
        using var stream = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(json));
        await blobClient.UploadAsync(stream, overwrite: true);

        _logger.LogInformation("Stored processing result at: {Path}", resultPath);
    }

    /// <summary>
    /// Clean up pending email blobs after processing
    /// </summary>
    private async Task CleanupPendingEmails(HMLRResponsePair pair)
    {
        var containerClient = _blobClient.GetBlobContainerClient(HMLRMailboxConfig.PendingEmailsContainer);

        // Delete Excel email folder
        await DeleteBlobFolder(containerClient, pair.ExcelEmail.EmailId);

        // Delete ZIP email folder
        await DeleteBlobFolder(containerClient, pair.ZipEmail.EmailId);

        // Delete the pair file
        var pairPath = $"pairs/{pair.ExcelEmail.EmailId}_{pair.ZipEmail.EmailId}.json";
        var pairBlob = containerClient.GetBlobClient(pairPath);
        await pairBlob.DeleteIfExistsAsync();

        _logger.LogInformation("Cleaned up pending emails for pair");
    }

    /// <summary>
    /// Delete all blobs in a folder
    /// </summary>
    private async Task DeleteBlobFolder(BlobContainerClient container, string prefix)
    {
        await foreach (var blob in container.GetBlobsAsync(prefix: prefix))
        {
            await container.GetBlobClient(blob.Name).DeleteIfExistsAsync();
        }
    }
}
