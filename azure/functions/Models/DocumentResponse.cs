namespace LandRegFunctions.Models;

/// <summary>
/// Response from document upload
/// </summary>
public class DocumentUploadResponse
{
    /// <summary>
    /// Whether the upload succeeded
    /// </summary>
    public bool Success { get; set; }

    /// <summary>
    /// Blob path in storage (e.g., "batch-id/record-id/title-number.pdf")
    /// </summary>
    public string? BlobPath { get; set; }

    /// <summary>
    /// Full blob URL (without SAS token)
    /// </summary>
    public string? BlobUrl { get; set; }

    /// <summary>
    /// File size in bytes
    /// </summary>
    public long? FileSizeBytes { get; set; }

    /// <summary>
    /// When the document was uploaded
    /// </summary>
    public DateTime? UploadedAt { get; set; }

    /// <summary>
    /// Error message if failed
    /// </summary>
    public string? ErrorMessage { get; set; }
}

/// <summary>
/// Response with SAS URL for viewing document
/// </summary>
public class DocumentAccessResponse
{
    /// <summary>
    /// Whether the request succeeded
    /// </summary>
    public bool Success { get; set; }

    /// <summary>
    /// SAS URL for viewing the document (time-limited)
    /// </summary>
    public string? SasUrl { get; set; }

    /// <summary>
    /// Blob path in storage
    /// </summary>
    public string? BlobPath { get; set; }

    /// <summary>
    /// When the SAS URL expires
    /// </summary>
    public DateTime? ExpiresAt { get; set; }

    /// <summary>
    /// Error message if failed
    /// </summary>
    public string? ErrorMessage { get; set; }
}

/// <summary>
/// Response for listing documents
/// </summary>
public class DocumentListResponse
{
    /// <summary>
    /// Whether the request succeeded
    /// </summary>
    public bool Success { get; set; }

    /// <summary>
    /// List of documents
    /// </summary>
    public List<DocumentInfo> Documents { get; set; } = new();

    /// <summary>
    /// Error message if failed
    /// </summary>
    public string? ErrorMessage { get; set; }
}

/// <summary>
/// Information about a stored document
/// </summary>
public class DocumentInfo
{
    /// <summary>
    /// Blob path in storage
    /// </summary>
    public string BlobPath { get; set; } = string.Empty;

    /// <summary>
    /// File name
    /// </summary>
    public string FileName { get; set; } = string.Empty;

    /// <summary>
    /// File size in bytes
    /// </summary>
    public long FileSizeBytes { get; set; }

    /// <summary>
    /// When the document was uploaded
    /// </summary>
    public DateTime? UploadedAt { get; set; }

    /// <summary>
    /// Content type
    /// </summary>
    public string ContentType { get; set; } = "application/pdf";
}
