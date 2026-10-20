#ifndef PAMAUTH_H
#define PAMAUTH_H

#include <QString>
#include <QByteArray>
#include <security/pam_appl.h>
#include <cstdlib>
#include <cstring>

// The system password through PAM's "marathon-shell" service, for the Rust
// security service (crates/marathon-shell-native/src/security.rs), which
// calls it on its blocking pool. Here rather than a Rust binding: libpam is
// a C API, and the Rust crates for it generate their bindings at build time.
namespace marathon::pam {

    inline int answer(int count, const pam_message **messages, pam_response **responses,
                      void *password) {
        if (count <= 0 || !messages || !responses || !password)
            return PAM_CONV_ERR;
        auto *out = static_cast<pam_response *>(calloc(count, sizeof(pam_response)));
        if (!out)
            return PAM_BUF_ERR;
        for (int i = 0; i < count; ++i) {
            switch (messages[i]->msg_style) {
                case PAM_PROMPT_ECHO_OFF:
                case PAM_PROMPT_ECHO_ON:
                    out[i].resp = strdup(static_cast<const QByteArray *>(password)->constData());
                    break;
                case PAM_ERROR_MSG:
                case PAM_TEXT_INFO:
                    break;
                default:
                    for (int j = 0; j < i; ++j)
                        free(out[j].resp);
                    free(out);
                    return PAM_CONV_ERR;
            }
        }
        *responses = out;
        return PAM_SUCCESS;
    }

    inline bool authenticate(const QString &user, const QString &password) {
        const QByteArray secret = password.toUtf8();
        const pam_conv   conv{answer, const_cast<QByteArray *>(&secret)};
        pam_handle_t    *handle = nullptr;
        if (pam_start("marathon-shell", user.toUtf8().constData(), &conv, &handle) != PAM_SUCCESS)
            return false;
        int status = pam_authenticate(handle, PAM_SILENT);
        if (status == PAM_SUCCESS)
            status = pam_acct_mgmt(handle, PAM_SILENT);
        pam_end(handle, status);
        return status == PAM_SUCCESS;
    }

} // namespace marathon::pam

#endif
