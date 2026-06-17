//! A small, dependency-free cron-expression engine: parse a standard 5-field expression
//! (`minute hour day-of-month month day-of-week`) and compute the next fire time after a
//! given instant.
//!
//! Hand-rolled (no `cron`/`chrono` crate) to honour the workspace's minimal-dependency
//! convention and keep the low-resource footprint small. Time is **UTC**. Fields support
//! `*`, `*/step`, `a-b`, `a-b/step`, `a/step`, single values, and comma-separated lists.
//! Day-of-week is `0-6` with Sunday `0` (and `7` also accepted for Sunday). When **both**
//! day-of-month and day-of-week are restricted, a minute matches if **either** matches —
//! the Vixie-cron convention.

use std::time::{SystemTime, UNIX_EPOCH};

/// A parsed cron schedule. Each field is a bitset of permitted values plus a `star` flag
/// recording whether the field was an unrestricted `*` (needed for the day-of-month/-week
/// OR rule).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CronSchedule {
    minute: Field,
    hour: Field,
    dom: Field,
    month: Field,
    dow: Field,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Field {
    /// Bit `v` set ⇔ value `v` is permitted.
    mask: u64,
    /// True ⇔ the field was exactly `*` (unrestricted).
    star: bool,
}

impl Field {
    fn matches(self, v: u32) -> bool {
        self.mask & (1u64 << v) != 0
    }
}

/// A failure parsing a cron expression.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum CronError {
    /// The expression did not have exactly five whitespace-separated fields.
    #[error("expected 5 cron fields (min hour dom month dow), got {0}")]
    FieldCount(usize),
    /// A field was malformed or out of range.
    #[error("invalid cron field {field:?}: {reason}")]
    Field { field: String, reason: String },
}

/// Broken-down UTC wall-clock components used for matching.
struct Civil {
    minute: u32,
    hour: u32,
    dom: u32,
    month: u32,
    /// Day of week, Sunday = 0.
    dow: u32,
}

impl CronSchedule {
    /// Parse a standard 5-field cron expression. Returns [`CronError`] on a bad field count
    /// or an out-of-range / malformed field.
    pub fn parse(expr: &str) -> Result<Self, CronError> {
        let fields: Vec<&str> = expr.split_whitespace().collect();
        if fields.len() != 5 {
            return Err(CronError::FieldCount(fields.len()));
        }
        Ok(Self {
            minute: parse_field(fields[0], 0, 59, false)?,
            hour: parse_field(fields[1], 0, 23, false)?,
            dom: parse_field(fields[2], 1, 31, false)?,
            month: parse_field(fields[3], 1, 12, false)?,
            dow: parse_field(fields[4], 0, 6, true)?,
        })
    }

    /// The next fire time (Unix seconds, aligned to a minute boundary) strictly **after**
    /// `after_unix_secs`. Returns `None` if the schedule has no fire within ~4 years (e.g. an
    /// impossible date like Feb 30), so the caller can disable the job rather than spin.
    pub fn next_after(&self, after_unix_secs: u64) -> Option<u64> {
        // First whole minute strictly after the given instant.
        let mut t = (after_unix_secs / 60 + 1) * 60;
        // ~4 years of minutes bounds the worst legitimate gap (Feb 29 yearly schedules).
        let cap = t + 4 * 366 * 24 * 60 * 60;
        while t <= cap {
            if self.matches(&civil_from_unix(t)) {
                return Some(t);
            }
            t += 60;
        }
        None
    }

    /// Convenience: next fire time after *now* (UTC), as a [`SystemTime`]-derived Unix second
    /// count. `None` mirrors [`next_after`](Self::next_after).
    pub fn next_after_now(&self) -> Option<u64> {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        self.next_after(now)
    }

    fn matches(&self, c: &Civil) -> bool {
        let day_ok = match (self.dom.star, self.dow.star) {
            (true, true) => true,
            (false, true) => self.dom.matches(c.dom),
            (true, false) => self.dow.matches(c.dow),
            // Both restricted ⇒ OR (Vixie convention).
            (false, false) => self.dom.matches(c.dom) || self.dow.matches(c.dow),
        };
        self.minute.matches(c.minute)
            && self.hour.matches(c.hour)
            && self.month.matches(c.month)
            && day_ok
    }
}

/// Parse one cron field into a bitset over `[min, max]`. `dow` enables the `7 == Sunday`
/// alias (folded onto `0`).
fn parse_field(field: &str, min: u32, max: u32, dow: bool) -> Result<Field, CronError> {
    let bad = |reason: &str| CronError::Field {
        field: field.to_string(),
        reason: reason.to_string(),
    };
    let star = field.trim() == "*";
    let mut mask = 0u64;

    for part in field.split(',') {
        // Split an optional `/step` suffix.
        let (range, step) = match part.split_once('/') {
            Some((r, s)) => {
                let step: u32 = s.parse().map_err(|_| bad("step is not a number"))?;
                if step == 0 {
                    return Err(bad("step must be >= 1"));
                }
                (r, step)
            }
            None => (part, 1),
        };

        // Resolve the range the step walks over.
        let (lo, hi) = if range == "*" {
            (min, max)
        } else if let Some((a, b)) = range.split_once('-') {
            let a: u32 = a.parse().map_err(|_| bad("range start is not a number"))?;
            let b: u32 = b.parse().map_err(|_| bad("range end is not a number"))?;
            (a, b)
        } else {
            let v: u32 = range.parse().map_err(|_| bad("value is not a number"))?;
            // `N/step` means N through max stepping by `step`; a bare `N` is just N.
            if part.contains('/') {
                (v, max)
            } else {
                (v, v)
            }
        };

        if lo > hi {
            return Err(bad("range start is greater than range end"));
        }
        let mut v = lo;
        while v <= hi {
            // dow allows 7 as an alias for Sunday (0); folding it makes 7 in-range.
            let val = if dow && v == 7 { 0 } else { v };
            if val < min || val > max {
                return Err(bad("value out of range"));
            }
            mask |= 1u64 << val;
            v += step;
        }
    }

    Ok(Field { mask, star })
}

/// Decompose a Unix-second instant into UTC wall-clock components. Uses Howard Hinnant's
/// `days → civil` algorithm (exact, branch-light, no external date library).
fn civil_from_unix(secs: u64) -> Civil {
    let secs = secs as i64;
    let days = secs.div_euclid(86_400);
    let sod = secs.rem_euclid(86_400);
    let hour = (sod / 3_600) as u32;
    let minute = ((sod % 3_600) / 60) as u32;
    // 1970-01-01 was a Thursday; Sunday = 0.
    let dow = (days.rem_euclid(7) + 4).rem_euclid(7) as u32;

    // days-from-civil inverse (Hinnant). `z` shifts the epoch to 0000-03-01.
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097; // [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365; // [0, 399]
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = doy - (153 * mp + 2) / 5 + 1; // [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 }; // [1, 12]
    let year_adjusted_month = m; // month already 1..=12
    let _ = y; // year not needed for matching

    Civil {
        minute,
        hour,
        dom: d as u32,
        month: year_adjusted_month as u32,
        dow,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sched(e: &str) -> CronSchedule {
        CronSchedule::parse(e).expect("valid")
    }

    #[test]
    fn civil_epoch_is_thursday() {
        let c = civil_from_unix(0);
        assert_eq!((c.month, c.dom, c.hour, c.minute), (1, 1, 0, 0));
        assert_eq!(c.dow, 4); // Thursday
    }

    #[test]
    fn civil_known_timestamp() {
        // 1_700_000_000 = 2023-11-14 22:13:20 UTC, a Tuesday.
        let c = civil_from_unix(1_700_000_000);
        assert_eq!((c.month, c.dom), (11, 14));
        assert_eq!((c.hour, c.minute), (22, 13));
        assert_eq!(c.dow, 2);
    }

    #[test]
    fn every_minute_matches_next_minute() {
        let s = sched("* * * * *");
        // 100 seconds past a minute boundary → fires at the next boundary (120).
        assert_eq!(s.next_after(100), Some(120));
        assert_eq!(s.next_after(120), Some(180));
    }

    #[test]
    fn step_minutes() {
        let s = sched("*/15 * * * *");
        // Minutes 0,15,30,45 only.
        let t = s.next_after(0).unwrap();
        let c = civil_from_unix(t);
        assert!(matches!(c.minute, 0 | 15 | 30 | 45));
        // From 16:07:00, the next quarter-hour is 16:15 → minute 15.
        let base = 16 * 3600 + 7 * 60;
        assert_eq!(civil_from_unix(s.next_after(base).unwrap()).minute, 15);
    }

    #[test]
    fn daily_midnight() {
        let s = sched("0 0 * * *");
        // From just after an arbitrary midday, the next fire is the following midnight.
        let noon = 1_700_000_000; // 2023-11-14 22:13:20
        let next = s.next_after(noon).unwrap();
        let c = civil_from_unix(next);
        assert_eq!((c.hour, c.minute), (0, 0));
        assert_eq!(c.dom, 15); // next midnight is the 15th
    }

    #[test]
    fn weekday_range() {
        // 09:30 Mon–Fri.
        let s = sched("30 9 * * 1-5");
        let next = s.next_after(1_700_000_000).unwrap();
        let c = civil_from_unix(next);
        assert_eq!((c.hour, c.minute), (9, 30));
        assert!((1..=5).contains(&c.dow));
    }

    #[test]
    fn sunday_seven_alias() {
        let a = sched("0 0 * * 0");
        let b = sched("0 0 * * 7");
        // Both should fire on the same next Sunday midnight.
        assert_eq!(a.next_after(0), b.next_after(0));
        assert_eq!(civil_from_unix(a.next_after(0).unwrap()).dow, 0);
    }

    #[test]
    fn dom_or_dow_when_both_restricted() {
        // 1st of the month OR Mondays.
        let s = sched("0 0 1 * 1");
        let next = s.next_after(0).unwrap();
        let c = civil_from_unix(next);
        assert!(c.dom == 1 || c.dow == 1);
    }

    #[test]
    fn list_and_range() {
        let s = sched("0,30 9-17 * * *");
        let c = civil_from_unix(s.next_after(0).unwrap());
        assert!(c.minute == 0 || c.minute == 30);
        assert!((9..=17).contains(&c.hour));
    }

    #[test]
    fn impossible_date_has_no_fire() {
        // Feb 30 never occurs.
        let s = sched("0 0 30 2 *");
        assert_eq!(s.next_after(0), None);
    }

    #[test]
    fn rejects_bad_expressions() {
        assert_eq!(
            CronSchedule::parse("* * * *"),
            Err(CronError::FieldCount(4))
        );
        assert!(CronSchedule::parse("60 * * * *").is_err()); // minute out of range
        assert!(CronSchedule::parse("* 24 * * *").is_err()); // hour out of range
        assert!(CronSchedule::parse("*/0 * * * *").is_err()); // zero step
        assert!(CronSchedule::parse("5-1 * * * *").is_err()); // inverted range
        assert!(CronSchedule::parse("x * * * *").is_err()); // non-numeric
    }
}
