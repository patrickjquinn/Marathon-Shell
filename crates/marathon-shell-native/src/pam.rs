//! The system password through libpam's `marathon-shell` service. Declared
//! here rather than generated: four functions and one callback of a stable
//! C API, with no bindgen in the build.

use std::ffi::{c_char, c_int, c_void, CString};
use std::ptr;

#[repr(C)]
struct Message {
    style: c_int,
    text: *const c_char,
}

#[repr(C)]
struct Response {
    text: *mut c_char,
    code: c_int,
}

type Converse = extern "C" fn(c_int, *mut *const Message, *mut *mut Response, *mut c_void) -> c_int;

#[repr(C)]
struct Conversation {
    converse: Converse,
    data: *mut c_void,
}

enum Handle {}

const SUCCESS: c_int = 0;
const BUF_ERR: c_int = 5;
const CONV_ERR: c_int = 19;
const PROMPT_ECHO_OFF: c_int = 1;
const PROMPT_ECHO_ON: c_int = 2;
const SILENT: c_int = 0x8000;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    InvalidInput,
    Start(c_int),
    Authenticate(c_int),
    Account(c_int),
    End(c_int),
}

#[link(name = "pam")]
extern "C" {
    fn pam_start(
        service: *const c_char,
        user: *const c_char,
        conversation: *const Conversation,
        handle: *mut *mut Handle,
    ) -> c_int;
    fn pam_authenticate(handle: *mut Handle, flags: c_int) -> c_int;
    fn pam_acct_mgmt(handle: *mut Handle, flags: c_int) -> c_int;
    fn pam_end(handle: *mut Handle, status: c_int) -> c_int;
}

// PAM frees the answers with free(), so they come from the C allocator.
extern "C" {
    fn calloc(count: usize, size: usize) -> *mut c_void;
    fn strdup(text: *const c_char) -> *mut c_char;
}

/// Answers every prompt with the password in `data`.
extern "C" fn converse(
    count: c_int,
    messages: *mut *const Message,
    answers: *mut *mut Response,
    data: *mut c_void,
) -> c_int {
    let Ok(count) = usize::try_from(count) else {
        return CONV_ERR;
    };
    if count == 0 || messages.is_null() || answers.is_null() || data.is_null() {
        return CONV_ERR;
    }
    // SAFETY: PAM passes `count` message pointers and a place for the
    // answers; `data` is the `CString` `authenticate` lent it for this call.
    unsafe {
        let out = calloc(count, size_of::<Response>()).cast::<Response>();
        if out.is_null() {
            return BUF_ERR;
        }
        let password = &*data.cast::<CString>();
        for i in 0..count {
            if matches!((**messages.add(i)).style, PROMPT_ECHO_OFF | PROMPT_ECHO_ON) {
                (*out.add(i)).text = strdup(password.as_ptr());
            }
        }
        *answers = out;
    }
    SUCCESS
}

/// Verifies `password` through PAM's authentication and account stacks. Waits
/// out PAM's failure delay on rejection: call it off the GUI thread.
pub fn authenticate(user: &str, password: &str) -> Result<(), Error> {
    let (Ok(service), Ok(user), Ok(password)) = (
        CString::new("marathon-shell"),
        CString::new(user),
        CString::new(password),
    ) else {
        return Err(Error::InvalidInput);
    };
    let conversation = Conversation {
        converse,
        data: ptr::from_ref(&password).cast_mut().cast(),
    };
    let mut handle = ptr::null_mut();
    // SAFETY: the strings and the conversation outlive the PAM transaction,
    // which ends with pam_end before they drop.
    unsafe {
        let started = pam_start(
            service.as_ptr(),
            user.as_ptr(),
            &raw const conversation,
            &raw mut handle,
        );
        if started != SUCCESS {
            return Err(Error::Start(started));
        }
        let authenticated = pam_authenticate(handle, SILENT);
        if authenticated != SUCCESS {
            pam_end(handle, authenticated);
            return Err(Error::Authenticate(authenticated));
        }
        let account = pam_acct_mgmt(handle, SILENT);
        if account != SUCCESS {
            pam_end(handle, account);
            return Err(Error::Account(account));
        }
        let ended = pam_end(handle, SUCCESS);
        if ended == SUCCESS {
            Ok(())
        } else {
            Err(Error::End(ended))
        }
    }
}
