namespace LandRegFunctions.Models;

/// <summary>
/// Configuration for mailbox monitoring
/// </summary>
public class MailboxSettings
{
    /// <summary>
    /// The email address to monitor for HMLR responses
    /// </summary>
    public string MailboxAddress { get; set; } = string.Empty;

    /// <summary>
    /// Known HMLR sender addresses to filter emails
    /// </summary>
    public static readonly string[] HMLRSenderAddresses = new[]
    {
        "data.services@mail.landregistry.gov.uk",
        "noreply@landregistry.gov.uk"
    };

    /// <summary>
    /// Time window (in hours) within which two emails are considered a pair
    /// </summary>
    public static readonly int PairingWindowHours = 12;

    /// <summary>
    /// Container name for temporary storage of pending emails
    /// </summary>
    public static readonly string PendingEmailsContainer = "pending-hmlr-emails";
}
