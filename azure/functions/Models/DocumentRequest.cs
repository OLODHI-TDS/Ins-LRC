namespace LandRegFunctions.Models;

/// <summary>
/// Request to upload a document to blob storage
/// </summary>
public class DocumentUploadRequest
{
    /// <summary>
    /// Salesforce Batch ID (Land_Registry_Batch__c.Id)
    /// </summary>
    public string BatchId { get; set; } = string.Empty;

    /// <summary>
    /// Salesforce Check Record ID (Land_Registry_Check__c.Id)
    /// </summary>
    public string RecordId { get; set; } = string.Empty;

    /// <summary>
    /// HMLR Title Number (e.g., "NGL123456")
    /// </summary>
    public string TitleNumber { get; set; } = string.Empty;

    /// <summary>
    /// Base64-encoded PDF content
    /// </summary>
    public string DocumentBase64 { get; set; } = string.Empty;

    /// <summary>
    /// Original filename (optional)
    /// </summary>
    public string? FileName { get; set; }

    /// <summary>
    /// Content type (defaults to application/pdf)
    /// </summary>
    public string ContentType { get; set; } = "application/pdf";
}

/// <summary>
/// Request to get a SAS URL for viewing a document
/// </summary>
public class DocumentAccessRequest
{
    /// <summary>
    /// Full blob path (e.g., "batch-id/record-id/title-number.pdf")
    /// </summary>
    public string? BlobPath { get; set; }

    /// <summary>
    /// Alternative: Salesforce Batch ID
    /// </summary>
    public string? BatchId { get; set; }

    /// <summary>
    /// Alternative: Salesforce Check Record ID
    /// </summary>
    public string? RecordId { get; set; }

    /// <summary>
    /// Alternative: Title Number
    /// </summary>
    public string? TitleNumber { get; set; }

    /// <summary>
    /// SAS URL expiry in minutes (default: 60)
    /// </summary>
    public int ExpiryMinutes { get; set; } = 60;
}
