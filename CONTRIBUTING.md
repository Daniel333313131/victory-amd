# Contributing

Bug reports and pull requests are welcome.

## Ground rules (no exceptions)

- **No game content.** Never commit, attach or link game files, dumps, extracted
  assets, shader dumps or screenshots of copyrighted content. See
  [docs/asset-policy.md](docs/asset-policy.md). Issues or PRs that do are closed.
- **No piracy talk.** Do not ask or explain where to get a title.
- Be civil.

## Reporting bugs

Use the bug report form. Always include the newest log from `_victory-logs\`
and your GPU, driver, CPU and RAM.

## Pull requests

- One change per PR, behind an environment switch if it changes behaviour.
- Say what you measured: fps median, frames over 100 ms, before and after,
  same launcher, same place in the game.
- `cargo build --release --locked -p victory` must build without warnings.
- Do not run the full `cargo test -p victory-gpu` suite on a PC you care about:
  its replay tests drive the real GPU and have crashed AMD drivers. Run targeted
  tests (`cargo test -p victory-gpu --lib -- <name>`).

By contributing you agree your code is licensed under GPL-3.0.
