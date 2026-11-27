//! Write-combining title memory left on the card (`VICTORY_SKIP_WC_BACK`, on by default).
//!
//! Memory the title reserves write-combined (console protection bit `0x400`) is memory its CPU
//! writes and does not read back: what shaders write into buffers of `>= VICTORY_SKIP_WC_MIN_KB`
//! (`1024` KiB by default) stays on the card instead of being fetched back every frame.

use std::collections::BTreeMap;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

static WC: Mutex<BTreeMap<usize, usize>> = Mutex::new(BTreeMap::new());
static SKIPPED: [AtomicU64; 2] = [const { AtomicU64::new(0) }; 2];

fn setting(names: [&str; 2]) -> Option<String> {
    names.iter().find_map(|n| std::env::var(n).ok()).map(|v| v.trim().to_string())
}

/// `VICTORY_SKIP_WC_BACK` / `KLBF_SKIP_WC_BACK`: on unless `"0"` (off cost ~40 ms/frame of copy-back, bb89970).
///
/// With it off, GTA VI reserves nearly all of its GPU heap write-combined,
/// and with renderer port 1 the buffers still fetched back are the aliased /
/// multi-section ones (vehicle deformation and skinning output among them).
/// Turning it off did not fix frozen body panels (user test after bb89970).
pub(crate) fn skip_wc_back() -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| {
        let on = setting(["KLBF_SKIP_WC_BACK", "VICTORY_SKIP_WC_BACK"]).is_none_or(|v| v != "0");
        if on {
            tracing::info!(
                "write-combining title memory >= 1 MiB stays on the card (VICTORY_SKIP_WC_BACK=0 to fetch back)"
            );
        }
        on
    })
}

fn big_enough(len: u64) -> bool {
    static MIN: std::sync::OnceLock<u64> = std::sync::OnceLock::new();
    let min = *MIN.get_or_init(|| {
        setting(["KLBF_SKIP_WC_MIN_KB", "VICTORY_SKIP_WC_MIN_KB"])
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(1024)
            .saturating_mul(1024)
    });
    len >= min
}

/// Records `[at, at + len)` when reserved with write-combining protection (`0x400`).
pub fn title_memory_reserved(at: usize, len: usize, protect: u32) {
    if protect & 0x400 == 0 || at == 0 || len == 0 || !skip_wc_back() {
        return;
    }
    WC.lock().unwrap_or_else(|e| e.into_inner()).insert(at, len);
}

fn in_wc(map: &BTreeMap<usize, usize>, (from, to): (usize, usize)) -> bool {
    map.range(..=from)
        .next_back()
        .is_some_and(|(&base, &len)| base.checked_add(len).is_some_and(|end| to <= end))
}

/// True when `declared` lies inside a write-combining reservation of at least `VICTORY_SKIP_WC_MIN_KB`.
pub(crate) fn skip_back(buffer_len: u64, declared: (usize, usize), bytes: u64) -> bool {
    if !skip_wc_back() || !big_enough(buffer_len) || declared.0 >= declared.1 {
        return false;
    }
    let wc = in_wc(&WC.lock().unwrap_or_else(|e| e.into_inner()), declared);
    if wc {
        let n = SKIPPED[0].fetch_add(1, Ordering::Relaxed) + 1;
        let b = SKIPPED[1].fetch_add(bytes, Ordering::Relaxed) + bytes;
        if n.is_power_of_two() {
            tracing::info!(
                "VICTORY_SKIP_WC_BACK: {n} pieces ({} MB) of write-combining memory left on the card so far",
                b >> 20
            );
        }
    }
    wc
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_range_is_write_combining_only_inside_one_reservation() {
        let map = BTreeMap::from([(0x1000, 0x1000), (0x4000, 0x2000)]);
        assert!(in_wc(&map, (0x1000, 0x2000)));
        assert!(in_wc(&map, (0x4800, 0x5000)));
        assert!(!in_wc(&map, (0x1800, 0x2800)), "past its end");
        assert!(!in_wc(&map, (0x800, 0x1800)), "before its start");
        assert!(!in_wc(&map, (0x3000, 0x3800)), "between two");
    }
}
