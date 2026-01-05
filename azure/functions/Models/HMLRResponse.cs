namespace LandRegFunctions.Models;

/// <summary>
/// Represents a pending HMLR response email waiting to be paired
/// </summary>
public class PendingHMLREmail
{
    public string EmailId { get; set; } = string.Empty;
    public string Subject { get; set; } = string.Empty;
    public DateTime ReceivedDateTime { get; set; }
    public string FromAddress { get; set; } = string.Empty;
    public HMLREmailType EmailType { get; set; }
    public string? AttachmentName { get; set; }
    public string? TempBlobPath { get; set; }
}

public enum HMLREmailType
{
    ExcelResults,   // RPMSG with Excel spreadsheet
    TitleDeedsZip   // Normal email with ZIP of PDFs
}

/// <summary>
/// Paired HMLR response ready for processing
/// </summary>
public class HMLRResponsePair
{
    public PendingHMLREmail ExcelEmail { get; set; } = null!;
    public PendingHMLREmail ZipEmail { get; set; } = null!;
    public DateTime PairedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// A single row from the HMLR response Excel
/// </summary>
public class HMLRResponseRow
{
    // Original columns we sent
    public string CustomerRef { get; set; } = string.Empty;
    public string Forename { get; set; } = string.Empty;
    public string Surname { get; set; } = string.Empty;
    public string CompanyName { get; set; } = string.Empty;
    public string Address1 { get; set; } = string.Empty;
    public string Address2 { get; set; } = string.Empty;
    public string Address3 { get; set; } = string.Empty;
    public string Address4 { get; set; } = string.Empty;
    public string Address5 { get; set; } = string.Empty;
    public string Postcode { get; set; } = string.Empty;

    // HMLR response columns
    public string AddressMatchResult { get; set; } = string.Empty;
    public string TitleNumber { get; set; } = string.Empty;
    public string NameMatchResult { get; set; } = string.Empty;

    // Computed properties
    public bool IsAddressMatch => AddressMatchResult.Equals("Match", StringComparison.OrdinalIgnoreCase);
    public bool IsNameMatch => NameMatchResult.Equals("Match", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Determines the Salesforce status based on match results
    /// </summary>
    public string GetSalesforceStatus()
    {
        if (!IsAddressMatch)
            return "No Match";

        return IsNameMatch ? "Matched" : "Under Review";
    }

    /// <summary>
    /// Determines the match type for Salesforce
    /// </summary>
    public string GetMatchType()
    {
        if (!IsAddressMatch)
            return "No Property Match";

        return IsNameMatch ? "Property and Person Match" : "Property Only";
    }
}

/// <summary>
/// Result of processing an HMLR response
/// </summary>
public class HMLRProcessingResult
{
    public bool Success { get; set; }
    public string? ErrorMessage { get; set; }
    public int TotalRows { get; set; }
    public int MatchedRecords { get; set; }
    public int UnderReviewRecords { get; set; }
    public int NoMatchRecords { get; set; }
    public int SkippedRows { get; set; }
    public List<string> Errors { get; set; } = new();
    public DateTime ProcessedAt { get; set; } = DateTime.UtcNow;
    public DateTime EmailReceivedAt { get; set; }
}

/// <summary>
/// Record update to be sent to Salesforce
/// </summary>
public class SalesforceRecordUpdate
{
    /// <summary>
    /// Salesforce record ID (populated after query)
    /// </summary>
    public string RecordId { get; set; } = string.Empty;

    /// <summary>
    /// CustomerRef from HMLR response (used to match Salesforce record)
    /// </summary>
    public string CustomerRef { get; set; } = string.Empty;

    /// <summary>
    /// Postcode from HMLR response (used to match Salesforce record)
    /// </summary>
    public string Postcode { get; set; } = string.Empty;

    /// <summary>
    /// Status to set: Matched, Under Review, No Match
    /// </summary>
    public string Status { get; set; } = string.Empty;

    /// <summary>
    /// Match type: Property+Person Match, Property Only, No Property Match
    /// </summary>
    public string MatchType { get; set; } = string.Empty;

    /// <summary>
    /// Title number from HMLR
    /// </summary>
    public string? TitleNumber { get; set; }

    /// <summary>
    /// Blob storage path for title deed PDF
    /// </summary>
    public string? TitleDeedBlobPath { get; set; }

    /// <summary>
    /// URL to view title deed PDF (set after processing)
    /// </summary>
    public string? TitleDeedUrl { get; set; }

    /// <summary>
    /// When HMLR response was received
    /// </summary>
    public DateTime HMLRResponseDate { get; set; }
}
