//! `Telephony`: the shell's Telephony1, voice calls.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use futures_lite::StreamExt;

use crate::shell::{allowed, answers, relay, Service};
use marathon_rt::io;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QString, call_state, cxx_name = "callState", READ, NOTIFY = call_state_changed)]
        #[qproperty(bool, has_modem, cxx_name = "hasModem", READ, NOTIFY = modem_changed)]
        #[qproperty(QString, active_number, cxx_name = "activeNumber", READ, NOTIFY = active_number_changed)]
        type Telephony = super::TelephonyRust;

        #[qsignal]
        #[cxx_name = "callStateChanged"]
        fn call_state_changed(self: Pin<&mut Self>, state: &QString);
        #[qsignal]
        #[cxx_name = "modemChanged"]
        fn modem_changed(self: Pin<&mut Self>, has_modem: bool);
        #[qsignal]
        #[cxx_name = "activeNumberChanged"]
        fn active_number_changed(self: Pin<&mut Self>, number: &QString);
        #[qsignal]
        #[cxx_name = "incomingCall"]
        fn incoming_call(self: Pin<&mut Self>, number: &QString);
        #[qsignal]
        #[cxx_name = "callFailed"]
        fn call_failed(self: Pin<&mut Self>, reason: &QString);

        #[qinvokable]
        fn dial(self: &Telephony, number: &QString);
        #[qinvokable]
        #[cxx_name = "dialEmergency"]
        fn dial_emergency(self: &Telephony, number: &QString);
        #[qinvokable]
        fn answer(self: &Telephony);
        #[qinvokable]
        fn hangup(self: &Telephony);
        #[qinvokable]
        #[cxx_name = "sendDTMF"]
        fn send_dtmf(self: &Telephony, digit: &QString);
        #[qinvokable]
        #[cxx_name = "simulateIncomingCall"]
        fn simulate_incoming_call(self: &Telephony, number: &QString);
        #[qinvokable]
        #[cxx_name = "simulateCallStateChange"]
        fn simulate_call_state_change(self: &Telephony, state: &QString);
        #[qinvokable]
        #[cxx_name = "setSpeakerphone"]
        fn set_speakerphone(self: &Telephony, on: bool);
        #[qinvokable]
        #[cxx_name = "setCallMuted"]
        fn set_call_muted(self: &Telephony, muted: bool);
        #[qinvokable]
        #[cxx_name = "isSpeakerphoneOn"]
        fn is_speakerphone_on(self: &Telephony) -> bool;
        #[qinvokable]
        #[cxx_name = "isCallMuted"]
        fn is_call_muted(self: &Telephony) -> bool;
    }

    impl cxx_qt::Threading for Telephony {}
    impl cxx_qt::Initialize for Telephony {}
}

use qobject::Telephony;

const TELEPHONY: Service = Service::session("Telephony");

#[derive(Default)]
pub struct TelephonyRust {
    call_state: QString,
    has_modem: bool,
    active_number: QString,
}

type Qt = cxx_qt::CxxQtThread<Telephony>;

impl cxx_qt::Initialize for Telephony {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(qt.clone(), TELEPHONY, "CallStateChanged", |obj, (s,): (String,)| show_state(obj, &s));
        relay(qt.clone(), TELEPHONY, "ModemChanged", |obj, (m,): (bool,)| show_modem(obj, m));
        relay(qt.clone(), TELEPHONY, "ActiveNumberChanged", |obj, (n,): (String,)| show_number(obj, &n));
        relay(qt.clone(), TELEPHONY, "IncomingCall", |obj, (n,): (String,)| obj.incoming_call(&QString::from(&n)));
        relay(qt.clone(), TELEPHONY, "CallFailed", |obj, (r,): (String,)| obj.call_failed(&QString::from(&r)));
        io::spawn(async move {
            let mut asked = false;
            refresh(&qt, &mut asked).await;
            if let Ok(grants) = answers("PermissionGranted", "telephony").await {
                let mut grants = std::pin::pin!(grants);
                while grants.next().await.is_some() {
                    refresh(&qt, &mut asked).await;
                }
            }
        });
    }
}

async fn refresh(qt: &Qt, asked: &mut bool) {
    if !allowed("telephony", asked).await.unwrap_or(false) {
        return;
    }
    let state = TELEPHONY.ask::<_, String>("CallState", &()).await;
    let modem = TELEPHONY.ask::<_, bool>("HasModem", &()).await;
    let number = TELEPHONY.ask::<_, String>("ActiveNumber", &()).await;
    qt.queue(move |mut obj| {
        if let Ok(s) = state {
            show_state(obj.as_mut(), &s);
        }
        if let Ok(m) = modem {
            show_modem(obj.as_mut(), m);
        }
        if let Ok(n) = number {
            show_number(obj, &n);
        }
    })
    .ok();
}

fn show_state(mut obj: Pin<&mut Telephony>, state: &str) {
    let state = QString::from(state);
    if obj.call_state != state {
        obj.as_mut().rust_mut().call_state = state.clone();
        obj.call_state_changed(&state);
    }
}

fn show_modem(mut obj: Pin<&mut Telephony>, has_modem: bool) {
    if obj.has_modem != has_modem {
        obj.as_mut().rust_mut().has_modem = has_modem;
        obj.modem_changed(has_modem);
    }
}

fn show_number(mut obj: Pin<&mut Telephony>, number: &str) {
    let number = QString::from(number);
    if obj.active_number != number {
        obj.as_mut().rust_mut().active_number = number.clone();
        obj.active_number_changed(&number);
    }
}

impl Telephony {
    crate::shell::calls! { TELEPHONY;
        answer() => "Answer";
        hangup() => "Hangup";
        set_speakerphone(on: bool) => "SetSpeakerphone";
        set_call_muted(muted: bool) => "SetCallMuted";
        dial(number: &QString) => "Dial";
        send_dtmf(digit: &QString) => "SendDTMF";
        simulate_incoming_call(number: &QString) => "SimulateIncomingCall";
        simulate_call_state_change(state: &QString) => "SimulateCallStateChange";
    }
    crate::shell::asks! { TELEPHONY;
        is_speakerphone_on() -> bool => "IsSpeakerphoneOn";
        is_call_muted() -> bool => "IsCallMuted";
    }

    fn dial_emergency(&self, number: &QString) {
        self.dial(number);
    }

}
