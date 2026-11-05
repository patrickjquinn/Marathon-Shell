//! Klobuchar ionospheric delay (IS-GPS-200 20.3.3.5.2.5).

use std::f64::consts::PI;

/// L1 group delay in seconds for a receiver at `lat`, `lon` (radians), a
/// satellite at azimuth `az` and elevation `el` (radians), at GPS time of
/// week `t`, from the broadcast coefficients.
#[allow(clippy::many_single_char_names, reason = "ICD symbols")]
pub fn delay(k: &[f64; 8], lat: f64, lon: f64, az: f64, el: f64, t: f64) -> f64 {
    // The ICD works in semicircles.
    let (phi_u, lam_u, e) = (lat / PI, lon / PI, el / PI);
    let psi = 0.0137 / (e + 0.11) - 0.022;
    let phi_i = (phi_u + psi * az.cos()).clamp(-0.416, 0.416);
    let lam_i = lam_u + psi * az.sin() / (phi_i * PI).cos();
    let phi_m = phi_i + 0.064 * ((lam_i - 1.617) * PI).cos();
    let tl = (4.32e4 * lam_i + t).rem_euclid(86_400.0);
    let f = 1.0 + 16.0 * (0.53 - e).powi(3);
    let amp = (k[0] + phi_m * (k[1] + phi_m * (k[2] + phi_m * k[3]))).max(0.0);
    let per = (k[4] + phi_m * (k[5] + phi_m * (k[6] + phi_m * k[7]))).max(72_000.0);
    let x = 2.0 * PI * (tl - 50_400.0) / per;
    let night = 5e-9;
    if x.abs() < 1.57 {
        f * (night + amp * (1.0 - x * x / 2.0 + x.powi(4) / 24.0))
    } else {
        f * night
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn night_floor_and_daytime_peak() {
        let k = [1.1e-8, 0.0, -6.0e-8, 0.0, 9.0e4, 0.0, -2.0e5, 0.0];
        let (lat, lon) = (53.26f64.to_radians(), -6.13f64.to_radians());
        let zenith = PI / 2.0;
        // 02:00 local: the 5 ns night value, times the obliquity of 1.
        let night = delay(&k, lat, lon, 0.0, zenith, 2.0 * 3600.0 + 1800.0);
        assert!((night - 5e-9).abs() < 1e-10, "{night}");
        // 14:00 local, low elevation: larger than at zenith.
        let noon = delay(&k, lat, lon, 0.0, zenith, 14.0 * 3600.0 + 1800.0);
        let low = delay(
            &k,
            lat,
            lon,
            0.0,
            15f64.to_radians(),
            14.0 * 3600.0 + 1800.0,
        );
        assert!(noon > 5e-9 && low > 1.5 * noon, "{noon} {low}");
    }
}
