# VIctory AMD

An AMD Radeon-tuned fork of [VIctory](https://github.com/Marvisak/VIctory), a
compatibility layer that runs Xbox Series titles natively on Windows, from
files you supply yourself. Built on the work of the community forks credited
below. Tuned and tested on RDNA4 (RX 9070 XT); RDNA2 and RDNA3 are supported by
the installer but less tested.

**This repository contains no game content of any kind**: no executables,
assets, shaders, or data from any title, and no instructions for obtaining
them. You need your own legally obtained copy of a title. See
[docs/asset-policy.md](docs/asset-policy.md).

## What this fork changes

- Performance on AMD: skipped residency waits for short-lived buffers (the
  main source of hitches), high process priority, a below-normal cleanup
  thread, frame pacing on the title thread instead of the submit thread.
- Texture streaming: oldest-first texture queue, mip upgrades on a background
  copy queue (2-4 workers), a texture size cap that scales with free VRAM.
- AMD FidelityFX: FSR upscaling and frame generation through the official
  FidelityFX SDK DLLs (FSR 4 on RDNA4; the SDK picks FSR 4.1 or 3.1 on RDNA2/3).
- Keyboard and mouse controls, F9 frame capture in diagnostics builds.

## Install (Windows, AMD RX 6000 / 7000 / 9000)

1. Download the zip from [Releases](../../releases) and extract it next to the
   title's executable.
2. Run `INSTALL.bat` (not as administrator). It detects your GPU and writes
   launchers tuned for it.

Requirements: 16 GB VRAM recommended, 32 GB RAM, a fast 8-core CPU (the layer
is CPU-bound), current Adrenalin driver, Visual C++ 2015-2022 x64 runtime.

## Build from source

```
cargo build --release --locked -p victory
```

The installer scripts are in [installer/](installer/).

## Credits

- [Marvisak/VIctory](https://github.com/Marvisak/VIctory) (original project)
- [DexNom/VIctory](https://github.com/DexNom/VIctory)
- [avatarmanz/VIctory-7900XTX](https://github.com/avatarmanz/VIctory-7900XTX)
- [Belobug/VIctory-Belobug-AMD](https://github.com/Belobug/VIctory-Belobug-AMD)
- [fxceless/victory-fork](https://github.com/fxceless/victory-fork)

## License

GPL-3.0, see [LICENSE](LICENSE). The AMD FidelityFX DLLs shipped in releases
are AMD's, redistributed under [AMD's license](third_party/AMD-FidelityFX-SDK-LICENSE.md).
This project is not affiliated with or endorsed by Microsoft, AMD, or any game
publisher. All trademarks belong to their owners.
