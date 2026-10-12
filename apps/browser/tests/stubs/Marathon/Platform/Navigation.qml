pragma Singleton
import QtQml

QtObject {
    signal deepLinkRequested(string appId, string route, var params)
}
