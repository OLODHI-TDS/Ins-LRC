using System.Text.Json.Serialization;

namespace LandRegFunctions.Models;

/// <summary>
/// Represents a Land_Registry_Check__c record from Salesforce
/// </summary>
public class LandRegistryCheckRecord
{
    [JsonPropertyName("Id")]
    public string? Id { get; set; }

    [JsonPropertyName("Name")]
    public string? Name { get; set; }

    [JsonPropertyName("Landlord_ID__c")]
    public string? LandlordId { get; set; }

    [JsonPropertyName("Landlord_Name__c")]
    public string? LandlordName { get; set; }

    [JsonPropertyName("Property_Postcode__c")]
    public string? PropertyPostcode { get; set; }

    [JsonPropertyName("Status__c")]
    public string? Status { get; set; }

    [JsonPropertyName("Match_Type__c")]
    public string? MatchType { get; set; }

    [JsonPropertyName("Title_Number__c")]
    public string? TitleNumber { get; set; }

    [JsonPropertyName("Title_Deed_URL__c")]
    public string? TitleDeedUrl { get; set; }

    [JsonPropertyName("HMLR_Response_Date__c")]
    public DateTime? HMLRResponseDate { get; set; }

    [JsonPropertyName("Batch__c")]
    public string? BatchId { get; set; }
}

/// <summary>
/// Update payload for Land_Registry_Check__c record
/// </summary>
public class LandRegistryCheckUpdate
{
    [JsonPropertyName("Status__c")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Status { get; set; }

    [JsonPropertyName("Match_Type__c")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? MatchType { get; set; }

    [JsonPropertyName("Title_Number__c")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? TitleNumber { get; set; }

    [JsonPropertyName("Title_Deed_URL__c")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? TitleDeedUrl { get; set; }

    [JsonPropertyName("HMLR_Response_Date__c")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public DateTime? HMLRResponseDate { get; set; }
}
