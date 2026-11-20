pragma Singleton
import QtQml

QtObject {
    property var results: []
    property var recentSearches: []
    function search(query) {
        return results;
    }
    function addToRecentSearches(query) {
    }
    function clearRecentSearches() {
    }
}
