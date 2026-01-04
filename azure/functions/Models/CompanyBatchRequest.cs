namespace LandRegFunctions.Models;

/// <summary>
/// Request payload from Salesforce for sending company landlord batch to HMLR
/// </summary>
public class CompanyBatchRequest
{
    public string BatchId { get; set; } = string.Empty;
    public string BatchName { get; set; } = string.Empty;
    public List<CompanyLandlordRecord> Records { get; set; } = new();
}

/// <summary>
/// Individual company landlord record for HMLR submission
/// </summary>
public class CompanyLandlordRecord
{
    public string RecordId { get; set; } = string.Empty;
    public string CustomerRef { get; set; } = string.Empty;
    public string CompanyName { get; set; } = string.Empty;
    public string Forename { get; set; } = string.Empty;
    public string Surname { get; set; } = string.Empty;
    public string Address1 { get; set; } = string.Empty;
    public string Address2 { get; set; } = string.Empty;
    public string Address3 { get; set; } = string.Empty;
    public string Address4 { get; set; } = string.Empty;
    public string Address5 { get; set; } = string.Empty;
    public string Postcode { get; set; } = string.Empty;
}
