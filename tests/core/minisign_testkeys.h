#pragma once

#include <QByteArray>
#include <QFile>
#include <QString>

// Unencrypted minisign key pairs for tests only. The secret keys are public
// here, so nothing outside tests may ever trust these.
namespace TestKeys {

    struct Pair {
        const char *id;
        const char *secret;
        const char *pub;
    };

    inline const Pair alice{
        "BDC597FE8CF7F6F3",
        "untrusted comment: test-only key, never trust outside tests\n"
        "RWQAAEIyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA8/b3jP6Xxb3qJ5ax"
        "6Xw6NmCuW9TKBPerSOXJc2mFOlAsAgSTu0OZXaHGXJDKwGIRS/MP5g/syiBzHNpL/aymxdZvs/8LDhpFPzDwppppC8"
        "P6/+dVMf2QWE20PYbOl3/ngrGlV6IMpdA=\n",
        "untrusted comment: minisign public key: BDC597FE8CF7F6F3\n"
        "RWTz9veM/pfFvaHGXJDKwGIRS/MP5g/syiBzHNpL/aymxdZvs/8LDhpF\n"};

    inline const Pair bob{
        "4D9129AD84930B56",
        "untrusted comment: test-only key, never trust outside tests\n"
        "RWQAAEIyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVguThK0pkU3Oe14F"
        "+bjHfSd3jq3EmsiQNwz6gDCRWxkFCdAjFrvviVVnWh8/O076dg0kVIVZEnPa4o47qiQ0GY2tQoEdEpyf/JCnqwxCz3"
        "tHLrAwGW3f6ekvZJEd3RvvpPUp01rGY/o=\n",
        "untrusted comment: minisign public key: 4D9129AD84930B56\n"
        "RWRWC5OErSmRTVVnWh8/O076dg0kVIVZEnPa4o47qiQ0GY2tQoEdEpyf\n"};

    inline const Pair mallory{
        "FDCBFECA7632AD97",
        "untrusted comment: test-only key, never trust outside tests\n"
        "RWQAAEIyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAl60ydsr+y/2Hmfix"
        "I74d39lF9bgf3eSQYHSAweTEAkvlY22BjYtNTC1pC3XVhk6owZaKsk0j9scShT3Zg1chUWddricgt9J4y+2wE9cxrZ"
        "J600OiYaLLUXAZLcaLzyqI0TTdmArQdKM=\n",
        "untrusted comment: minisign public key: FDCBFECA7632AD97\n"
        "RWSXrTJ2yv7L/S1pC3XVhk6owZaKsk0j9scShT3Zg1chUWddricgt9J4\n"};

    inline bool write(const QString &path, const QByteArray &data) {
        QFile f(path);
        return f.open(QIODevice::WriteOnly) && f.write(data) == data.size();
    }

} // namespace TestKeys
