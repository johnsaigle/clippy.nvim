# clippy.nvim

Adds lint results from `cargo clippy` to neovim's built-in diagnostics.

`rust-analyzer` is supposed to be able to do this but it seems broken (at least for neovim).

## Install

### Lazy

```lua
  { -- Clippy diagnostics
    'johnsaigle/clippy.nvim',
    dependencies = { "jose-elias-alvarez/null-ls.nvim" },
  },
```
