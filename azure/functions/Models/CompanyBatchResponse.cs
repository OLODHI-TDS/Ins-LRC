namespace LandRegFunctions.Models;

/// <summary>
/// Response returned to Salesforce after sending batch to HMLR
/// </summary>
public class CompanyBatchResponse
{
    public bool Success { get; set; }
    public string BatchId { get; set; } = string.Empty;
    public int RecordsProcessed { get; set; }
    public string? EmailMessageId { get; set; }
    public DateTime? SentAt { get; set; }
    public string? ErrorMessage { get; set; }
    public string? RecipientEmail { get; set; }
}
