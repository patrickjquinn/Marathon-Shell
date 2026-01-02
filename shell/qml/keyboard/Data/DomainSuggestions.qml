import QtQuick

QtObject {
    id: domainSuggestions

    readonly property var commonTLDs: ["com", "org", "net", "edu", "gov", "co.uk", "co", "io", "app", "dev", "uk", "ca", "au", "de", "fr", "jp", "cn", "in", "br", "ru"]
    readonly property var emailDomains: ["gmail.com", "outlook.com", "yahoo.com", "hotmail.com", "icloud.com", "protonmail.com", "me.com", "live.com", "msn.com"]
    readonly property var urlPrefixes: ["www.", "mail.", "blog.", "shop.", "m.", "api.", "dev.", "staging."]

    function getSuggestions(text, isEmail) {
        if (!text || text.length === 0)
            return [];

        var suggestions = [];
        var lowerText = text.toLowerCase();
        if (isEmail) {
            if (lowerText.indexOf("@") !== -1) {
                var parts = lowerText.split("@");
                if (parts.length === 2) {
                    var domain = parts[1];
                    for (var i = 0; i < emailDomains.length && suggestions.length < 3; i++) {
                        if (emailDomains[i].startsWith(domain) && emailDomains[i] !== domain)
                            suggestions.push(parts[0] + "@" + emailDomains[i]);
                    }
                }
            } else if (lowerText.length >= 2) {
                for (var j = 0; j < emailDomains.length && suggestions.length < 3; j++)
                    suggestions.push(lowerText + "@" + emailDomains[j]);
            }
        } else {
            var lastDot = lowerText.lastIndexOf(".");
            if (lastDot !== -1) {
                var afterDot = lowerText.substring(lastDot + 1);
                for (var k = 0; k < commonTLDs.length && suggestions.length < 3; k++) {
                    if (commonTLDs[k].startsWith(afterDot) && commonTLDs[k] !== afterDot) {
                        var beforeDot = lowerText.substring(0, lastDot + 1);
                        suggestions.push(beforeDot + commonTLDs[k]);
                    }
                }
            } else if (lowerText.length >= 2 && lowerText.indexOf("://") === -1) {
                for (var l = 0; l < Math.min(3, commonTLDs.length); l++)
                    suggestions.push(lowerText + "." + commonTLDs[l]);
            }
        }
        return suggestions;
    }

    function shouldShowDomainSuggestions(text, isEmail, isUrl) {
        if (!text || text.length === 0)
            return false;

        if (isEmail)
            return text.indexOf("@") !== -1 || text.length >= 2;

        if (isUrl)
            return text.indexOf(".") !== -1 || (text.length >= 2 && text.indexOf("://") === -1);

        return false;
    }
}
