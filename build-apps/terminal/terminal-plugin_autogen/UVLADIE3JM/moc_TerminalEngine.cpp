/****************************************************************************
** Meta object code from reading C++ file 'TerminalEngine.h'
**
** Created by: The Qt Meta Object Compiler version 69 (Qt 6.9.3)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include "../../../../apps/terminal/src/TerminalEngine.h"
#include <QtCore/qmetatype.h>

#include <QtCore/qtmochelpers.h>

#include <memory>


#include <QtCore/qxptype_traits.h>
#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'TerminalEngine.h' doesn't include <QObject>."
#elif Q_MOC_OUTPUT_REVISION != 69
#error "This file was generated using the moc from 6.9.3. It"
#error "cannot be used with the include files from this version of Qt."
#error "(The moc has changed too much.)"
#endif

#ifndef Q_CONSTINIT
#define Q_CONSTINIT
#endif

QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
QT_WARNING_DISABLE_GCC("-Wuseless-cast")
namespace {
struct qt_meta_tag_ZN14TerminalEngineE_t {};
} // unnamed namespace

template <> constexpr inline auto TerminalEngine::qt_create_metaobjectdata<qt_meta_tag_ZN14TerminalEngineE_t>()
{
    namespace QMC = QtMocConstants;
    QtMocHelpers::StringRefStorage qt_stringData {
        "TerminalEngine",
        "QML.Element",
        "auto",
        "outputChanged",
        "",
        "runningChanged",
        "workingDirectoryChanged",
        "newOutput",
        "text",
        "processExited",
        "exitCode",
        "handleReadyRead",
        "handleFinished",
        "QProcess::ExitStatus",
        "exitStatus",
        "handleError",
        "QProcess::ProcessError",
        "error",
        "start",
        "sendInput",
        "sendCtrlC",
        "sendCtrlD",
        "clear",
        "terminate",
        "output",
        "running",
        "workingDirectory"
    };

    QtMocHelpers::UintData qt_methods {
        // Signal 'outputChanged'
        QtMocHelpers::SignalData<void()>(3, 4, QMC::AccessPublic, QMetaType::Void),
        // Signal 'runningChanged'
        QtMocHelpers::SignalData<void()>(5, 4, QMC::AccessPublic, QMetaType::Void),
        // Signal 'workingDirectoryChanged'
        QtMocHelpers::SignalData<void()>(6, 4, QMC::AccessPublic, QMetaType::Void),
        // Signal 'newOutput'
        QtMocHelpers::SignalData<void(const QString &)>(7, 4, QMC::AccessPublic, QMetaType::Void, {{
            { QMetaType::QString, 8 },
        }}),
        // Signal 'processExited'
        QtMocHelpers::SignalData<void(int)>(9, 4, QMC::AccessPublic, QMetaType::Void, {{
            { QMetaType::Int, 10 },
        }}),
        // Slot 'handleReadyRead'
        QtMocHelpers::SlotData<void()>(11, 4, QMC::AccessPrivate, QMetaType::Void),
        // Slot 'handleFinished'
        QtMocHelpers::SlotData<void(int, QProcess::ExitStatus)>(12, 4, QMC::AccessPrivate, QMetaType::Void, {{
            { QMetaType::Int, 10 }, { 0x80000000 | 13, 14 },
        }}),
        // Slot 'handleError'
        QtMocHelpers::SlotData<void(QProcess::ProcessError)>(15, 4, QMC::AccessPrivate, QMetaType::Void, {{
            { 0x80000000 | 16, 17 },
        }}),
        // Method 'start'
        QtMocHelpers::MethodData<void()>(18, 4, QMC::AccessPublic, QMetaType::Void),
        // Method 'sendInput'
        QtMocHelpers::MethodData<void(const QString &)>(19, 4, QMC::AccessPublic, QMetaType::Void, {{
            { QMetaType::QString, 8 },
        }}),
        // Method 'sendCtrlC'
        QtMocHelpers::MethodData<void()>(20, 4, QMC::AccessPublic, QMetaType::Void),
        // Method 'sendCtrlD'
        QtMocHelpers::MethodData<void()>(21, 4, QMC::AccessPublic, QMetaType::Void),
        // Method 'clear'
        QtMocHelpers::MethodData<void()>(22, 4, QMC::AccessPublic, QMetaType::Void),
        // Method 'terminate'
        QtMocHelpers::MethodData<void()>(23, 4, QMC::AccessPublic, QMetaType::Void),
    };
    QtMocHelpers::UintData qt_properties {
        // property 'output'
        QtMocHelpers::PropertyData<QString>(24, QMetaType::QString, QMC::DefaultPropertyFlags, 0),
        // property 'running'
        QtMocHelpers::PropertyData<bool>(25, QMetaType::Bool, QMC::DefaultPropertyFlags, 1),
        // property 'workingDirectory'
        QtMocHelpers::PropertyData<QString>(26, QMetaType::QString, QMC::DefaultPropertyFlags | QMC::Writable | QMC::StdCppSet, 2),
    };
    QtMocHelpers::UintData qt_enums {
    };
    QtMocHelpers::UintData qt_constructors {};
    QtMocHelpers::ClassInfos qt_classinfo({
            {    1,    2 },
    });
    return QtMocHelpers::metaObjectData<TerminalEngine, void>(QMC::MetaObjectFlag{}, qt_stringData,
            qt_methods, qt_properties, qt_enums, qt_constructors, qt_classinfo);
}
Q_CONSTINIT const QMetaObject TerminalEngine::staticMetaObject = { {
    QMetaObject::SuperData::link<QObject::staticMetaObject>(),
    qt_staticMetaObjectStaticContent<qt_meta_tag_ZN14TerminalEngineE_t>.stringdata,
    qt_staticMetaObjectStaticContent<qt_meta_tag_ZN14TerminalEngineE_t>.data,
    qt_static_metacall,
    nullptr,
    qt_staticMetaObjectRelocatingContent<qt_meta_tag_ZN14TerminalEngineE_t>.metaTypes,
    nullptr
} };

void TerminalEngine::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    auto *_t = static_cast<TerminalEngine *>(_o);
    if (_c == QMetaObject::InvokeMetaMethod) {
        switch (_id) {
        case 0: _t->outputChanged(); break;
        case 1: _t->runningChanged(); break;
        case 2: _t->workingDirectoryChanged(); break;
        case 3: _t->newOutput((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1]))); break;
        case 4: _t->processExited((*reinterpret_cast< std::add_pointer_t<int>>(_a[1]))); break;
        case 5: _t->handleReadyRead(); break;
        case 6: _t->handleFinished((*reinterpret_cast< std::add_pointer_t<int>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QProcess::ExitStatus>>(_a[2]))); break;
        case 7: _t->handleError((*reinterpret_cast< std::add_pointer_t<QProcess::ProcessError>>(_a[1]))); break;
        case 8: _t->start(); break;
        case 9: _t->sendInput((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1]))); break;
        case 10: _t->sendCtrlC(); break;
        case 11: _t->sendCtrlD(); break;
        case 12: _t->clear(); break;
        case 13: _t->terminate(); break;
        default: ;
        }
    }
    if (_c == QMetaObject::IndexOfMethod) {
        if (QtMocHelpers::indexOfMethod<void (TerminalEngine::*)()>(_a, &TerminalEngine::outputChanged, 0))
            return;
        if (QtMocHelpers::indexOfMethod<void (TerminalEngine::*)()>(_a, &TerminalEngine::runningChanged, 1))
            return;
        if (QtMocHelpers::indexOfMethod<void (TerminalEngine::*)()>(_a, &TerminalEngine::workingDirectoryChanged, 2))
            return;
        if (QtMocHelpers::indexOfMethod<void (TerminalEngine::*)(const QString & )>(_a, &TerminalEngine::newOutput, 3))
            return;
        if (QtMocHelpers::indexOfMethod<void (TerminalEngine::*)(int )>(_a, &TerminalEngine::processExited, 4))
            return;
    }
    if (_c == QMetaObject::ReadProperty) {
        void *_v = _a[0];
        switch (_id) {
        case 0: *reinterpret_cast<QString*>(_v) = _t->output(); break;
        case 1: *reinterpret_cast<bool*>(_v) = _t->running(); break;
        case 2: *reinterpret_cast<QString*>(_v) = _t->workingDirectory(); break;
        default: break;
        }
    }
    if (_c == QMetaObject::WriteProperty) {
        void *_v = _a[0];
        switch (_id) {
        case 2: _t->setWorkingDirectory(*reinterpret_cast<QString*>(_v)); break;
        default: break;
        }
    }
}

const QMetaObject *TerminalEngine::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *TerminalEngine::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_staticMetaObjectStaticContent<qt_meta_tag_ZN14TerminalEngineE_t>.strings))
        return static_cast<void*>(this);
    return QObject::qt_metacast(_clname);
}

int TerminalEngine::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QObject::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 14)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 14;
    }
    if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 14)
            *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType();
        _id -= 14;
    }
    if (_c == QMetaObject::ReadProperty || _c == QMetaObject::WriteProperty
            || _c == QMetaObject::ResetProperty || _c == QMetaObject::BindableProperty
            || _c == QMetaObject::RegisterPropertyMetaType) {
        qt_static_metacall(this, _c, _id, _a);
        _id -= 3;
    }
    return _id;
}

// SIGNAL 0
void TerminalEngine::outputChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 0, nullptr);
}

// SIGNAL 1
void TerminalEngine::runningChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 1, nullptr);
}

// SIGNAL 2
void TerminalEngine::workingDirectoryChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 2, nullptr);
}

// SIGNAL 3
void TerminalEngine::newOutput(const QString & _t1)
{
    QMetaObject::activate<void>(this, &staticMetaObject, 3, nullptr, _t1);
}

// SIGNAL 4
void TerminalEngine::processExited(int _t1)
{
    QMetaObject::activate<void>(this, &staticMetaObject, 4, nullptr, _t1);
}
QT_WARNING_POP
