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

    // Regex to find PROPRIETOR entry
    private static readonly Regex ProprietorRegex = new(
        @"PROPRIETOR:\s*(.+?)(?=\s*\d{1,2}\s+\(|\s*End of register|\s*C:\s*Charges Register|$)",
        RegexOptions.IgnoreCase | RegexOptions.Singleline | RegexOptions.Compiled);

    // Regex to strip company registration details
    private static readonly Regex CompanyRegRegex = new(
        @"\s*\([^)]*(?:Co\.|Regn|incorporated|OE ID|UK Regn)[^)]*\)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    // UK Postcode pattern (used to detect addresses)
    private static readonly Regex UKPostcodeRegex = new(
        @"[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    // Pattern for "care of" which always indicates address follows
    private static readonly Regex CareOfRegex = new(
        @"\s+care\s*of\s+",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    // Common address/location keywords that indicate start of address
    private static readonly HashSet<string> AddressKeywords = new(StringComparer.OrdinalIgnoreCase)
    {
        // Building types
        "house", "farm", "building", "court", "lodge", "hall", "place", "gardens",
        "park", "mansion", "mansions", "tower", "towers", "apartments", "villas",
        "chambers", "cottage", "cottages", "villa", "grange", "manor", "castle",
        "centre", "center", "office", "offices", "suite", "unit", "flat", "flats",
        // Street types
        "road", "street", "avenue", "lane", "drive", "close", "way", "crescent",
        "grove", "terrace", "square", "mews", "row", "walk", "rise",
        "hill", "green", "meadow", "fields", "view", "parade", "circus", "yard",
        // Major UK cities and areas
        "london", "manchester", "birmingham", "leeds", "liverpool", "bristol",
        "sheffield", "newcastle", "nottingham", "southampton", "portsmouth",
        "brighton", "edinburgh", "glasgow", "cardiff", "belfast", "surrey",
        "essex", "kent", "sussex", "middlesex", "hertfordshire", "hampshire",
        "doncaster", "epsom", "dartford", "bridgwater"
    };

    public TitleDeedParser(ILogger<TitleDeedParser> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Extract proprietor name(s) from a title deed PDF
    /// </summary>
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
    /// </summary>
    private string ExtractNamesFromProprietorText(string text)
    {
        // Count " of " occurrences and check for " and " patterns
        var ofCount = Regex.Matches(text, @"\s+of\s+", RegexOptions.IgnoreCase).Count;
        var andMatches = Regex.Matches(text, @"\s+and\s+(?=[A-Z])", RegexOptions.IgnoreCase);

        // Multiple owners with separate addresses: "NAME1 of ADDR1 and NAME2 of ADDR2"
        if (ofCount > 1 && andMatches.Count > 0)
        {
            var names = new List<string>();
            var parts = Regex.Split(text, @"\s+and\s+(?=[A-Z])");

            foreach (var part in parts)
            {
                var name = ExtractSingleName(part);
                if (!string.IsNullOrWhiteSpace(name))
                {
                    names.Add(name);
                }
            }

            if (names.Count > 0)
            {
                return string.Join(" and ", names);
            }
        }

        // Joint owners sharing one address: "NAME1 and NAME2 of ADDRESS"
        if (andMatches.Count > 0 && ofCount == 1)
        {
            var ofMatch = Regex.Match(text, @"\s+of\s+", RegexOptions.IgnoreCase);
            if (ofMatch.Success)
            {
                var firstAnd = andMatches[0];
                if (firstAnd.Index < ofMatch.Index)
                {
                    // Joint owners - extract everything before " of "
                    var addressStart = FindAddressStart(text);
                    if (addressStart > 0)
                    {
                        var namesPart = text.Substring(0, addressStart).Trim();
                        return CleanProprietorName(namesPart);
                    }
                }
            }
        }

        // Single owner case
        return ExtractSingleName(text);
    }

    /// <summary>
    /// Extract a single proprietor name from text, stripping address
    /// </summary>
    private string ExtractSingleName(string text)
    {
        var addressStart = FindAddressStart(text);

        string name;
        if (addressStart > 0)
        {
            name = text.Substring(0, addressStart).Trim();
        }
        else
        {
            name = text.Trim();
        }

        return CleanProprietorName(name);
    }

    /// <summary>
    /// Find where the address starts in the proprietor text.
    /// Returns the index where the name ends (before address), or -1 if no address found.
    /// </summary>
    private int FindAddressStart(string text)
    {
        // 1. Check for "care of" - everything before it is the name
        var careOfMatch = CareOfRegex.Match(text);
        if (careOfMatch.Success)
        {
            return careOfMatch.Index;
        }

        // 2. Find all occurrences of " of " and check what follows
        var ofMatches = Regex.Matches(text, @"\s+of\s+", RegexOptions.IgnoreCase);

        foreach (Match match in ofMatches)
        {
            var afterOf = text.Substring(match.Index + match.Length);

            // Check if " of " is followed by a number (street number)
            if (afterOf.Length > 0 && char.IsDigit(afterOf[0]))
            {
                return match.Index;
            }

            // Check for postcode in the following text (next ~100 chars)
            var checkLength = Math.Min(100, afterOf.Length);
            var checkText = afterOf.Substring(0, checkLength);

            if (UKPostcodeRegex.IsMatch(checkText))
            {
                return match.Index;
            }

            // Check for address keywords in the following text
            foreach (var keyword in AddressKeywords)
            {
                if (Regex.IsMatch(checkText, @"\b" + Regex.Escape(keyword) + @"\b", RegexOptions.IgnoreCase))
                {
                    return match.Index;
                }
            }
        }

        // 3. Check if there's a postcode anywhere - find where address likely starts
        var postcodeMatch = UKPostcodeRegex.Match(text);
        if (postcodeMatch.Success)
        {
            // Work backwards from postcode to find " of "
            var textBeforePostcode = text.Substring(0, postcodeMatch.Index);
            var lastOf = textBeforePostcode.LastIndexOf(" of ", StringComparison.OrdinalIgnoreCase);
            if (lastOf > 0)
            {
                return lastOf;
            }
        }

        return -1;
    }

    /// <summary>
    /// Clean up proprietor name by removing company registration details and artifacts
    /// </summary>
    private static string CleanProprietorName(string name)
    {
        // Remove company registration details in parentheses
        var cleaned = CompanyRegRegex.Replace(name, "");

        // Remove any trailing punctuation and extra spaces
        cleaned = cleaned.Trim().TrimEnd('.', ',', ';', ':');
        cleaned = Regex.Replace(cleaned, @"\s+", " ");

        // Remove trailing "of" if present (artifact from splitting)
        cleaned = Regex.Replace(cleaned, @"\s+of\s*$", "", RegexOptions.IgnoreCase);

        return cleaned.Trim();
    }
}
