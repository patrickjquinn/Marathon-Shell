// SPDX-License-Identifier: GPL-3.0-or-later
//! Turn-by-turn route following for the Maps app: where a fix lies on a
//! Valhalla route, the maneuver ahead, the distance and time to it and to
//! the destination, and when to ask for a new route.
//!
//! The edge matching, reference points, miss count and reroute rule are
//! ported from Pure Maps' `src/navigator.cpp`, copyright Rinigus and the
//! Pure Maps contributors, GPL-3.0-or-later. Pure Maps finds nearby edges
//! with an S2 index; a phone's route is small enough to scan in a local
//! plane around each fix.

use std::collections::VecDeque;

use serde_json::Value;

const EARTH_RADIUS: f64 = 6_371_000.0;
/// No fix is taken as better than this, in metres.
const MIN_ACCURACY: f64 = 15.0;
/// A fix vaguer than this is not placed at all.
const MAX_ACCURACY: f64 = 100.0;
/// Edges tried per fix, closest first: a route can cross itself.
const CANDIDATES: usize = 5;
/// A reference point is kept once the fix is this many accuracies past the last one.
const REF_MARGIN: f64 = 2.0;
const REF_POINTS: usize = 2;
/// Misses in a row before the fix counts as off the route.
const OFF_ROUTE_MISSES: u32 = 3;
/// Misses in a row before driving the route backwards asks for a new one.
const WRONG_WAY_MISSES: u32 = 5;
/// Seconds between reroute requests.
const REROUTE_INTERVAL: f64 = 5.0;

/// A maneuver's place on the route.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Maneuver {
    /// Metres from the start to where the maneuver begins.
    pub distance: f64,
    /// Seconds from the start to it, by Valhalla's estimate.
    pub time: f64,
}

#[derive(Debug)]
struct Edge {
    from: (f64, f64),
    to: (f64, f64),
    length: f64,
    /// Metres of route before the edge.
    before: f64,
    bearing: f64,
    maneuver: usize,
}

/// The first leg of a Valhalla route: Marathon routes to one destination.
/// Points are (latitude, longitude).
#[derive(Debug)]
pub struct Route {
    edges: Vec<Edge>,
    pub maneuvers: Vec<Maneuver>,
    /// Metres.
    pub length: f64,
    /// Seconds.
    pub time: f64,
}

impl Route {
    /// From Valhalla's `/route` reply in its own JSON format.
    pub fn from_valhalla(reply: &Value) -> Result<Self, String> {
        let leg = &reply["trip"]["legs"][0];
        let shape = leg["shape"].as_str().ok_or("The route has no shape")?;
        let points: Vec<(f64, f64)> = polyline::decode_polyline(shape, 6)
            .map_err(|e| format!("Bad route shape: {e}"))?
            .coords()
            .map(|c| (c.y, c.x))
            .collect();
        let steps = leg["maneuvers"]
            .as_array()
            .filter(|steps| !steps.is_empty() && points.len() > 1)
            .ok_or("The route has no maneuvers")?;
        let mut edges = Vec::with_capacity(points.len() - 1);
        let mut length = 0.0;
        for pair in points.windows(2) {
            let (from, to) = (pair[0], pair[1]);
            let edge = distance(from, to);
            edges.push(Edge {
                from,
                to,
                length: edge,
                before: length,
                bearing: bearing(from, to),
                maneuver: 0,
            });
            length += edge;
        }
        let mut maneuvers = Vec::with_capacity(steps.len());
        let mut time = 0.0;
        for (i, step) in steps.iter().enumerate() {
            let (begin, end) = (
                index(&step["begin_shape_index"])?,
                index(&step["end_shape_index"])?,
            );
            if begin > end || end >= points.len() {
                return Err(format!("Maneuver {i} is off the route"));
            }
            for edge in &mut edges[begin..end] {
                edge.maneuver = i;
            }
            maneuvers.push(Maneuver {
                distance: edges.get(begin).map_or(length, |e| e.before),
                time,
            });
            time += step["time"].as_f64().unwrap_or(0.0);
        }
        Ok(Self {
            edges,
            maneuvers,
            length,
            time,
        })
    }
}

fn index(value: &Value) -> Result<usize, String> {
    value
        .as_u64()
        .and_then(|i| usize::try_from(i).ok())
        .ok_or_else(|| "A maneuver has no shape index".to_owned())
}

/// A position fix.
#[derive(Clone, Copy, Debug)]
pub struct Fix {
    pub lat: f64,
    pub lon: f64,
    /// Metres.
    pub accuracy: f64,
    /// Degrees clockwise from north. Without it any edge near the fix
    /// matches, and driving the wrong way goes unnoticed.
    pub heading: Option<f64>,
    /// Seconds, from any fixed start.
    pub time: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    /// On the route, but not yet far enough along it to be sure.
    Joining,
    Following,
    /// On the route, going against it.
    WrongWay,
    /// `Status::off_route` metres from the route.
    OffRoute,
    /// The last fix was too vague to place.
    Imprecise,
    Arrived,
}

/// Where navigation stands. Distances and times are from the last fix
/// placed on the route.
#[derive(Clone, Debug, PartialEq)]
pub struct Status {
    pub state: State,
    /// The maneuver ahead, an index into `Route::maneuvers`.
    pub next: usize,
    /// Metres and seconds to the maneuver ahead.
    pub to_next: f64,
    pub time_to_next: f64,
    /// Metres and seconds to the destination.
    pub remaining: f64,
    pub time_remaining: f64,
    /// The fix placed on the route, and the route's bearing there.
    pub position: (f64, f64),
    pub bearing: f64,
    pub off_route: f64,
    /// Ask for a new route from the current fix. Set by one update only.
    pub reroute: bool,
}

#[derive(Clone, Copy)]
struct Reference {
    along: f64,
    accuracy: f64,
}

struct Match {
    along: f64,
    edge: usize,
    position: (f64, f64),
}

pub struct Navigator {
    route: Route,
    /// Recent fixes on the route, oldest first: a new fix must not fall
    /// behind them.
    references: VecDeque<Reference>,
    /// The last fix taken and its accuracy.
    last: Option<((f64, f64), f64)>,
    misses: u32,
    rerouted: Option<f64>,
    status: Status,
}

impl Navigator {
    pub fn new(route: Route) -> Self {
        let start = route.edges[0].from;
        let mut navigator = Self {
            route,
            references: VecDeque::new(),
            last: None,
            misses: 0,
            rerouted: None,
            status: Status {
                state: State::Joining,
                next: 0,
                to_next: 0.0,
                time_to_next: 0.0,
                remaining: 0.0,
                time_remaining: 0.0,
                position: start,
                bearing: 0.0,
                off_route: 0.0,
                reroute: false,
            },
        };
        navigator.place(&Match {
            along: 0.0,
            edge: 0,
            position: start,
        });
        navigator
    }

    pub fn route(&self) -> &Route {
        &self.route
    }

    pub fn status(&self) -> &Status {
        &self.status
    }

    pub fn update(&mut self, fix: &Fix) -> &Status {
        self.status.reroute = false;
        if self.status.state == State::Arrived {
            return &self.status;
        }
        if fix.accuracy > MAX_ACCURACY {
            self.status.state = State::Imprecise;
            self.last = None;
            return &self.status;
        }
        let accuracy = fix.accuracy.max(MIN_ACCURACY);
        let here = (fix.lat, fix.lon);
        if let Some((last, last_accuracy)) = self.last {
            if distance(last, here) < accuracy / 10.0
                && (last_accuracy - accuracy).abs() < accuracy / 10.0
            {
                return &self.status;
            }
        }
        self.last = Some((here, accuracy));
        let rerouted = *self.rerouted.get_or_insert(fix.time);
        let (found, wrong_way) = self.find(here, fix.heading, accuracy);
        if let Some(found) = found {
            self.follow(&found, accuracy, fix.accuracy);
            return &self.status;
        }
        if self.misses <= WRONG_WAY_MISSES {
            self.misses += 1;
        }
        if self.misses > OFF_ROUTE_MISSES {
            self.references.clear();
            if wrong_way {
                self.status.state = State::WrongWay;
                self.status.off_route = 0.0;
            } else {
                self.status.state = State::OffRoute;
                self.status.off_route = self
                    .route
                    .edges
                    .iter()
                    .filter(|e| e.length > 0.0)
                    .map(|e| project(here, e).0)
                    .fold(f64::INFINITY, f64::min);
            }
        }
        let lost = (self.misses > WRONG_WAY_MISSES && self.status.off_route < 1.0)
            || self.status.off_route > 100.0 + fix.accuracy;
        if lost && fix.time - rerouted > REROUTE_INTERVAL {
            self.status.reroute = true;
            self.rerouted = Some(fix.time);
        }
        &self.status
    }

    /// The fix's place on the route, if it has one ahead of the reference
    /// points; and whether the only edges near it run against its heading.
    fn find(&self, here: (f64, f64), heading: Option<f64>, accuracy: f64) -> (Option<Match>, bool) {
        let mut near: Vec<(f64, usize, f64, bool)> = self
            .route
            .edges
            .iter()
            .enumerate()
            .filter(|(_, e)| e.length > 0.0)
            .map(|(i, e)| {
                let (d, t, inside) = project(here, e);
                (d, i, t, inside)
            })
            .filter(|&(d, ..)| d <= accuracy)
            .collect();
        near.sort_by(|a, b| a.0.total_cmp(&b.0));
        near.truncate(CANDIDATES);
        let reference = self.references.front().map(|r| r.along);
        let mut best: Option<Match> = None;
        let mut wrong_way = false;
        for (_, i, t, inside) in near {
            let edge = &self.route.edges[i];
            if let Some(heading) = heading {
                let off = angle_between(heading, edge.bearing);
                if off > 45.0 {
                    wrong_way |= off > 135.0;
                    continue;
                }
            }
            let along = edge.before + t * edge.length;
            // Where the route passes the fix twice, keep to the earlier pass
            // while it is still ahead of the reference points.
            let better = match (&best, reference) {
                (None, _) => true,
                (Some(best), Some(reference)) => {
                    inside
                        && reference - accuracy < along
                        && best.along - along > 2.0 * REF_MARGIN * accuracy
                }
                (Some(_), None) => false,
            };
            if better {
                best = Some(Match {
                    along,
                    edge: i,
                    position: lerp(edge, t),
                });
            }
        }
        let wrong_way = wrong_way && best.is_none();
        let best = best.filter(|b| reference.is_none_or(|r| r - 2.0 * accuracy < b.along));
        (best, wrong_way)
    }

    fn follow(&mut self, found: &Match, accuracy: f64, fix_accuracy: f64) {
        if self
            .references
            .back()
            .is_none_or(|r| (found.along - r.along) / accuracy > REF_MARGIN)
        {
            self.references.push_back(Reference {
                along: found.along,
                accuracy,
            });
        }
        if self.references.len() > REF_POINTS
            || self
                .references
                .front()
                .is_some_and(|r| r.accuracy / 2.0 > accuracy)
        {
            self.references.pop_front();
        }
        let sure = self.references.len() >= REF_POINTS;
        if sure {
            self.misses = 0;
        }
        self.place(found);
        self.status.state = if found.along + fix_accuracy > self.route.length {
            State::Arrived
        } else if sure {
            State::Following
        } else {
            State::Joining
        };
    }

    fn place(&mut self, found: &Match) {
        let route = &self.route;
        let edge = &route.edges[found.edge];
        let maneuver = route.maneuvers[edge.maneuver];
        let (end, end_time) = route
            .maneuvers
            .get(edge.maneuver + 1)
            .map_or((route.length, route.time), |m| (m.distance, m.time));
        let elapsed = if end > maneuver.distance {
            maneuver.time
                + (found.along - maneuver.distance) / (end - maneuver.distance)
                    * (end_time - maneuver.time)
        } else {
            maneuver.time
        };
        let next = (edge.maneuver + 1).min(route.maneuvers.len() - 1);
        let status = &mut self.status;
        status.next = next;
        status.to_next = (route.maneuvers[next].distance - found.along).max(0.0);
        status.time_to_next = (route.maneuvers[next].time - elapsed).max(0.0);
        status.remaining = route.length - found.along;
        status.time_remaining = (route.time - elapsed).max(0.0);
        status.position = found.position;
        status.bearing = edge.bearing;
        status.off_route = 0.0;
    }
}

/// Metres from `p` to the edge; how far along it (0 to 1) the closest
/// point lies; and whether that point is strictly inside it.
fn project(p: (f64, f64), edge: &Edge) -> (f64, f64, bool) {
    let (ax, ay) = local(p, edge.from);
    let (bx, by) = local(p, edge.to);
    let (dx, dy) = (bx - ax, by - ay);
    let t = -(ax * dx + ay * dy) / (dx * dx + dy * dy);
    let inside = t > 0.0 && t < 1.0;
    let t = t.clamp(0.0, 1.0);
    ((ax + t * dx).hypot(ay + t * dy), t, inside)
}

/// `q` in metres east and north of `origin`.
fn local(origin: (f64, f64), q: (f64, f64)) -> (f64, f64) {
    (
        (q.1 - origin.1).to_radians() * origin.0.to_radians().cos() * EARTH_RADIUS,
        (q.0 - origin.0).to_radians() * EARTH_RADIUS,
    )
}

fn lerp(edge: &Edge, t: f64) -> (f64, f64) {
    (
        edge.from.0 + t * (edge.to.0 - edge.from.0),
        edge.from.1 + t * (edge.to.1 - edge.from.1),
    )
}

fn distance(a: (f64, f64), b: (f64, f64)) -> f64 {
    let (lat_a, lat_b) = (a.0.to_radians(), b.0.to_radians());
    let h = ((lat_b - lat_a) / 2.0).sin().powi(2)
        + lat_a.cos() * lat_b.cos() * ((b.1 - a.1).to_radians() / 2.0).sin().powi(2);
    2.0 * EARTH_RADIUS * h.sqrt().asin()
}

fn bearing(a: (f64, f64), b: (f64, f64)) -> f64 {
    let (lat_a, lat_b) = (a.0.to_radians(), b.0.to_radians());
    let dlon = (b.1 - a.1).to_radians();
    let y = dlon.sin() * lat_b.cos();
    let x = lat_a.cos() * lat_b.sin() - lat_a.sin() * lat_b.cos() * dlon.cos();
    y.atan2(x).to_degrees().rem_euclid(360.0)
}

fn angle_between(a: f64, b: f64) -> f64 {
    let d = (a - b).rem_euclid(360.0);
    d.min(360.0 - d)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::float_cmp, reason = "tests")]
mod tests {
    use super::*;

    fn dublin() -> Route {
        let path = format!(
            "{}/tests/fixtures/valhalla-dublin.json",
            env!("CARGO_MANIFEST_DIR")
        );
        let reply = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        Route::from_valhalla(&reply).unwrap()
    }

    /// The route's point `d` metres from the start, and its bearing there.
    fn point_at(route: &Route, d: f64) -> ((f64, f64), f64) {
        let edge = route
            .edges
            .iter()
            .filter(|e| e.length > 0.0)
            .find(|e| d <= e.before + e.length)
            .unwrap_or_else(|| route.edges.last().unwrap());
        (
            lerp(edge, ((d - edge.before) / edge.length).clamp(0.0, 1.0)),
            edge.bearing,
        )
    }

    /// `p` moved `metres` towards `heading`.
    fn moved(p: (f64, f64), heading: f64, metres: f64) -> (f64, f64) {
        let h = heading.to_radians();
        (
            p.0 + (metres * h.cos() / EARTH_RADIUS).to_degrees(),
            p.1 + (metres * h.sin() / (EARTH_RADIUS * p.0.to_radians().cos())).to_degrees(),
        )
    }

    fn fix(p: (f64, f64), heading: Option<f64>, accuracy: f64, time: f64) -> Fix {
        Fix {
            lat: p.0,
            lon: p.1,
            accuracy,
            heading,
            time,
        }
    }

    /// Fixes every `step` metres from `from` to `to` along the route, one a
    /// second from `time`, each `side(n)` metres right of the route.
    fn drive(
        route: &Route,
        from: f64,
        to: f64,
        step: f64,
        time: f64,
        side: impl Fn(u32) -> f64,
    ) -> Vec<Fix> {
        let mut fixes = Vec::new();
        let (mut d, mut t, mut n) = (from, time, 0);
        loop {
            let (p, heading) = point_at(route, d.min(to));
            fixes.push(fix(
                moved(p, heading + 90.0, side(n)),
                Some(heading),
                10.0,
                t,
            ));
            if d >= to {
                return fixes;
            }
            d += step;
            t += 1.0;
            n += 1;
        }
    }

    #[test]
    fn reads_a_valhalla_route() {
        let route = dublin();
        assert_eq!(route.maneuvers.len(), 8);
        // Valhalla's summary: 1.675 km, 367.676 s (its maneuvers' times are rounded).
        assert!((route.length - 1675.0).abs() < 15.0, "{}", route.length);
        assert!((route.time - 367.676).abs() < 0.01, "{}", route.time);
        assert!(route
            .maneuvers
            .windows(2)
            .all(|m| m[0].distance <= m[1].distance));
        assert_eq!(route.maneuvers[7].distance, route.length);
        assert!(Route::from_valhalla(&serde_json::json!({"trip": {}})).is_err());
    }

    #[test]
    fn follows_the_route_through_its_u_turn_to_the_end() {
        let route = dublin();
        let fixes = drive(&route, 0.0, route.length, 10.0, 0.0, |_| 0.0);
        let mut navigator = Navigator::new(route);
        let mut seen = Vec::new();
        let mut remaining = f64::INFINITY;
        for f in &fixes {
            let status = navigator.update(f).clone();
            assert!(!status.reroute);
            assert!(status.remaining <= remaining + 1e-6);
            remaining = status.remaining;
            seen.push((status.state, status.next));
        }
        assert_eq!(seen[0].0, State::Joining);
        let arrival = seen.iter().position(|s| s.0 == State::Arrived).unwrap();
        assert!(fixes.len() - arrival <= 2, "arrives within 10 m of the end");
        assert!(
            seen[5..arrival].iter().all(|s| s.0 == State::Following),
            "{seen:?}"
        );
        assert!(seen[arrival..].iter().all(|s| *s == (State::Arrived, 7)));
        assert!(seen.windows(2).all(|s| s[0].1 <= s[1].1));
        // Every turn is announced in order, the U-turn (6) included.
        let mut nexts: Vec<usize> = seen.iter().map(|s| s.1).collect();
        nexts.dedup();
        assert_eq!(nexts, [1, 2, 3, 4, 5, 6, 7]);
    }

    #[test]
    fn distance_and_time_to_the_next_turn() {
        let route = dublin();
        // 50 m before "Turn right onto Aungier Street".
        let (turn, turn_time) = (route.maneuvers[4].distance, route.maneuvers[4].time);
        let here = turn - 50.0;
        let fixes = drive(&route, 0.0, here, 10.0, 0.0, |_| 0.0);
        let mut navigator = Navigator::new(route);
        for f in &fixes {
            navigator.update(f);
        }
        let status = navigator.status();
        assert_eq!((status.state, status.next), (State::Following, 4));
        assert!((status.to_next - 50.0).abs() < 0.5, "{}", status.to_next);
        let leg = turn - navigator.route().maneuvers[3].distance;
        let expected = 50.0 / leg * (turn_time - navigator.route().maneuvers[3].time);
        assert!(
            (status.time_to_next - expected).abs() < 0.5,
            "{}",
            status.time_to_next
        );
        assert!((status.remaining - (navigator.route().length - here)).abs() < 0.5);
        let after_turn = navigator.route().time - turn_time;
        assert!((status.time_remaining - status.time_to_next - after_turn).abs() < 1e-6);
    }

    #[test]
    fn rides_out_gps_noise() {
        let route = dublin();
        let fixes = drive(&route, 0.0, route.length, 10.0, 0.0, |n| {
            if n % 2 == 0 {
                8.0
            } else {
                -8.0
            }
        });
        let mut navigator = Navigator::new(route);
        for f in &fixes {
            let status = navigator.update(f);
            assert!(!status.reroute);
            assert!(
                !matches!(status.state, State::OffRoute | State::WrongWay),
                "{status:?}"
            );
        }
        assert_eq!(navigator.status().state, State::Arrived);
    }

    #[test]
    fn leaving_the_route_asks_for_a_new_one() {
        let route = dublin();
        let mut fixes = drive(&route, 0.0, 200.0, 10.0, 0.0, |_| 0.0);
        let last = *fixes.last().unwrap();
        // Into the park, 15 m a second.
        let away = last.heading.unwrap() - 90.0;
        for n in 1..=20u32 {
            let t = last.time + f64::from(n);
            fixes.push(fix(
                moved((last.lat, last.lon), away, 15.0 * f64::from(n)),
                Some(away),
                10.0,
                t,
            ));
        }
        let mut navigator = Navigator::new(route);
        let mut log = Vec::new();
        for f in &fixes {
            let status = navigator.update(f);
            log.push((f.time, status.state, status.off_route, status.reroute));
        }
        let t0 = last.time;
        let at = |t: f64| log.iter().find(|l| l.0 == t).unwrap();
        assert_eq!(at(t0).1, State::Following);
        // Three misses keep the last state; the fourth is off the route.
        assert_eq!(at(t0 + 3.0).1, State::Following);
        assert_eq!(at(t0 + 4.0).1, State::OffRoute);
        let reroutes: Vec<_> = log.iter().filter(|l| l.3).collect();
        assert!(!reroutes.is_empty());
        assert!(reroutes[0].2 > 110.0);
        assert!(log
            .iter()
            .filter(|l| l.0 < reroutes[0].0)
            .all(|l| l.2 <= 110.0));
        assert!(reroutes
            .windows(2)
            .all(|r| r[1].0 - r[0].0 > REROUTE_INTERVAL));
    }

    #[test]
    fn driving_the_wrong_way_asks_for_a_new_one() {
        let route = dublin();
        let mut fixes = drive(&route, 0.0, 200.0, 10.0, 0.0, |_| 0.0);
        let t0 = fixes.last().unwrap().time;
        for (n, f) in drive(&route, 50.0, 190.0, 10.0, 0.0, |_| 0.0)
            .iter()
            .rev()
            .enumerate()
        {
            let time = t0 + 1.0 + f64::from(u32::try_from(n).unwrap());
            fixes.push(fix(
                (f.lat, f.lon),
                f.heading.map(|h| h + 180.0),
                10.0,
                time,
            ));
        }
        let mut navigator = Navigator::new(route);
        let log: Vec<_> = fixes
            .iter()
            .map(|f| (f.time, navigator.update(f).clone()))
            .collect();
        let at = |t: f64| &log.iter().find(|l| l.0 == t).unwrap().1;
        assert_eq!(at(t0).state, State::Following);
        assert_eq!(at(t0 + 3.0).state, State::Following);
        assert_eq!(at(t0 + 4.0).state, State::WrongWay);
        assert!(!at(t0 + 5.0).reroute);
        assert!(at(t0 + 6.0).reroute);
        assert!(!at(t0 + 7.0).reroute);
    }

    #[test]
    fn a_fix_that_jumps_back_along_the_route_is_not_taken() {
        let route = dublin();
        let mut fixes = drive(&route, 0.0, 400.0, 10.0, 0.0, |_| 0.0);
        let back = drive(&route, 250.0, 250.0, 10.0, 41.0, |_| 0.0);
        fixes.extend(back);
        let mut navigator = Navigator::new(route);
        for f in &fixes[..fixes.len() - 1] {
            navigator.update(f);
        }
        let before = navigator.status().clone();
        let status = navigator.update(fixes.last().unwrap());
        assert_eq!(status, &before);
    }

    #[test]
    fn a_vague_fix_is_not_placed() {
        let route = dublin();
        let fixes = drive(&route, 0.0, 100.0, 10.0, 0.0, |_| 0.0);
        let mut navigator = Navigator::new(route);
        for f in &fixes {
            navigator.update(f);
        }
        let placed = navigator.status().clone();
        let vague = Fix {
            accuracy: 150.0,
            time: 11.0,
            ..fixes[10]
        };
        let status = navigator.update(&vague);
        assert_eq!(status.state, State::Imprecise);
        assert_eq!(status.remaining, placed.remaining);
        let again = Fix {
            time: 12.0,
            ..fixes[10]
        };
        assert_eq!(navigator.update(&again).state, State::Following);
    }

    #[test]
    fn follows_without_a_heading() {
        let route = dublin();
        let fixes = drive(&route, 0.0, 600.0, 10.0, 0.0, |_| 0.0);
        let mut navigator = Navigator::new(route);
        for f in &fixes {
            let status = navigator.update(&Fix {
                heading: None,
                ..*f
            });
            assert!(!status.reroute);
        }
        assert_eq!(navigator.status().state, State::Following);
        assert_eq!(navigator.status().next, 4);
    }
}
