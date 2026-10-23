use evdev::{
    uinput::VirtualDevice, AbsInfo, AbsoluteAxisCode, AttributeSet, EventType, InputEvent, KeyCode,
    UinputAbsSetup,
};
use std::env;
use std::error::Error;
use std::io::{self, BufRead};
use std::str::FromStr;
use std::thread::sleep;
use std::time::Duration;

const ABS_MAX: i32 = 32_767;

fn screen_size() -> Result<(i32, i32), Box<dyn Error>> {
    let framebuffer = std::fs::read_to_string("/sys/class/graphics/fb0/virtual_size")
        .ok()
        .and_then(|value| {
            let (width, height) = value.trim().split_once(',')?;
            Some((width.parse::<i32>().ok()?, height.parse::<i32>().ok()?))
        })
        .unwrap_or((720, 1440));
    let width = env::var("MARATHON_TOUCH_WIDTH")
        .ok()
        .map_or(Ok(framebuffer.0), |value| value.parse::<i32>())?;
    let height = env::var("MARATHON_TOUCH_HEIGHT")
        .ok()
        .map_or(Ok(framebuffer.1), |value| value.parse::<i32>())?;
    if width <= 0 || height <= 0 {
        return Err("touch dimensions must be positive".into());
    }
    Ok((width, height))
}

fn absolute(value: i32, extent: i32) -> i32 {
    i32::try_from(
        (i64::from(value) * i64::from(ABS_MAX) / i64::from(extent)).clamp(0, i64::from(ABS_MAX)),
    )
    .unwrap_or(ABS_MAX)
}

fn interpolate(start: i32, end: i32, step: i32, steps: i32) -> i32 {
    i32::try_from(
        (i64::from(start) * i64::from(steps - step) + i64::from(end) * i64::from(step))
            / i64::from(steps),
    )
    .unwrap_or(end)
}

fn event(kind: EventType, code: u16, value: i32) -> InputEvent {
    InputEvent::new(kind.0, code, value)
}

fn abs(code: AbsoluteAxisCode, value: i32) -> InputEvent {
    event(EventType::ABSOLUTE, code.0, value)
}

fn touch_device(width: i32, height: i32) -> io::Result<VirtualDevice> {
    let mut keys = AttributeSet::<KeyCode>::new();
    keys.insert(KeyCode::BTN_TOUCH);
    let mut builder = VirtualDevice::builder()?
        .name("marathon-touchctl")
        .with_keys(&keys)?;
    for (axis, minimum, maximum, resolution) in [
        (AbsoluteAxisCode::ABS_X, 0, ABS_MAX, ABS_MAX / width),
        (AbsoluteAxisCode::ABS_Y, 0, ABS_MAX, ABS_MAX / height),
        (AbsoluteAxisCode::ABS_MT_SLOT, 0, 4, 0),
        (AbsoluteAxisCode::ABS_MT_TRACKING_ID, -1, 65_535, 0),
        (
            AbsoluteAxisCode::ABS_MT_POSITION_X,
            0,
            ABS_MAX,
            ABS_MAX / width,
        ),
        (
            AbsoluteAxisCode::ABS_MT_POSITION_Y,
            0,
            ABS_MAX,
            ABS_MAX / height,
        ),
    ] {
        builder = builder.with_absolute_axis(&UinputAbsSetup::new(
            axis,
            AbsInfo::new(0, minimum, maximum, 0, 0, resolution),
        ))?;
    }
    builder.build()
}

fn touch_down(device: &mut VirtualDevice, x: i32, y: i32, tracking: i32) -> io::Result<()> {
    device.emit(&[
        abs(AbsoluteAxisCode::ABS_MT_SLOT, 0),
        abs(AbsoluteAxisCode::ABS_MT_TRACKING_ID, tracking),
        abs(AbsoluteAxisCode::ABS_MT_POSITION_X, x),
        abs(AbsoluteAxisCode::ABS_MT_POSITION_Y, y),
        event(EventType::KEY, KeyCode::BTN_TOUCH.0, 1),
        abs(AbsoluteAxisCode::ABS_X, x),
        abs(AbsoluteAxisCode::ABS_Y, y),
    ])
}

fn touch_up(device: &mut VirtualDevice) -> io::Result<()> {
    device.emit(&[
        abs(AbsoluteAxisCode::ABS_MT_SLOT, 0),
        abs(AbsoluteAxisCode::ABS_MT_TRACKING_ID, -1),
        event(EventType::KEY, KeyCode::BTN_TOUCH.0, 0),
    ])
}

fn number(value: Option<&str>, name: &str) -> Result<i32, Box<dyn Error>> {
    value
        .ok_or_else(|| format!("missing {name}"))?
        .parse::<i32>()
        .map_err(Into::into)
}

fn duration(ms: i32) -> Result<Duration, Box<dyn Error>> {
    if !(0..=60_000).contains(&ms) {
        return Err("duration must be between 0 and 60000 ms".into());
    }
    Ok(Duration::from_millis(u64::try_from(ms)?))
}

fn run_command(
    device: &mut VirtualDevice,
    keyboard: &mut Option<(KeyCode, VirtualDevice)>,
    size: (i32, i32),
    line: &str,
) -> Result<(), Box<dyn Error>> {
    let mut parts = line.split_whitespace();
    let Some(command) = parts.next() else {
        return Ok(());
    };
    if command.starts_with('#') {
        return Ok(());
    }
    match command {
        "tap" | "longtap" => {
            let x = absolute(number(parts.next(), "x")?, size.0);
            let y = absolute(number(parts.next(), "y")?, size.1);
            if parts.next().is_some() {
                return Err("too many tap arguments".into());
            }
            touch_down(device, x, y, 1)?;
            sleep(duration(if command == "tap" { 80 } else { 600 })?);
            touch_up(device)?;
        }
        "swipe" => {
            let x1 = absolute(number(parts.next(), "x1")?, size.0);
            let y1 = absolute(number(parts.next(), "y1")?, size.1);
            let x2 = absolute(number(parts.next(), "x2")?, size.0);
            let y2 = absolute(number(parts.next(), "y2")?, size.1);
            let steps = parts.next().map_or(Ok(24), str::parse::<i32>)?;
            if !(1..=240).contains(&steps) || parts.next().is_some() {
                return Err("swipe steps must be between 1 and 240".into());
            }
            touch_down(device, x1, y1, 2)?;
            for step in 1..=steps {
                let x = interpolate(x1, x2, step, steps);
                let y = interpolate(y1, y2, step, steps);
                device.emit(&[
                    abs(AbsoluteAxisCode::ABS_MT_POSITION_X, x),
                    abs(AbsoluteAxisCode::ABS_MT_POSITION_Y, y),
                    abs(AbsoluteAxisCode::ABS_X, x),
                    abs(AbsoluteAxisCode::ABS_Y, y),
                ])?;
                sleep(Duration::from_micros(400_000 / u64::try_from(steps)?));
            }
            touch_up(device)?;
        }
        "key" => {
            let name = parts.next().ok_or("missing key name")?;
            if parts.next().is_some() {
                return Err("too many key arguments".into());
            }
            let code = KeyCode::from_str(name).map_err(|_error| "unknown key name")?;
            if keyboard.as_ref().is_none_or(|(active, _)| *active != code) {
                let mut keys = AttributeSet::<KeyCode>::new();
                keys.insert(code);
                *keyboard = Some((
                    code,
                    VirtualDevice::builder()?
                        .name("marathon-touchctl-keyboard")
                        .with_keys(&keys)?
                        .build()?,
                ));
                sleep(Duration::from_millis(400));
            }
            let (_, keyboard) = keyboard.as_mut().ok_or("keyboard creation failed")?;
            keyboard.emit(&[event(EventType::KEY, code.0, 1)])?;
            sleep(Duration::from_millis(50));
            keyboard.emit(&[event(EventType::KEY, code.0, 0)])?;
        }
        "sleep" => {
            sleep(duration(number(parts.next(), "milliseconds")?)?);
            if parts.next().is_some() {
                return Err("too many sleep arguments".into());
            }
        }
        _ => return Err(format!("unknown command: {command}").into()),
    }
    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    let size = screen_size()?;
    let mut device = touch_device(size.0, size.1)?;
    sleep(Duration::from_millis(400));
    let mut keyboard = None;
    let arguments: Vec<String> = env::args().skip(1).collect();
    if arguments.is_empty() || arguments == ["-"] {
        for line in io::stdin().lock().lines() {
            run_command(&mut device, &mut keyboard, size, &line?)?;
        }
    } else {
        run_command(&mut device, &mut keyboard, size, &arguments.join(" "))?;
    }
    sleep(Duration::from_millis(200));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clamps_coordinates_without_overflow() {
        assert_eq!(absolute(-10, 720), 0);
        assert_eq!(absolute(720, 720), ABS_MAX);
        assert_eq!(absolute(i32::MAX, 720), ABS_MAX);
    }

    #[test]
    fn rejects_unbounded_waits() {
        assert!(duration(-1).is_err());
        assert!(duration(60_001).is_err());
    }

    #[test]
    fn reverse_swipe_interpolation_matches_absolute_pixel_path() {
        assert_eq!(interpolate(ABS_MAX, 0, 1, 24), 31_401);
        assert_eq!(interpolate(ABS_MAX, 0, 24, 24), 0);
        assert_eq!(interpolate(0, ABS_MAX, 24, 24), ABS_MAX);
    }
}
