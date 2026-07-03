## AsyncFuture - Use QFuture like a Promise object
![GitHub Workflow Status](https://github.com/vpicaver/asyncfuture/actions/workflows/linux_build_and_test.yml/badge.svg)

![GitHub Workflow Status](https://github.com/vpicaver/asyncfuture/actions/workflows/windows_build_and_test.yml/badge.svg)


AsyncFuture is a header only library tested using Qt 5.15 and Qt 6.2 or later.

QFuture is used together with QtConcurrent to represent the result of an asynchronous computation. It is a powerful component for multi-thread programming. But its usage is limited to the result of threads, it doesn't work with the asynchronous signal emitted by QObject. And it is a bit trouble to setup the listener function via QFutureWatcher.

AsyncFuture is designed to enhance the function to offer a better way to use it for asynchronous programming. It provides a Promise object like interface. This project is inspired by AsynQt and RxCpp.

Reference Articles
------------------

1. [Multithreading Programming with Future & Promise – E-Fever – Medium](https://medium.com/e-fever/multithreading-programming-with-future-promise-2d35e13b9404)
1. [AsyncFuture Cookbook 1 — Calling QtConcurrent::mapped within the run function](https://medium.com/e-fever/asyncfuture-cookbook-1-calling-qtconcurrent-mapped-within-the-run-function-ba58d523a0ce)

Including it into your project
==============================

### CMake
    add_subdirectory(asyncfuture)
    target_link_libraries(MyLib PRIVATE asyncfuture)
### QBS
    references: [ "asyncfuture/asyncfuture.qbs" ]
    Application {
        Depends { name: "asyncfuture" }
    }

### QMake
    include(asyncfuture/asyncfuture.pri)


Features
========

 1. Convert a signal from QObject into a QFuture object
 2. Combine multiple futures with different type into a single future object
 3. Use QFuture like a Promise object
 4. Chainable Callback - Advanced multi-threading programming model
 5. Automatic future unwrapping
 6. Full chain cancellation propagation
 7. Automatic progress accumulation

**1. Convert a signal from QObject into a QFuture object**

```c++

#include "asyncfuture.h"
using namespace AsyncFuture;

// Convert a signal from QObject into a QFuture object

QFuture<void> future = observe(timer, &QTimer::timeout).future();

/* Listen from the future without using QFutureWatcher<T>*/
observe(future).subscribe([]() {
    // onCompleted. It is invoked when the observed future is finished successfully
    qDebug() << "onCompleted";
},[]() {
    // onCanceled
    qDebug() << "onCancel";
});

```

**2. Combine multiple futures with different type into a single future object**

```c++
/* Combine multiple futures with different type into a single future */

QFuture<QImage> f1 = QtConcurrent::run(readImage, QString("image.jpg"));

QFuture<void> f2 = observe(timer, &QTimer::timeout).future();

QFuture<QImage> result = (combine() << f1 << f2).subscribe([=](){
    // Read an image but do not return before timeout
    return f1.result();
}).future();

QCOMPARE(result.progressMaximum(), 2); // Added since v0.4.1

```

**3. Use QFuture like a Promise object**

Create a QFuture then complete / cancel it by yourself.

```c++
// Complete / cancel a future on your own choice
auto d = deferred<bool>();

d.subscribe([]() {
    qDebug() << "onCompleted";
}, []() {
    qDebug() << "onCancel";
});

d.complete(true); // or d.cancel();

QCOMPARE(d.future().isFinished(), true);
QCOMPARE(d.future().isCanceled(), false);

```

Complete / cancel a future according to another future object.


```c++
// Complete / cancel a future according to another future object.

auto d = deferred<void>();

d.complete(QtConcurrent::run(timeout));

QCOMPARE(d.future().isFinished(), false);
QCOMPARE(d.future().isCanceled(), false);

```

Read a file. If timeout, cancel it.

```c++

auto timeout = observe(timer, &QTimer::timeout).future();

auto defer = deferred<QString>();

defer.complete(QtConcurrent::run(readFileworker, fileName));
defer.cancel(timeout);

return defer.future();
```

**4. Chainable Callback - Advanced multi-threading programming model**

Futures can be chained into a sequence of process. And represented by a single future object.

```c++
/* Start a thread and process its result in main thread */

QFuture<QImage> readImage(const QString& file) {

    auto readImageWorker = [=]() {
        QImage image;
        image.read(file);
        return image;
    };
    
    auto updateCache = [&](QImage image) {
        m_cache[file] = image;
        return image;
    };

    QFuture<QImage> reading = QtConcurrent::run(readImageWorker));
    return observe(reading).subscribe(updateCache).future();   
}

// Read image by a thread, when it is ready, run the updateCache function
// in the main thread.
// And it return another QFuture to represent the final result.

```

```c++
/* Start a thread and process its result in main thread, then start another thread. */

QFuture<int> f1 = QtConcurrent::mapped(input, mapFunc);

QFuture<int> f2 = observe(f1).subscribe([=](QFuture<int> future) {
    // You may use QFuture as the input argument of your callback function
    // It will be set to the observed future object. So that you may obtain
    // the value of results()

    qDebug() << future.results();

    // Return another QFuture is possible.
    return QtConcurrent::run(reducerFunc, future.results());
}).future();

// f2 is constructed before the QtConcurrent::run statement
// But its value is equal to the result of reducerFunc

```


More examples are available at : [asyncfuture/example.cpp at master · vpicaver/asyncfuture](https://github.com/vpicaver/asyncfuture/blob/master/tests/asyncfutureunittests/example.cpp)

Installation
=============

AsyncFuture is a single header library. You could just download the `asyncfuture.h` in your source tree or install it via qpm

    qpm install async.future.pri

or

    wget https://raw.githubusercontent.com/vpicaver/asyncfuture/master/asyncfuture.h

API
===

AsyncFuture::observe(QObject* object, PointerToMemberFunc signal)
-------------------

This function creates an Observable&lt;ARG&gt; object which contains a future to represent the result of the signal. You could obtain the future by the future() method. And observe the result by subscribe() / context() methods

The ARG type is equal to the first parameter of the signal. If the signal does not contain any argument, ARG will be void. Note that having more than one argument may result in a syntax error.

```c++
QFuture<void> f1 = observe(timer, &QTimer::timeout).future();
QFuture<bool> f2 = observe(button, &QAbstractButton::toggled).future();
```

To support signals with multiple arguments, use a AsyncFuture::deferred, for example:

```c++
auto proc = QSharedPointer<QProcess>(new QProcess());

struct Finished {
    int exitCode = -1;
    QProcess::ExitStatus status = QProcess::CrashExit;
};

auto deferred = AsyncFuture::deferred<Finished>();
QObject::connect(proc.get(), QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                 [&](int code, QProcess::ExitStatus status) {
    //Signal that the deferred is done
    deferred.complete({code, status});
});

proc->start(QString("ls"), QStringList());
```


See [Observable`<T>`](#observablet)

AsyncFuture::observe(object, SIGNAL(signal))
----------------------

This function creates an `Observable<QVariant>` object which contains a future to represent the result of the signal. You could obtain the future by the future() method. And observe the result by subscribe() / context() methods. The result of the future is equal to the first parameter of the signal.

```c++
QFuture<QVariant> future = observe(timer, SIGNAL(timeout()).future();
```

See [Observable`<T>`](#observablet)

AsyncFuture::observe(QFuture&lt;T&gt; future)
-------------

This function creates an Observable&lt;T&gt; object which provides an interface for observing the input future. See [Observable`<T>`](#observablet)

```c++
// Convert a signal from QObject into QFuture
QFuture<bool> future = observe(button, &QAbstractButton::toggled).future();


// Listen from the future without using QFutureWatcher<T>
observe(future).subscribe([](bool toggled) {
    // onCompleted. It is invoked when the observed future is finished successfully
    qDebug() << "onCompleted";
},[]() {
    // onCanceled
    qDebug() << "onCancel";
});
```

AsyncFuture::observe(QFuture&lt;QFuture&lt;T&gt;T&gt; future)
-----

This function creates an Observable<T> object which provides an interface for observing the input future.  That is designed to handle following use-case:

```
QFuture<QImage> readImagesFromFolder(const QString& folder) {

    auto worker = [=]() {
        // Read files from a directory in a thread
        QStringList files = findImageFiles(folder);

        // Concurrent image reader
        return QtConcurrent::mapped(files, readImage);
    };

    auto future = QtConcurrent::run(worker); // The type of future is QFuture<QFuture<QImage>>

    auto defer = AsyncFuture::deferred<QImage>();

    // defer object track the input future. It will emit "started" and `progressValueChanged` according to the status of the future of "QtConcurrent::mapped"
    defer.complete(future);
    return defer.future();
}
```

See [Observable`<T>`](#observablet)



AsyncFuture::combine(CombinatorMode mode = FailFast)
------------

This function creates a Combinator object (inherit `Observable<void>`) for combining multiple future objects with different type into a single future.

For example:

```c++

QFuture<QImage> f1 = QtConcurrent::run(readImage, QString("image.jpg"));
QFuture<void> f2 = observe(timer, &QTimer::timeout).future();

auto combinator = combine(AllSettled) << f1 << f2;

QFuture<QImage> result = combinator.subscribe([=](){
    // Read an image but do not return before timeout
    return f1.result();
}).future();

QCOMPARE(combinator.progressMaximum, 2);
```

Once all the observed futures finished, the contained future will be finished too.  And it will be cancelled immediately if any one of the observed future is cancelled in fail fast mode. In case you want the cancellation take place after all the futures finished, you should set mode to `AsyncFuture::AllSettled`.

Since v0.4.1, the `progressValue` and `progressMaximum` of the obtained future will be set.

Since v0.3.6, you may assign a deferred object to Combinator directly.

Example 

```
QFuture<QImage> f1 = QtConcurrent::run(readImage, QString("image.jpg"));
auto defer = deferred<void>();

QFuture<QImage> result = (combine(AllSettled) << f1 << defer).subscribe([=](){
    // Read an image but do not return before the deferred is completed
    return f1.result();
}).future();
```

AsyncFuture::deferred&lt;T&gt;()
----------

The deferred() function return a Deferred object that allows you to set QFuture completed/cancelled manually. 

```c++
auto d = deferred<bool>();

d.subscribe([]() {
    qDebug() << "onCompleted";
}, []() {
    qDebug() << "onCancel";
});

d.complete(true); // or d.cancel();
```

See [`Deferred<T>`](#deferredt)

![AsyncFuture Class Diagram](https://raw.githubusercontent.com/benlau/junkcode/master/docs/AsyncFuture%20Class%20Diagram.png)

Observable&lt;T&gt;
------------

Observable&lt;T&gt; is a chainable utility class for observing a QFuture object. It is created by the observe() function. It can register multiple callbacks to be triggered in different situations. And that will create a new Observable&lt;T&gt; / QFuture object to represent the result of the callback function. It may even call QtConcurrent::run() within the callback function to run the funciton in another thread. Therefore, it could create a more complex/flexible workflow.

```
QFuture<int> future

Observable<int> observable1 = AsyncFuture::observe(future); 
// or
auto observable2 = AsyncFuture::observe(future); 
```
**QFuture&lt;T&gt; Observable&lt;T&gt;::future()**

Obtain the QFuture object to represent the result.

**Observable&lt;T&gt; Observable&lt;T&gt;::subscribe(Completed onCompleted, Canceled onCanceled)**

    Observable<T> Observable<T>::subscribe(Completed onCompleted);
    Observable<T> Observable<T>::subscribe(Completed onCompleted, Canceled onCanceled);

Register a onCompleted and/or onCanceled callback to the observed QFuture object. Unlike the context() function, the callbacks will be triggered on the main thread. The return value is an `Observable<R>` object where R is the return type of the onCompleted callback.

Remarks: Before v0.3.2, the callback will be executed in the current thread.

See [Subscribe Callback Function](#subscribe-callback-funcion)

Example:

```c++
QFuture<bool> future = observe(button, &QAbstractButton::toggled).future();

// Listen from the future without using QFutureWatcher<T>
observe(future).subscribe([](bool toggled) {
    // onCompleted. It is invoked when the observed future is finished successfully
    qDebug() << "onCompleted";
},[]() {
    // onCanceled
    qDebug() << "onCancel";
});

```

**Observable&lt;R&gt; Observable&lt;T&gt;::context(QObject&#42; contextObject, Completed onCompleted, Cancel onCanceled)**

*This API is for advanced users only*

Add a callback function that listens to the finished and canceled signals from the observing QFuture object.

The callback is invoked in the thread of the context object. In case the context object is destroyed before the finished signal, the callback functions (onCompleted and onCanceled) won't be triggered and the returned Observable object will cancel its future.

Note: An event loop, must be excuting on the the contextObject->thread() for nested observe().context() calls to work.
Threads on the QThreadPool, generally don't have a QEventLoop executing, so manually creating and calling QEventLoop is
necessary. For example:

```c++
auto worker = [&]() {
    auto localTimeout = [](int sleepTime) {
        return QtConcurrent::run([sleepTime]() {
            QThread::currentThread()->msleep(sleepTime);
        });
    };

    QEventLoop loop;

    auto context = QSharedPointer<QObject>::create();

    QThread* workerThread = QThread::currentThread();

    observe(localTimeout(50)).context(context.data(), [localTimeout, context]() {
        qDebug() << "First time localTimeout() finished
        return localTimeout(50);
    }).context(context.data(), [context, &called, workerThread, &loop]() {
        qDebug() << "Second time localTimeout() finished
        loop.quit();
    });

    loop.exec();
};

QtConcurrent::run(worker);

```

The return value is an `Observable<R>` object where R is the return type of the onCompleted callback.

```c++

auto validator = [](QImage input) -> bool {
   /* A dummy function. Return true for any case. */
   return true;
};

QFuture<QImage> reading = QtConcurrent::run(readImage, QString("image.jpg"));

QFuture<bool> validating = observe(reading).context(contextObject, validator).future();
```

In the above example, the result of `validating` is supposed to be true. However, if the `contextObject` is destroyed before `reading` future finished, it will be cancelled and the result will become undefined.

**void Observable&lt;T&gt;::onProgress(Functor callback)**

Listens the `progressValueChanged` and `progressRangeChanged` signal from the observed future then trigger the callback. The callback function may return nothing or a boolean value. If the boolean value is false, it will remove the listener such that the callback will not be  triggered anymore.

Example

```c++
QFuture<int> future = QtConcurrent::mapped(input, workerFunction);

AsyncFuture::observe(future).onProgress([=]() -> bool {
    qDebug() << future.progressValue();
    return true;
});

// or

AsyncFuture::observe(future).onProgress([=]() -> void {
    qDebug() << future.progressValue();
});
```

Added since v0.3.6.4

**Chained Progress**

`observe().subscribe().future()` future will report progress accordingly to the underlying future chain. When watching the final future in the chain, `progressRangeChanged` may be be updated multiple times as futures in the chain update their individual `progressRangeChanged`. When visualizing final future's progress in a progress bar, progressValue may appear to go in reverse, as progressRange increases. `progressValueChanged` will never go down as execution continues. 

Example:

```{c++}
    QVector<int> ints(100);
    std::iota(ints.begin(), ints.end(), ints.size()); // Make ints from 1 to 100, increament by 1
    
    // Worker function
    std::function<int (int)> func = [](int x)->int {
        QThread::msleep(100);
        return x * x;
    };
    
    //First execution of workers
    //Will increase the progressRange to 100
    QFuture<int> mappedFuture = QtConcurrent::mapped(ints, func);

    auto nextFuture = AsyncFuture::observe(mappedFuture).subscribe([ints, func](){
        //Execute another batch of workers
        //Will increase the progressRange to 200
        QFuture<int> mappedFuture2 = QtConcurrent::mapped(ints, func);
        return mappedFuture2;
    }).future();

    AsyncFuture::observe(nextFuture).onProgress([nextFuture](){
        //Report the progress for the sum of mappedFuture and nextFuture from 0 to 200.
    });
```

Deferred&lt;T&gt;
-----------

The `deferred<T>()` function return a Deferred<T> object that allows you to manipulate a QFuture manually. The future() function return a running QFuture<T>. You have to call Deferred.complete() / Deferred.cancel() to trigger the status changes.

The usage of complete/cancel in a Deferred object is pretty similar to the resolve/reject in a Promise object. You could complete a future by calling complete with a result value. If you give it another future, then it will observe the input future and change status once that is finished.

`deffered<T>()` that are created and immediately completed it's recommend to use `completed<T>()` instead. 

**Auto Cancellation**

The `Deferred<T>` object is an explicitly shared class. You may own multiple copies and they are pointed to the same piece of shared data. In case, all of the instances are destroyed, it will cancel its future automatically.

But there has an exception if you have even called Deferred.complete(`QFuture<T>`) / Deferred.cancel(`QFuture<ANY>`) then it won't cancel its future due to destruction. That will leave to the observed future to determine the final state.

```c++
  QFuture<void> future;
  {

    auto defer = deferred<void>();
    future = defer.future();
  }
  QCOMPARE(future.isCanceled(), true); // Due to auto cancellation
```

```c++
  QFuture<void> future;
  {

    auto defer = deferred<void>();
    future = defer.future();
    defer.complete(QtConcurrent::run(worker));
  }
  QCOMPARE(future.isCanceled(), false);
```

**Deferred&lt;T&gt;::complete(T) / Deferred&lt;T&gt;::complete()**

Complete this future object with the given arguments

**Deferred&lt;T&gt;::complete(QList&lt;T&gt;)**

Complete the future object with a list of result. User may obtain all the value by QFuture::results().

**Deferred&lt;T&gt;::complete(QFuture&lt;T&gt;)**

This future object is deferred to complete/cancel. It will track the state from the input future. If the input future is completed, then it will be completed too. That is same for cancel.


**Deferred&lt;T&gt;::cancel()**

Cancel the future object

**Deferred&lt;T&gt;::cancel(QFuture<ANY>)**

This future object is deferred to cancel according to the input future. Once it is completed, this future will be cancelled. However, if the input future is cancelled. Then this future object will just ignore it. Unless it fulfils the auto-cancellation rule.

**Deferred&lt;T&gt;::track(QFuture target)**

Track the progress and synchronize the status of the target future object.

It will forward the signal of `started` , `resumed` , `paused` . And synchonize  the `progressValue`, `progressMinimum` and `progressMaximum` value by listening the  `progressValueChanged` signal from target future object.

Remarks: It won't complete a future even the `progressValue` has been reached the maximum value.

Added since v0.3.6

completed();
-----------

The `completed<T>(const T&)` and `completed()` function return finished `QFuture<T>`
and `QFuture<void>` . `completed<T>(const T&)` can be used instead of a `deferred<T>()`
when the result is already available. For example:

```c++
    auto defer = deferred<int>();
    defer.complete(5);
    auto completedFuture = defer.future();
```

is equivalent to

```c++
    auto completedFuture = completed<int>(5);
```

`completed<T>(const T&)` is more convenient and light weight (memory and performance efficient) method of creating
a completed `QFuture<T>`.

Example

```
auto defer = AsyncFuture::deferred<void>();

auto mappedFuture = QtConcurrent::mapped(data, workerFunc);

defer.track(mappedFuture);

AsyncFuture::observe(mappedFuture).subscribute([=]() mutable {
   defer.complete();
});

return defer.future(); // It is a future with progress value same as the mappedFuture, but it don't contains the result.
```

Advanced Topics
=======

Subscribe Callback Funcion
---------------

In subscribe() / context(), you may pass a function with zero or one argument as the onCompleted callback. If you give it an argument, the type must be either of T or QFuture<T>. That would obtain the result or the observed future itself.

```c++
QFuture<QImage> reading = QtConcurrent::run(readImage, QString("image.jpg"));

observe(reading).subscribe([]() {
});

observe(reading).subscribe([](QImage result) {
});

observe(reading).subscribe([](QFuture<QImage> future) {
  // In case you need to get future.results
});
```

The return type can be none or any kind of value. That would determine what type of `Observable<R>` generated by context()/subscribe().

In case, you return a QFuture object. Then the new `Observable<R>` object will be deferred to complete/cancel until your future object is resolved. Therefore, you could run QtConcurrent::run within your callback function to make a more complex/flexible multi-threading programming models.

```c++

QFuture<int> f1 = QtConcurrent::mapped(input, mapFunc);

QFuture<int> f2 = observe(f1).context(contextObject, [=](QFuture<int> future) {
    // You may use QFuture as the input argument of your callback function
    // It will be set to the observed future object. So that you may obtain
    // the value of results()

    qDebug() << future.results();

    // Return another thread is possible.
    return QtConcurrent::run(reducerFunc, future.results());
}).future();

// f2 is constructed before the QtConcurrent::run statement
// But its value is equal to the result of reducerFunc

```

Callback Chain Cancelation
----

A chain can be canceled by returning a canceled QFuture.

Example:

```c++
auto f2 = observe(f1).subscribe([=]() {
  auto defer = Deferred<void>();
  defer.cancel();
  return defer.future();
}).future();

observe(f2).subscribe([=]() {
  // it won't be executed.
});
```

Cancelling the future at the end of the chain will cancel the whole chain. This will cancel all `QtConcurrent` execution. Worker threads that have already been started by `QtConcurrent` will continue running until finished, but no new ones will be started (this is how `QtConcurrent` works). 

Example: 

```c++
    QVector<int> ints(100);
    std::iota(ints.begin(), ints.end(), ints.size());
    std::function<int (int)> func = [](int x)->int {
        QThread::msleep(100);
        return x * x;
    };
    
    QFuture<int> mappedFuture = QtConcurrent::mapped(ints, func);

    auto future = AsyncFuture::observe(mappedFuture).subscribe(
                []{ 
                   // it won't be executed
                },
                []{ 
                    // it will be executed.
                }
    ).future();
    
    future.cancel(); //Will cancel mappedFuture and future 
```

Future Object Tracking
---------------

Since v0.4, the deferred object is supported to track the status of another future object. It will synchronize the `progressValue` / `progressMinimium ` /  `progressMaximium` and status of the tracking object. (e.g started signal)

For example:

```c++

        auto defer = AsyncFuture::deferred<QImage>();

        QFuture<QImage> input = QtConcurrent::mapped(files, readImage);

        defer.complete(input); // defer.future() will be a mirror of `input`. The `progressValue` will be changed and it will emit "started" signal via QFutureWatcher
```

A practical use-case

```c++

QFuture<QImage> readImagesFromFolder(const QString& folder) {

    auto worker = [=]() {
        // Read files from a directory in a thread
        QStringList files = findImageFiles(folder);

        // Concurrent image reader
        return QtConcurrent::mapped(files, readImage);
    };

    auto future = QtConcurrent::run(worker); // The type of future is QFuture<QFuture<QImage>>

    auto defer = AsyncFuture::deferred<QImage>();

    // defer object track the input future. It will emit "started" and `progressValueChanged` according to the status of the future of "QtConcurrent::mapped"
    defer.complete(future);
    return defer.future();
}

```

In the example code above, the future returned by `defer.future` is supposed to be a mirror of the result of `QtConcurrent::mapped`. However, the linkage is  not estimated in the beginning until the worker functions start `QtConcurrent::mapped`

In case it needs to track the status of a future object but it won’t complete automatically. It may use track() function

Restarter<T> 
---
Restarter is a helper for managing asynchronous operations in Qt/Concurrent. It lets you “restart” a long-running task whenever inputs change, ensuring that only the most recent invocation actually runs to completion. Previous runs are cancelled cleanly before the next one begins.

When to use

Debouncing or reload-on-change
If you have a UI element (e.g. a search box, filter slider, map viewport) that triggers an expensive asynchronous operation on every change, use Restarter to avoid piling up simultaneous tasks. Only the latest action will complete; in-flight tasks get cancelled.
Auto-retry with updated parameters
When your parameters change mid-flight, you want to cancel the current job and start a fresh one with new arguments, but only once the old job actually acknowledges cancellation.

**How it works**

1. First call to restart(...)
  * Immediately runs the provided runFunction to produce a QFuture<T>.
  * Calls your “future changed” callback so you can react to the new future.
2. Subsequent calls while the future is running
  * Saves the newest runFunction.
  * Installs a single cancellation watcher (via AsyncFuture::observe) on the running future.
  * Cancels the running future.
3. When the running future is cancelled
  * The watcher fires, and Restarter calls your latest runFunction to start the new task.
  * Again notifies you via the “future changed” callback.
4. Safety on context deletion
  * Because the watcher is tied to a QObject* context, if that context is destroyed before cancellation completes, the watcher is cleaned up and you’ll get a cancelled future.

**Quick Example**

Imagine you have a search field and want to fire off a network request each time the text changes, but cancel any pending request as soon as the user types again:

```
// 1) Create a Restarter<int> (or whatever T your request returns)
Restarter<ResponseData> restarter{ this };

// 2) Hook up a callback so you get notified whenever a new future is created
restarter.onFutureChanged([&](){
  //Help watch current progress of the future that's running
});

// 3) Whenever the text changes, restart the search
connect(searchLineEdit, &QLineEdit::textChanged, this,
        [&](const QString& text){
    restarter.restart([=](){
        // This lambda runs on a worker thread
        auto future = QtConcurrent::run([=](){
            return performNetworkSearch(text);
        });

        return observe(future).subscribe([](){
          //Handle the results of network search
        }).future();

    });
});
```
* On the very first keystroke, a network request fires immediately.
* If the user types again before the request completes, the old request is cancelled (assuming your network layer supports cancellation) and a new one starts only once the cancellation is acknowledged.
* displayResults() sees only the latest completed response.


waitForFinished()
---
Sometimes you need to block until a QFuture<T> completes, but you don’t want to spin your test harness or lose signal/slot delivery in unit tests. This helper uses a QFutureWatcher<T> and a minimal QEventLoop (with an optional timeout) to pump events needed for Qt’s testing framework while waiting.

```
void MyTest::testAsyncSum() {
    auto future = QtConcurrent::run([](){
        QThread::sleep(1);
        return 123;
    });

    // Wait up to 2 seconds, processing events so QTest continues handling events
    QVERIFY(waitForFinished(future, 2000));
    QCOMPARE(future.result(), 123);
}
```



Examples
========

There has few examples of different use-cases in this source file:

[asyncfuture/example.cpp at master · vpicaver/asyncfuture](https://github.com/vpicaver/asyncfuture/blob/master/tests/asyncfutureunittests/example.cpp)

Building Testcases
==================

Open the CMakeList.txt in QtCreator and set ENABLE_TESTING to ON. Build and run ./asyncfutureunittests 

From the command line
```
cmake -S . -B build -G Ninja -DENABLE_TESTING:BOOL=ON -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_FLAGS="-fsanitize=address"
cmake --build build
cd build 
./tests/asyncfutureunittests
```

See [github actions](https://github.com/vpicaver/asyncfuture/tree/dev/.github/workflows) for example of building the library. 



