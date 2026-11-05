//! Constant-velocity filter over the epoch solutions: smooths a still
//! receiver, follows a moving one, and refuses a solution its innovation says
//! is inconsistent with the track. Only positions are measured: a Doppler
//! velocity needs five satellites of one system and was still 1-2 m/s off.

use nalgebra::{Matrix3, SMatrix, SVector, Vector3};

type V6 = SVector<f64, 6>;
type M6 = SMatrix<f64, 6, 6>;
type M36 = SMatrix<f64, 3, 6>;

/// White acceleration spectral density, m²/s³.
const ACCEL: f64 = 1.0;
/// Velocity sigma of a new track, m/s.
const START_SPEED: f64 = 30.0;
/// Squared innovation distance beyond which a solution is refused
/// (chi-square, 3 degrees of freedom, 0.1 %).
const GATE: f64 = 16.3;
/// After this many refusals in a row the track is presumed wrong.
const MAX_REFUSED: u32 = 5;

#[derive(Default)]
pub struct Filter {
    state: Option<(V6, M6, f64)>,
    refused: u32,
}

impl Filter {
    /// Folds in a solution at time `t` with position sigma `sigma`. Returns
    /// the filtered position, or `None` when the solution was refused.
    #[allow(clippy::many_single_char_names, reason = "usual Kalman symbols")]
    pub fn update(&mut self, t: f64, pos: Vector3<f64>, sigma: f64) -> Option<Vector3<f64>> {
        let r = Matrix3::from_diagonal_element(sigma * sigma);
        let Some((x, p, at)) = self.state else {
            return Some(self.reset(t, pos, sigma));
        };
        let dt = (t - at).max(0.0);
        let mut f = M6::identity();
        f.fixed_view_mut::<3, 3>(0, 3).fill_diagonal(dt);
        let mut q = M6::zeros();
        q.fixed_view_mut::<3, 3>(0, 0)
            .fill_diagonal(ACCEL * dt.powi(3) / 3.0);
        q.fixed_view_mut::<3, 3>(0, 3)
            .fill_diagonal(ACCEL * dt * dt / 2.0);
        q.fixed_view_mut::<3, 3>(3, 0)
            .fill_diagonal(ACCEL * dt * dt / 2.0);
        q.fixed_view_mut::<3, 3>(3, 3).fill_diagonal(ACCEL * dt);
        let x = f * x;
        let p = f * p * f.transpose() + q;
        let h = M36::identity();
        let s_inv = (h * p * h.transpose() + r).try_inverse()?;
        let y = pos - h * x;
        if (y.transpose() * s_inv * y)[0] > GATE {
            if self.refused < MAX_REFUSED {
                self.refused += 1;
                return None;
            }
            return Some(self.reset(t, pos, sigma));
        }
        self.refused = 0;
        let k = p * h.transpose() * s_inv;
        let x = x + k * y;
        let p = (M6::identity() - k * h) * p;
        self.state = Some((x, p, t));
        Some(x.fixed_rows::<3>(0).into())
    }

    fn reset(&mut self, t: f64, pos: Vector3<f64>, sigma: f64) -> Vector3<f64> {
        let mut x = V6::zeros();
        x.fixed_rows_mut::<3>(0).copy_from(&pos);
        let mut p = M6::zeros();
        p.fixed_view_mut::<3, 3>(0, 0).fill_diagonal(sigma * sigma);
        p.fixed_view_mut::<3, 3>(3, 3)
            .fill_diagonal(START_SPEED * START_SPEED);
        self.refused = 0;
        self.state = Some((x, p, t));
        pos
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn follows_motion_and_refuses_a_jump() {
        let mut f = Filter::default();
        let v = Vector3::new(10.0, 0.0, 0.0);
        for i in 0..60 {
            let t = f64::from(i);
            let noise = if i % 2 == 0 { 15.0 } else { -15.0 };
            let p = f
                .update(t, v * t + Vector3::new(0.0, noise, 0.0), 15.0)
                .unwrap();
            if i > 20 {
                assert!((p - v * t).norm() < 10.0, "{i} {p}");
            }
        }
        let jump = v * 60.0 + Vector3::new(0.0, 300.0, 0.0);
        assert!(f.update(60.0, jump, 15.0).is_none());
    }
}
