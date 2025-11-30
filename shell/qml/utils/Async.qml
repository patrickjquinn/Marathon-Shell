pragma Singleton
import QtQuick

/**
 * Async - Promise-based async utilities for Marathon Shell
 *
 * Provides a clean Promise-like interface over Qt's signal-based async operations
 * using the AsyncFuture library.
 *
 * Example usage:
 *
 *   Async.promise(MarathonAppLoader.loadAppAsync(appId))
 *       .then((instance) => {
 *           Logger.info("App loaded:", instance.appName)
 *           return AppLifecycleManager.bringToForeground(appId)
 *       })
 *       .then(() => {
 *           Logger.info("App brought to foreground")
 *       })
 *       .fail((error) => {
 *           Logger.error("Failed to load app:", error)
 *           NotificationService.showError("Failed to load app")
 *       })
 */
QtObject {
    id: root

    /**
     * Create a promise from a QFuture or signal
     * This is a placeholder - actual implementation will use AsyncFuture C++ bridge
     */
    function promise(futureOrSignal) {
        return createPromise(futureOrSignal);
    }

    /**
     * Create a deferred promise that can be resolved/rejected manually
     */
    function deferred() {
        return createDeferred();
    }

    /**
     * Combine multiple promises into one
     */
    function all(promises) {
        return createAll(promises);
    }

    /**
     * Race multiple promises (first one wins)
     */
    function race(promises) {
        return createRace(promises);
    }

    /**
     * Internal: Create a promise object
     */
    function createPromise(futureOrSignal) {
        var callbacks = {
            thenCallbacks: [],
            failCallbacks: [],
            finallyCallbacks: []
        };

        var promiseObj = {
            then: function (callback) {
                callbacks.thenCallbacks.push(callback);
                return promiseObj;
            },
            fail: function (callback) {
                callbacks.failCallbacks.push(callback);
                return promiseObj;
            },
            finally: function (callback) {
                callbacks.finallyCallbacks.push(callback);
                return promiseObj;
            },
            cancel: function () {
                // Cancel the underlying future
                if (futureOrSignal && typeof futureOrSignal.cancel === 'function') {
                    futureOrSignal.cancel();
                }
            }
        };

        // Wire up the callbacks when future completes
        // This will be replaced with actual AsyncFuture C++ integration
        if (futureOrSignal && typeof futureOrSignal.finished === 'object') {
            futureOrSignal.finished.connect(function (result) {
                callbacks.thenCallbacks.forEach(cb => cb(result));
                callbacks.finallyCallbacks.forEach(cb => cb());
            });
        }

        if (futureOrSignal && typeof futureOrSignal.error === 'object') {
            futureOrSignal.error.connect(function (error) {
                callbacks.failCallbacks.forEach(cb => cb(error));
                callbacks.finallyCallbacks.forEach(cb => cb());
            });
        }

        return promiseObj;
    }

    /**
     * Internal: Create a deferred object
     */
    function createDeferred() {
        var callbacks = {
            thenCallbacks: [],
            failCallbacks: [],
            finallyCallbacks: []
        };

        var resolved = false;
        var rejected = false;
        var result = null;
        var error = null;

        return {
            promise: function () {
                return {
                    then: function (callback) {
                        if (resolved) {
                            callback(result);
                        } else {
                            callbacks.thenCallbacks.push(callback);
                        }
                        return this;
                    },
                    fail: function (callback) {
                        if (rejected) {
                            callback(error);
                        } else {
                            callbacks.failCallbacks.push(callback);
                        }
                        return this;
                    },
                    finally: function (callback) {
                        if (resolved || rejected) {
                            callback();
                        } else {
                            callbacks.finallyCallbacks.push(callback);
                        }
                        return this;
                    }
                };
            },
            resolve: function (value) {
                if (!resolved && !rejected) {
                    resolved = true;
                    result = value;
                    callbacks.thenCallbacks.forEach(cb => cb(value));
                    callbacks.finallyCallbacks.forEach(cb => cb());
                }
            },
            reject: function (err) {
                if (!resolved && !rejected) {
                    rejected = true;
                    error = err;
                    callbacks.failCallbacks.forEach(cb => cb(err));
                    callbacks.finallyCallbacks.forEach(cb => cb());
                }
            }
        };
    }

    /**
     * Internal: Combine multiple promises
     */
    function createAll(promises) {
        var deferred = createDeferred();
        var results = [];
        var completed = 0;
        var failed = false;

        if (promises.length === 0) {
            deferred.resolve([]);
            return deferred.promise();
        }

        promises.forEach(function (p, index) {
            p.then(function (result) {
                if (!failed) {
                    results[index] = result;
                    completed++;
                    if (completed === promises.length) {
                        deferred.resolve(results);
                    }
                }
            }).fail(function (error) {
                if (!failed) {
                    failed = true;
                    deferred.reject(error);
                }
            });
        });

        return deferred.promise();
    }

    /**
     * Internal: Race multiple promises
     */
    function createRace(promises) {
        var deferred = createDeferred();
        var settled = false;

        promises.forEach(function (p) {
            p.then(function (result) {
                if (!settled) {
                    settled = true;
                    deferred.resolve(result);
                }
            }).fail(function (error) {
                if (!settled) {
                    settled = true;
                    deferred.reject(error);
                }
            });
        });

        return deferred.promise();
    }
}
