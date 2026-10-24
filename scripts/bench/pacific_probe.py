#!/usr/bin/env python3
"""Pacific acceptance probe, run on the device as root (stdlib only).

  pacific_probe.py serve [--port 8765] [--log /run/pacific-probe.jsonl]
      Serves a long test page on 127.0.0.1 that reports, as JSON lines in
      the log: its load timing ("load"), every page-scale change ("scale",
      visualViewport.scale) and main-thread frame times while it scrolls
      ("scroll").
  pacific_probe.py pinch [--gap0 150] [--gap1 375] [--ms 600] [--log ...]
      Two fingers spread about the panel centre through uinput, then reads
      the page scale the page reported and Pacific's GPU frames during the
      gesture (ftrace, as scroll_bench.py).

Open the page in Pacific (as uid 1000):
  busctl --user call org.shipwright.pacific /org/shipwright/Keel/Actions \\
    org.shipwright.Keel.Actions Invoke 'ssa{sv}' browser.open \\
    '{"url":"http://127.0.0.1:8765/?run=1"}' 0
"""
import argparse
import http.server
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scroll_bench as sb  # noqa: E402

PAGE = """<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pacific probe</title><style>
body{font:16px/1.5 sans-serif;margin:0 12px}
.card{margin:12px 0;padding:12px;border-radius:12px;box-shadow:0 2px 8px #0004;
background:linear-gradient(135deg,#e8f0ff,#fff6e8)}
</style></head><body><h1>Pacific probe</h1>%s<script>
function post(o){o.t=Math.round(performance.now());o.url=location.search;
navigator.sendBeacon('/log',JSON.stringify(o));}
addEventListener('load',()=>setTimeout(()=>{const n=performance.getEntriesByType('navigation')[0];
post({kind:'load',response_ms:Math.round(n.responseEnd),dcl_ms:Math.round(n.domContentLoadedEventEnd),
load_ms:Math.round(n.loadEventEnd)});},0));
let last=visualViewport.scale;post({kind:'scale',scale:last});
visualViewport.addEventListener('resize',()=>{if(visualViewport.scale!==last){
last=visualViewport.scale;post({kind:'scale',scale:last});}});
let frames=[],prev=0,idle=null;
function tick(ts){if(prev)frames.push(ts-prev);prev=ts;if(idle!==null)requestAnimationFrame(tick);}
addEventListener('scroll',()=>{if(idle===null){frames=[];prev=0;idle=0;requestAnimationFrame(tick);}
clearTimeout(idle);idle=setTimeout(()=>{idle=null;const s=frames.slice().sort((a,b)=>a-b);
const q=p=>s.length?Math.round(s[Math.min(s.length-1,Math.round(p*(s.length-1)))]*10)/10:null;
post({kind:'scroll',frames:s.length,p50_ms:q(.5),p95_ms:q(.95),max_ms:q(1),
over_25ms:s.filter(x=>x>25).length});},300);},{passive:true});
try{new PerformanceObserver(l=>{for(const e of l.getEntries())
if(e.name==='first-contentful-paint')post({kind:'fcp',ms:Math.round(e.startTime)});})
.observe({type:'paint',buffered:true});}catch(e){post({kind:'fcp',error:String(e)});}
</script></body></html>"""


def page():
    cards = "".join(
        "<div class=card><h2>Section %d</h2><p>%s</p></div>" % (i, "Lorem ipsum dolor sit amet, "
                                                               "consectetur adipiscing elit. " * 12)
        for i in range(300))
    return (PAGE % cards).encode()


def serve(a):
    body = page()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            data = self.rfile.read(min(int(self.headers.get("Content-Length", 0)), 65536))
            self.send_response(204)
            self.end_headers()
            try:
                rec = json.loads(data)
            except ValueError:
                return
            rec["wall"] = time.time()
            line = json.dumps(rec)
            with open(a.log, "a") as f:
                f.write(line + "\n")
            print(line, flush=True)

        def log_message(self, *args):
            pass

    http.server.ThreadingHTTPServer(("127.0.0.1", a.port), Handler).serve_forever()


def last_scale(log, since):
    scale = None
    try:
        with open(log) as f:
            for line in f:
                rec = json.loads(line)
                if rec.get("kind") == "scale" and rec["wall"] >= since:
                    scale = rec["scale"]
    except (OSError, ValueError):
        pass
    return scale


class Pinch(sb.Touch):
    def fingers(self, points):
        for slot, p in enumerate(points):
            self._ev(sb.EV_ABS, sb.ABS_MT_SLOT, slot)
            if p is None:
                self._ev(sb.EV_ABS, sb.ABS_MT_TRACKING_ID, -1)
                continue
            if p[2]:
                self.tid += 1
                self._ev(sb.EV_ABS, sb.ABS_MT_TRACKING_ID, self.tid)
            self._pos(p[0], p[1])
        down = any(p is not None for p in points)
        self._ev(sb.EV_KEY, sb.BTN_TOUCH, 1 if down else 0)
        self._ev(sb.EV_SYN, sb.SYN_REPORT, 0)
        return time.monotonic()


def pinch(a):
    cx, cy = a.width / 2, a.height / 2

    def at(gap, new=False):
        return [(cx - gap / 2, cy, new), (cx + gap / 2, cy, new)]

    touch = Pinch(a.width, a.height)
    time.sleep(0.6)
    sb.trace_start()
    time.sleep(0.3)
    started = time.time()
    try:
        t0 = touch.fingers(at(a.gap0, True))
        sb.sleep_until(t0 + 0.15)
        n = max(2, int(a.ms / a.step_ms))
        t1 = time.monotonic()
        for k in range(1, n + 1):
            sb.sleep_until(t1 + k * a.step_ms / 1000.0)
            touch.fingers(at(a.gap0 + (a.gap1 - a.gap0) * k / n))
        sb.sleep_until(time.monotonic() + 0.1)
        t_up = touch.fingers([None, None])
        time.sleep(1.5)
    finally:
        text = sb.trace_stop()
        touch.close()
    flips, submits = sb.parse(text)
    procs = {}
    for pid, ts in submits.items():
        fr = [t for t in sb.frames_of(ts) if t1 <= t <= t_up]
        if len(fr) >= 3:
            procs["%d:%s" % (pid, sb.comm(pid))] = sb.interval_stats(fr, 1.0 / a.hz)
    want = a.gap1 / a.gap0
    got = last_scale(a.log, started)
    res = {
        "expected_scale": round(want, 3),
        "page_scale": got,
        "scale_ok": got is not None and abs(got - want) <= 0.1 * want,
        "gesture_ms": round((t_up - t1) * 1000),
        "frames_during_pinch": procs,
    }
    print(json.dumps(res, indent=1))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("serve")
    s.add_argument("--port", type=int, default=8765)
    p = sub.add_parser("pinch")
    p.add_argument("--gap0", type=float, default=150)
    p.add_argument("--gap1", type=float, default=375)
    p.add_argument("--ms", type=int, default=600)
    p.add_argument("--step-ms", type=float, default=10.0)
    p.add_argument("--width", type=int, default=720)
    p.add_argument("--height", type=int, default=720)
    p.add_argument("--hz", type=float, default=60.0)
    for x in (s, p):
        x.add_argument("--log", default="/run/pacific-probe.jsonl")
    a = ap.parse_args()
    serve(a) if a.cmd == "serve" else pinch(a)


if __name__ == "__main__":
    main()
