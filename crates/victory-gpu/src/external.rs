//! Host work that a host library records into a title's command list in
//! place of a console one (the host's FidelityFX upscaler, say): the host
//! device, a title texture's host copy in the state the library is told,
//! and the host list itself.

use std::sync::atomic::{AtomicBool, Ordering};

use windows::Win32::Graphics::Direct3D12::{
    ID3D12Device, ID3D12GraphicsCommandList, ID3D12Resource,
};

use crate::object::Object;

static HOST_FIDELITYFX: AtomicBool = AtomicBool::new(false);

/// Enables compatibility behavior for a successfully loaded host upscaler.
pub fn enable_host_fidelityfx() {
    HOST_FIDELITYFX.store(true, Ordering::Release);
}

pub(crate) fn host_fidelityfx_enabled() -> bool {
    HOST_FIDELITYFX.load(Ordering::Acquire)
}

/// The host D3D12 device, created on first use; `None` without a host GPU.
pub fn host_device() -> Option<ID3D12Device> {
    crate::host::host().map(|h| h.device.clone())
}

/// Outcome of [`run_on_list`].
pub enum ListRun<R> {
    /// Executed synchronously on `list` (non-thin list with a host list).
    Ran(R),
    /// Enqueued onto a `VICTORY_THIN=1` list to run in exact command-list
    /// order on its backing host list.
    Deferred,
    /// `list` is null, closed, or has neither a host list nor a thin recording.
    NoList,
}

/// Runs `f` with the title list `list`: immediately when `list` records
/// directly onto a host list, or enqueued in exact command-list order onto
/// its backing host list when `VICTORY_THIN=1` is active.
pub fn run_on_list<R>(
    list: *const Object,
    f: impl FnOnce(*const Object) -> R + Send + 'static,
) -> ListRun<R> {
    if list.is_null() {
        return ListRun::NoList;
    }
    if crate::list::host_list(list).is_some() {
        return ListRun::Ran(f(list));
    }
    if crate::list::thin::is_thin(list)
        && crate::list::thin::enqueue_external(
            list,
            Box::new(move |back| {
                let _ = f(back);
            }),
        )
    {
        return ListRun::Deferred;
    }
    ListRun::NoList
}

/// Drains queued async submissions (including `VICTORY_THIN=1` translations)
/// and settles in-flight GPU work so an external host context (such as a
/// FidelityFX context) can be safely destroyed.
pub fn drain() {
    crate::queue::before_sync();
    crate::host::settle_for_present();
}

/// A title texture's host copy, moved to the host resource `state` in the
/// title list `list`, and the state it is in: `state` without the bits the
/// host copy cannot take (see `host::legal_state`). What the list records
/// next finds it there and must leave it there. The list holds the texture
/// until it is reset. `None` for a buffer, or without a host list.
pub fn host_texture(
    list: *const Object,
    resource: *const Object,
    state: u32,
) -> Option<(ID3D12Resource, u32)> {
    let host = crate::list::host_list(list)?;
    let texture = crate::resource::host_resource(resource)?.clone();
    // Keep depth textures written via their colour twin coherent before reads,
    // and mark UAV outputs as host-written.
    const UNORDERED_ACCESS: u32 = 0x8;
    if state & UNORDERED_ACCESS != 0 {
        crate::texture::host_written(resource);
    } else {
        host.twin_use(resource, false, false);
    }
    crate::list::ensure_state(host, resource, state);
    let state = crate::host::legal_state(&texture, state);
    Some((texture, state))
}

/// Human-readable reason why [`host_texture`] failed or returned a state other
/// than `wanted` (for diagnostics on error paths).
pub fn diagnose_host_texture(list: *const Object, resource: *const Object, wanted: u32) -> String {
    let has_host_list = crate::list::host_list(list).is_some();
    let thin = crate::list::thin::is_thin(list);
    match crate::resource::host_resource(resource) {
        None => format!(
            "has_host_list={has_host_list} thin={thin} has_host_resource=false wanted={wanted:#x}"
        ),
        Some(tex) => {
            // SAFETY: plain D3D12 descriptor query on a live texture.
            let d = unsafe { tex.GetDesc() };
            let legal = crate::host::legal_state(tex, wanted);
            format!(
                "has_host_list={has_host_list} thin={thin} {}x{} fmt={} flags={:#x} wanted={wanted:#x} legal={legal:#x}",
                d.Width, d.Height, d.Format.0, d.Flags.0
            )
        }
    }
}

/// Runs `f` with the host list behind the title list `list` (open for
/// recording); `None` without one. What `f` binds (descriptor heaps, root
/// signatures, pipeline) is replaced before the list's next draw or
/// dispatch.
pub fn record<R>(
    list: *const Object,
    f: impl FnOnce(&ID3D12GraphicsCommandList) -> R,
) -> Option<R> {
    let mut out = None;
    crate::list::with_state(list, |host, state| {
        out = Some(f(&host.list));
        state.host_state_lost();
    });
    out
}

/// What frame generation needs of an upscaled frame besides its depth and
/// motion vectors: the upscale's constants (as its description has them)
/// and the motion and depth bits of its creation flags.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct FrameInputs {
    pub render: [u32; 2],
    pub jitter: [f32; 2],
    pub motion_scale: [f32; 2],
    pub frame_time_ms: f32,
    pub reset: bool,
    /// Near, far, vertical field of view, metres per view-space unit.
    pub camera: [f32; 4],
    pub flags: u32,
    /// The FidelityFX descriptions of the depth and motion textures.
    pub depth_desc: [u32; 8],
    pub motion_desc: [u32; 8],
}

/// Turns on AMD frame generation for upscaled frames with
/// `amd_fidelityfx_framegeneration_dx12.dll` from `dir`: the presenter's
/// swap chain becomes its proxy. The DLL's path, or why not.
pub fn use_frame_generation(dir: &std::path::Path, ml: bool) -> Result<String, String> {
    crate::framegen::load(dir, ml)
}

/// At a host upscale recorded into the title list `list`: its depth and
/// motion textures (title resources) and constants feed frame generation
/// for the next present, once the list has run. Nothing when it is off.
pub fn frame_generation_inputs(
    list: *const Object,
    depth: *const Object,
    motion: *const Object,
    frame: FrameInputs,
) {
    if !crate::framegen::enabled() {
        return;
    }
    let (Some(host), Some(depth), Some(motion)) = (
        crate::list::host_list(list),
        crate::resource::host_copy(depth),
        crate::resource::host_copy(motion),
    ) else {
        return;
    };
    crate::framegen::record(
        host,
        crate::framegen::Inputs {
            depth,
            motion,
            frame,
            pose: None,
        },
    );
}
