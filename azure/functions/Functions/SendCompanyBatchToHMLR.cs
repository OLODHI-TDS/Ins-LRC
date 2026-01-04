using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Azure.Communication.Email;
using Azure.Security.KeyVault.Secrets;
using ClosedXML.Excel;
using LandRegFunctions.Models;

namespace LandRegFunctions.Functions;

public class SendCompanyBatchToHMLR
{
    private readonly ILogger<SendCompanyBatchToHMLR> _logger;
    private readonly EmailClient _emailClient;
    private readonly SecretClient _secretClient;

    public SendCompanyBatchToHMLR(
        ILogger<SendCompanyBatchToHMLR> logger,
        EmailClient emailClient,
        SecretClient secretClient)
    {
        _logger = logger;
        _emailClient = emailClient;
        _secretClient = secretClient;
    }

    [Function("SendCompanyBatchToHMLR")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData req)
    {
        _logger.LogInformation("SendCompanyBatchToHMLR function triggered");

        try
        {
            // Parse request body
            var request = await req.ReadFromJsonAsync<CompanyBatchRequest>();
            if (request == null || request.Records.Count == 0)
            {
                return await CreateErrorResponse(req, HttpStatusCode.BadRequest,
                    "Invalid request: no records provided");
            }

            _logger.LogInformation("Processing batch {BatchName} with {Count} records",
                request.BatchName, request.Records.Count);

            // Generate Excel file
            byte[] excelBytes = GenerateHMLRExcel(request);
            _logger.LogInformation("Generated Excel file: {Size} bytes", excelBytes.Length);

            // Get email configuration from Key Vault
            var senderEmail = (await _secretClient.GetSecretAsync("acs-sender-email")).Value.Value;
            var recipientEmail = (await _secretClient.GetSecretAsync("hmlr-recipient-email")).Value.Value;

            _logger.LogInformation("Sending email from {Sender} to {Recipient}",
                senderEmail, recipientEmail);

            // Prepare email content
            var subject = $"TDS Land Registry Check - {request.BatchName} - {DateTime.UtcNow:yyyy-MM-dd}";
            var bodyHtml = GenerateEmailBody(request);
            var fileName = $"TDS_LandRegCheck_{request.BatchName}_{DateTime.UtcNow:yyyyMMdd_HHmmss}.xlsx";

            // Create email message with attachment
            var emailMessage = new EmailMessage(
                senderAddress: senderEmail,
                recipients: new EmailRecipients(new List<EmailAddress>
                {
                    new EmailAddress(recipientEmail)
                }),
                content: new EmailContent(subject)
                {
                    Html = bodyHtml
                });

            // Add Excel attachment
            var attachment = new EmailAttachment(
                name: fileName,
                contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                content: new BinaryData(excelBytes));
            emailMessage.Attachments.Add(attachment);

            // Send email
            var sendOperation = await _emailClient.SendAsync(
                Azure.WaitUntil.Completed,
                emailMessage);

            var messageId = sendOperation.Id;
            _logger.LogInformation("Email sent successfully. MessageId: {MessageId}", messageId);

            // Create success response
            var responseBody = new CompanyBatchResponse
            {
                Success = true,
                BatchId = request.BatchId,
                RecordsProcessed = request.Records.Count,
                EmailMessageId = messageId,
                SentAt = DateTime.UtcNow,
                RecipientEmail = recipientEmail
            };

            var response = req.CreateResponse(HttpStatusCode.OK);
            await response.WriteAsJsonAsync(responseBody);
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing company batch");
            return await CreateErrorResponse(req, HttpStatusCode.InternalServerError,
                $"Error sending batch: {ex.Message}");
        }
    }

    private byte[] GenerateHMLRExcel(CompanyBatchRequest request)
    {
        using var workbook = new XLWorkbook();
        var worksheet = workbook.Worksheets.Add("Land Registry Check");

        // Add headers (HMLR format)
        var headers = new[]
        {
            "CustomerRef",
            "Forename",
            "Surname",
            "Company Name Supplied",
            "Input Address one",
            "Input Address two",
            "Input Address three",
            "Input Address four",
            "Input Address five",
            "Input Postcode"
        };

        for (int i = 0; i < headers.Length; i++)
        {
            worksheet.Cell(1, i + 1).Value = headers[i];
            worksheet.Cell(1, i + 1).Style.Font.Bold = true;
            worksheet.Cell(1, i + 1).Style.Fill.BackgroundColor = XLColor.LightGray;
        }

        // Add data rows
        int row = 2;
        foreach (var record in request.Records)
        {
            worksheet.Cell(row, 1).Value = record.CustomerRef;
            worksheet.Cell(row, 2).Value = record.Forename;
            worksheet.Cell(row, 3).Value = record.Surname;
            worksheet.Cell(row, 4).Value = record.CompanyName;
            worksheet.Cell(row, 5).Value = record.Address1;
            worksheet.Cell(row, 6).Value = record.Address2;
            worksheet.Cell(row, 7).Value = record.Address3;
            worksheet.Cell(row, 8).Value = record.Address4;
            worksheet.Cell(row, 9).Value = record.Address5;
            worksheet.Cell(row, 10).Value = record.Postcode;
            row++;
        }

        // Auto-fit columns
        worksheet.Columns().AdjustToContents();

        // Convert to byte array
        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        return stream.ToArray();
    }

    private string GenerateEmailBody(CompanyBatchRequest request)
    {
        return $@"
<!DOCTYPE html>
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; }}
        .header {{ color: #333; }}
        .details {{ margin: 20px 0; }}
        .footer {{ color: #666; font-size: 12px; margin-top: 30px; }}
    </style>
</head>
<body>
    <h2 class='header'>Land Registry Ownership Verification Request</h2>

    <div class='details'>
        <p><strong>Organisation:</strong> The Dispute Service Ltd</p>
        <p><strong>Batch Reference:</strong> {request.BatchName}</p>
        <p><strong>Number of Records:</strong> {request.Records.Count}</p>
        <p><strong>Submission Date:</strong> {DateTime.UtcNow:dd MMMM yyyy HH:mm} UTC</p>
    </div>

    <p>Please find attached an Excel file containing company landlord records for ownership verification.</p>

    <p>Please process these records and return the results to the sender email address.</p>

    <div class='footer'>
        <p>This is an automated message from The Dispute Service Ltd compliance system.</p>
        <p>If you have any questions, please contact compliance@tdsgroup.uk</p>
    </div>
</body>
</html>";
    }

    private async Task<HttpResponseData> CreateErrorResponse(
        HttpRequestData req,
        HttpStatusCode statusCode,
        string errorMessage)
    {
        var response = req.CreateResponse(statusCode);
        await response.WriteAsJsonAsync(new CompanyBatchResponse
        {
            Success = false,
            ErrorMessage = errorMessage
        });
        return response;
    }
}
