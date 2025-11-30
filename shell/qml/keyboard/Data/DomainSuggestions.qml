// Domain and Email Suggestion Engine
// Provides intelligent TLD and domain suggestions for URL/email contexts
import QtQuick

QtObject {
    id: domainSuggestions

    // Common TLDs (top-level domains) - ordered by popularity
    readonly property var commonTLDs: ["com", "org", "net", "edu", "gov", "co.uk", "co", "io", "app", "dev", "uk", "ca", "au", "de", "fr", "jp", "cn", "in", "br", "ru"]

    // Common email domains
    readonly property var emailDomains: ["gmail.com", "outlook.com", "yahoo.com", "hotmail.com", "icloud.com", "protonmail.com", "me.com", "live.com", "msn.com"]

    // Common URL prefixes
    readonly property var urlPrefixes: ["www.", "mail.", "blog.", "shop.", "m.", "api.", "dev.", "staging."]

    /**
     * Get domain suggestions based on current input
     * @param text - Current text being typed
     * @param isEmail - Whether we're in an email context
     * @returns Array of domain suggestions
     */
    function getSuggestions(text, isEmail) {
        if (!text || text.length === 0) {
            return [];
        }

        var suggestions = [];
        var lowerText = text.toLowerCase();

        // Email context
        if (isEmail) {
            // If user typed @ or text after @
            if (lowerText.indexOf("@") !== -1) {
                var parts = lowerText.split("@");
                if (parts.length === 2) {
                    var domain = parts[1];
                    // Suggest email domains that start with what user typed
                    for (var i = 0; i < emailDomains.length && suggestions.length < 3; i++) {
                        if (emailDomains[i].startsWith(domain) && emailDomains[i] !== domain) {
                            suggestions.push(parts[0] + "@" + emailDomains[i]);
                        }
                    }
                }
            } else
            // If no @ yet, suggest completing current word + @domain
            if (lowerText.length >= 2) {
                for (var j = 0; j < emailDomains.length && suggestions.length < 3; j++) {
                    suggestions.push(lowerText + "@" + emailDomains[j]);
                }
            }
        } else
        // URL context
        {
            // User typed a dot - suggest TLDs
            var lastDot = lowerText.lastIndexOf(".");
            if (lastDot !== -1) {
                var afterDot = lowerText.substring(lastDot + 1);

                // If user typed .c, suggest .com, .co, .co.uk, etc.
                for (var k = 0; k < commonTLDs.length && suggestions.length < 3; k++) {
                    if (commonTLDs[k].startsWith(afterDot) && commonTLDs[k] !== afterDot) {
                        var beforeDot = lowerText.substring(0, lastDot + 1);
                        suggestions.push(beforeDot + commonTLDs[k]);
                    }
                }
            } else
            // No dot yet - suggest adding .com, .org, etc.
            if (lowerText.length >= 2 && lowerText.indexOf("://") === -1) {
                for (var l = 0; l < Math.min(3, commonTLDs.length); l++) {
                    suggestions.push(lowerText + "." + commonTLDs[l]);
                }
            }
        }

        return suggestions;
    }

    /**
     * Check if we should show domain suggestions
     * @param text - Current text
     * @param isEmail - Email context
     * @param isUrl - URL context
     */
    function shouldShowDomainSuggestions(text, isEmail, isUrl) {
        if (!text || text.length === 0) {
            return false;
        }

        // Show for email if @ is present or text is long enough
        if (isEmail) {
            return text.indexOf("@") !== -1 || text.length >= 2;
        }

        // Show for URL if dot is present or text looks like domain
        if (isUrl) {
            return text.indexOf(".") !== -1 || (text.length >= 2 && text.indexOf("://") === -1);
        }

        return false;
    }
}
