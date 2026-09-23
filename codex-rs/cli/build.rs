/// Windows: reserve a larger main-thread stack for the `codex` executable.
///
/// Windows interactive `/resume` can overflow the 8 MiB default main stack
/// (STATUS_STACK_OVERFLOW in `tokio-runtime-worker`) when large session
/// histories are reloaded. `RUST_MIN_STACK` does not help: it only affects
/// runtime-spawned tokio threads, not the thread that `main` runs on. The
/// linker `/STACK` reserve is the fix and is verified for this case.
///
/// This only affects the `codex` executable of this crate, not other
/// workspace binaries. Set `CODEX_CLI_WINDOWS_STACK` to override the size
/// (bytes) when building this crate.
fn main() {
    #[cfg(all(target_os = "windows", target_env = "msvc"))]
    {
        let stack = std::env::var("CODEX_CLI_WINDOWS_STACK")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(33_554_432);
        let mut args = format!("/STACK:{stack}");
        if std::env::var("CARGO_CFG_TARGET_ARCH").as_deref() == Ok("aarch64") {
            args.push_str(",131072");
        }
        println!("cargo:rustc-link-arg={args}");
    }

    #[cfg(all(target_os = "windows", target_env = "gnu"))]
    {
        let stack = std::env::var("CODEX_CLI_WINDOWS_STACK")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(33_554_432);
        println!("cargo:rustc-link-arg=-Wl,--stack,{stack}");
    }
}
