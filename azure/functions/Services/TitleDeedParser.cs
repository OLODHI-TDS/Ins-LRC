using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using UglyToad.PdfPig;

namespace LandRegFunctions.Services;

/// <summary>
/// Extracts proprietor names from HMLR title deed PDFs
/// </summary>
public class TitleDeedParser
{
    private readonly ILogger<TitleDeedParser> _logger;

    // Regex to find PROPRIETOR entry - captures everything after "PROPRIETOR:" until end of sentence
    private static readonly Regex ProprietorRegex = new(
        @"PROPRIETOR:\s*(.+?)(?=\s*\d{1,2}\s+\(|\s*End of register|\s*C:\s*Charges Register|$)",
        RegexOptions.IgnoreCase | RegexOptions.Singleline | RegexOptions.Compiled);

    // Regex to extract name from proprietor text (handles "NAME of ADDRESS" pattern)
    private static readonly Regex NameOfAddressRegex = new(
        @"^(.+?)\s+of\s+\d",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    // Regex to strip company registration details
    private static readonly Regex CompanyRegRegex = new(
        @"\s*\([^)]*(?:Co\.|Regn|incorporated|OE ID|UK Regn)[^)]*\)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public TitleDeedParser(ILogger<TitleDeedParser> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Extract proprietor name(s) from a title deed PDF
    /// </summary>
    /// <param name="pdfBytes">PDF file content as byte array</param>
    /// <param name="titleNumber">Title number for logging</param>
    /// <returns>Extracted proprietor name(s) or null if not found</returns>
    public string? ExtractProprietorName(byte[] pdfBytes, string titleNumber)
    {
        try
        {
            using var document = PdfDocument.Open(pdfBytes);
            var fullText = string.Join(" ", document.GetPages().Select(p => p.Text));

            // Normalize whitespace
            fullText = Regex.Replace(fullText, @"\s+", " ");

            _logger.LogDebug("Extracted {Length} chars from PDF {TitleNumber}", fullText.Length, titleNumber);

            // Find the PROPRIETOR entry
            var match = ProprietorRegex.Match(fullText);
            if (!match.Success)
            {
                _logger.LogWarning("No PROPRIETOR entry found in {TitleNumber}", titleNumber);
                return null;
            }

            var proprietorText = match.Groups[1].Value.Trim();
            _logger.LogDebug("Raw proprietor text for {TitleNumber}: {Text}", titleNumber, proprietorText);

            // Extract names from the proprietor text
            var names = ExtractNamesFromProprietorText(proprietorText);

            if (string.IsNullOrWhiteSpace(names))
            {
                _logger.LogWarning("Could not extract names from proprietor text in {TitleNumber}", titleNumber);
                return null;
            }

            _logger.LogInformation("Extracted proprietor name for {TitleNumber}: {Name}", titleNumber, names);
            return names;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error extracting proprietor name from {TitleNumber}", titleNumber);
            return null;
        }
    }

    /// <summary>
    /// Extract clean names from proprietor text
    /// Handles patterns like:
    /// - "COMPANY NAME (Co. Regn. No. XXX) of address"
    /// - "PERSON NAME of address"
    /// - "PERSON1 and PERSON2 of address"
    /// - "PERSON1 of address1 and PERSON2 of address2"
    /// </summary>
    private string ExtractNamesFromProprietorText(string text)
    {
        // Check if this is a joint ownership with separate addresses
        // Pattern: "NAME1 of ADDRESS1 and NAME2 of ADDRESS2"
        if (ContainsMultipleOwnerAddresses(text))
        {
            return ExtractJointOwnersWithSeparateAddresses(text);
        }

        // Simple case: "NAME(S) of ADDRESS" - extract before " of " followed by address
        var nameMatch = NameOfAddressRegex.Match(text);
        if (nameMatch.Success)
        {
            var name = nameMatch.Groups[1].Value.Trim();
            return CleanProprietorName(name);
        }

        // Fallback: try to extract until first "of" followed by what looks like an address
        var ofIndex = FindAddressOfIndex(text);
        if (ofIndex > 0)
        {
            var name = text.Substring(0, ofIndex).Trim();
            return CleanProprietorName(name);
        }

        // Last resort: return cleaned full text (might include address)
        return CleanProprietorName(text);
    }

    /// <summary>
    /// Check if text contains multiple owners with separate addresses
    /// Pattern: "NAME of ADDRESS and NAME of ADDRESS"
    /// </summary>
    private static bool ContainsMultipleOwnerAddresses(string text)
    {
        // Look for pattern: "of [address] and [NAME]"
        // The "and" after an address indicates joint ownership with separate addresses
        return Regex.IsMatch(text, @"\s+of\s+[^,]+,.*\s+and\s+[A-Z]", RegexOptions.IgnoreCase);
    }

    /// <summary>
    /// Extract names from joint ownership with separate addresses
    /// "CAREY ANN HARRISON-ALLAN of Baycliffe Farm... and LAURA LINTERN of 32 Andrews Close..."
    /// → "CAREY ANN HARRISON-ALLAN and LAURA LINTERN"
    /// </summary>
    private string ExtractJointOwnersWithSeparateAddresses(string text)
    {
        var names = new List<string>();

        // Split by " and " where it's followed by an uppercase letter (start of name)
        var parts = Regex.Split(text, @"\s+and\s+(?=[A-Z])");

        foreach (var part in parts)
        {
            // For each part, extract the name before " of "
            var ofIndex = FindAddressOfIndex(part);
            if (ofIndex > 0)
            {
                var name = part.Substring(0, ofIndex).Trim();
                names.Add(CleanProprietorName(name));
            }
            else
            {
                // No "of" found, might be the full name
                names.Add(CleanProprietorName(part.Trim()));
            }
        }

        return string.Join(" and ", names.Where(n => !string.IsNullOrWhiteSpace(n)));
    }

    /// <summary>
    /// Find the index of " of " that precedes an address (not part of a name)
    /// </summary>
    private static int FindAddressOfIndex(string text)
    {
        // Find " of " followed by what looks like an address (number or building name)
        var match = Regex.Match(text, @"\s+of\s+(?=\d|[A-Z][a-z]+\s+(House|Farm|Building|Court|Lodge|Hall|Place|Gardens|Park|Road|Street|Avenue|Lane|Drive|Close|Way|Crescent))");
        return match.Success ? match.Index : -1;
    }

    /// <summary>
    /// Clean up proprietor name by removing company registration details
    /// </summary>
    private static string CleanProprietorName(string name)
    {
        // Remove company registration details in parentheses
        var cleaned = CompanyRegRegex.Replace(name, "");

        // Remove any trailing punctuation and extra spaces
        cleaned = cleaned.Trim().TrimEnd('.', ',');
        cleaned = Regex.Replace(cleaned, @"\s+", " ");

        return cleaned;
    }
}
