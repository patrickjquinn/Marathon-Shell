import QtQuick
import QtTest
import "../Phone.js" as Phone

TestCase {
    name: "PhoneJs"

    function test_format() {
        compare(Phone.format("+15551234567"), "+1 555 123 4567");
        compare(Phone.format("0871234567"), "087 123 4567");
        compare(Phone.format("*21#"), "*21#");
        compare(Phone.format(""), "");
    }

    function test_sameNumber() {
        verify(Phone.sameNumber("+1 555 123 4567", "5551234567"));
        verify(!Phone.sameNumber("112", "911"));
        verify(!Phone.sameNumber("", ""));
    }

    function test_emergency() {
        verify(Phone.isEmergency("112"));
        verify(Phone.isEmergency(" 911 "));
        verify(Phone.isEmergency("999"));
        verify(!Phone.isEmergency("1123"));
        verify(!Phone.isEmergency("+112"));
    }

    function test_duration() {
        compare(Phone.duration(0), "0:00");
        compare(Phone.duration(65), "1:05");
        compare(Phone.duration(3725), "1:02:05");
    }

    function test_timestampSecondsOrMs() {
        compare(Phone.timestampMs(1700000000), 1700000000000);
        compare(Phone.timestampMs(1700000000000), 1700000000000);
        compare(Phone.timestampMs("x"), 0);
    }

    function test_filterContacts() {
        const c = [
            {
                name: "Ada Lovelace",
                phone: "+44 20 7946 0000"
            },
            {
                name: "Alan Turing",
                phone: "555 0101"
            }
        ];
        compare(Phone.filterContacts(c, "").length, 2);
        compare(Phone.filterContacts(c, "ada")[0].name, "Ada Lovelace");
        compare(Phone.filterContacts(c, "0101")[0].name, "Alan Turing");
        compare(Phone.filterContacts(c, "zzz").length, 0);
    }

    function test_missedSince() {
        const h = [
            {
                type: "missed",
                timestamp: 200
            },
            {
                type: "missed",
                timestamp: 50
            },
            {
                type: "incoming",
                timestamp: 300
            }
        ];
        compare(Phone.missedSince(h, 100000), 1);
        compare(Phone.missedSince(h, 0), 2);
    }

    function test_groupCalls() {
        const rows = Phone.groupCalls([
            {
                id: 1,
                number: "+353 87 123 4567",
                type: "missed"
            },
            {
                id: 2,
                number: "0871234567",
                type: "missed"
            },
            {
                id: 3,
                number: "0871234567",
                type: "incoming"
            },
            {
                id: 4,
                number: "112",
                type: "outgoing"
            },
            {
                id: 5,
                number: "0871234567",
                type: "incoming"
            }
        ]);
        compare(rows.map(r => r.ids), [[1, 2], [3], [4], [5]]);
        compare(rows[0].number, "+353 87 123 4567");
        compare(Phone.groupCalls([]), []);
    }

    function test_peopleRows() {
        const rows = Phone.peopleRows([
            {
                id: 1,
                name: "grace Hopper"
            },
            {
                id: 2,
                name: "Ada Lovelace",
                favorite: true
            },
            {
                id: 3,
                name: "Alan Turing"
            },
            {
                id: 4,
                name: "+353 87 123"
            }
        ], "");
        compare(rows.map(r => r.id), [2, 4, 3, 1]);
        compare(rows.map(r => r.section), ["*", "#", "A", "G"]);
        compare(Phone.peopleRows([
            {
                id: 1,
                name: "Ada"
            },
            {
                id: 2,
                name: "Bob"
            }
        ], "bo").map(r => r.id), [2]);
    }

    function test_dialable() {
        compare(Phone.dialable("Call +1 (555) 123-4567 now"), "+15551234567");
        compare(Phone.dialable("*21#"), "*21#");
        compare(Phone.dialable("no digits"), "");
    }
}
