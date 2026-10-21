//! Real-time scheduling for the C++ threads that need it
//! (`docs/RT_SCHEDULING.md`).

#[cxx_qt::bridge]
mod ffi {
    #[namespace = "marathon::rt"]
    extern "Rust" {
        /// `SCHED_RR` at `priority` for the calling thread, `SCHED_OTHER`
        /// for 0; the error number, 0 on success.
        fn set_thread_priority(priority: i32) -> i32;
    }
}

use marathon_rt::set_thread_priority;
