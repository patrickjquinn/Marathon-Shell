// Marathon Virtual Keyboard - Long Press Handler
// Handles long-press for alternate characters
import QtQuick

Item {
    id: longPressHandler

    // Alternate character mappings
    readonly property var alternates: ({
            "a": ["à", "á", "â", "ã", "ä", "å", "æ", "ā"],
            "e": ["è", "é", "ê", "ë", "ē", "ė", "ę"],
            "i": ["ì", "í", "î", "ï", "ī", "į"],
            "o": ["ò", "ó", "ô", "õ", "ö", "ø", "ō", "œ"],
            "u": ["ù", "ú", "û", "ü", "ū"],
            "c": ["ç", "ć", "č"],
            "n": ["ñ", "ń"],
            "s": ["ś", "š", "ş", "ß"],
            "y": ["ý", "ÿ"],
            "z": ["ź", "ż", "ž"],
            "d": ["ð"],
            "t": ["þ"],
            "l": ["ł"],
            "0": ["°", "∅"],
            "1": ["¹", "½", "⅓", "¼"],
            "2": ["²", "⅔"],
            "3": ["³", "¾"],
            "?": ["¿"],
            "!": ["¡"],
            "$": ["€", "£", "¥", "¢", "₹"],
            "-": ["–", "—", "•"],
            "+": ["±"],
            "=": ["≠", "≈"],
            "<": ["≤", "«"],
            ">": ["≥", "»"],
            "/": ["÷"],
            "*": ["×"],
            "%": ["‰"]
        })

    signal alternateSelected(string character)

    // Get alternates for a character
    function getAlternates(character) {
        var lowerChar = character.toLowerCase();
        if (alternates.hasOwnProperty(lowerChar)) {
            return alternates[lowerChar];
        }
        return [];
    }

    // Check if character has alternates
    function hasAlternates(character) {
        var lowerChar = character.toLowerCase();
        return alternates.hasOwnProperty(lowerChar);
    }
}
