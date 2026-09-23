use super::*;
use async_trait::async_trait;
use codex_file_system::CopyOptions;
use codex_file_system::CreateDirectoryOptions;
use codex_file_system::FileMetadata;
use codex_file_system::FileSystemResult;
use codex_file_system::FileSystemSandboxContext;
use codex_file_system::ReadDirectoryEntry;
use codex_file_system::RemoveOptions;
use pretty_assertions::assert_eq;
use std::path::Path;
use tempfile::tempdir;

struct TestFileSystem;

#[async_trait]
impl ExecutorFileSystem for TestFileSystem {
    async fn canonicalize(
        &self,
        path: &AbsolutePathBuf,
        _sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<AbsolutePathBuf> {
        path.canonicalize()
    }

    async fn join(
        &self,
        base_path: &AbsolutePathBuf,
        path: &Path,
    ) -> FileSystemResult<AbsolutePathBuf> {
        Ok(base_path.join(path))
    }

    async fn parent(&self, path: &AbsolutePathBuf) -> FileSystemResult<Option<AbsolutePathBuf>> {
        Ok(path.parent())
    }

    async fn read_file(
        &self,
        path: &AbsolutePathBuf,
        _sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<Vec<u8>> {
        tokio::fs::read(path.as_path()).await
    }

    async fn write_file(
        &self,
        _path: &AbsolutePathBuf,
        _contents: Vec<u8>,
        _sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<()> {
        unimplemented!("test filesystem only supports reads")
    }

    async fn create_directory(
        &self,
        _path: &AbsolutePathBuf,
        _create_directory_options: CreateDirectoryOptions,
        _sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<()> {
        unimplemented!("test filesystem only supports reads")
    }

    async fn get_metadata(
        &self,
        path: &AbsolutePathBuf,
        _sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<FileMetadata> {
        let metadata = tokio::fs::symlink_metadata(path.as_path()).await?;
        Ok(FileMetadata {
            is_directory: metadata.is_dir(),
            is_file: metadata.is_file(),
            is_symlink: metadata.file_type().is_symlink(),
            created_at_ms: 0,
            modified_at_ms: 0,
        })
    }

    async fn read_directory(
        &self,
        _path: &AbsolutePathBuf,
        _sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<Vec<ReadDirectoryEntry>> {
        unimplemented!("test filesystem only supports reads")
    }

    async fn remove(
        &self,
        _path: &AbsolutePathBuf,
        _remove_options: RemoveOptions,
        _sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<()> {
        unimplemented!("test filesystem only supports reads")
    }

    async fn copy(
        &self,
        _source_path: &AbsolutePathBuf,
        _destination_path: &AbsolutePathBuf,
        _copy_options: CopyOptions,
        _sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<()> {
        unimplemented!("test filesystem only supports reads")
    }
}

#[tokio::test]
async fn custom_codex_home_does_not_load_default_home_config_as_project_config() -> io::Result<()> {
    let tmp = tempdir()?;
    let home = tmp.path().join("Users").join("Veysel");
    let cwd = home.join("Desktop").join("some-folder");
    let project_config_dir = cwd.join(".codex");
    let default_user_codex_home = home.join(".codex");
    let custom_codex_home = home.join(".codex-ninfer");
    tokio::fs::create_dir_all(&project_config_dir).await?;
    tokio::fs::create_dir_all(&default_user_codex_home).await?;
    tokio::fs::create_dir_all(&custom_codex_home).await?;
    tokio::fs::write(home.join(".git"), "gitdir: here").await?;
    tokio::fs::write(
        default_user_codex_home.join(CONFIG_TOML_FILE),
        "model = \"gpt-6-sol\"\nnotify = [\"unexpected\"]\n",
    )
    .await?;
    tokio::fs::write(
        custom_codex_home.join(CONFIG_TOML_FILE),
        "model = \"qwen3.8-27b\"\nmodel_reasoning_effort = \"none\"\n",
    )
    .await?;
    tokio::fs::write(
        project_config_dir.join(CONFIG_TOML_FILE),
        "web_search = \"disabled\"\n",
    )
    .await?;

    let home_abs = AbsolutePathBuf::from_absolute_path(&home)?;
    let cwd_abs = AbsolutePathBuf::from_absolute_path(&cwd)?;
    let home_key = project_trust_key(&home);
    let trust_context = ProjectTrustContext {
        project_root: home_abs.clone(),
        project_root_key: home_key.clone(),
        project_root_lookup_keys: vec![home_key.clone()],
        checkout_root: None,
        repo_root: None,
        repo_root_key: None,
        repo_root_lookup_keys: None,
        projects_trust: std::collections::HashMap::from([(home_key, TrustLevel::Trusted)]),
        user_config_file: AbsolutePathBuf::from_absolute_path(
            custom_codex_home.join(CONFIG_TOML_FILE),
        )?,
    };
    let project_layers = load_project_layers(
        &TestFileSystem,
        &cwd_abs,
        &home_abs,
        &trust_context,
        &custom_codex_home,
        Some(&default_user_codex_home),
        /*strict_config*/ false,
    )
    .await?;

    let mut merged: TomlValue =
        toml::from_str(&tokio::fs::read_to_string(custom_codex_home.join(CONFIG_TOML_FILE)).await?)
            .expect("parse custom user config");
    for layer in &project_layers.layers {
        merge_toml_values(&mut merged, &layer.config);
    }
    assert_eq!(
        project_layers
            .layers
            .iter()
            .map(|layer| layer.name.clone())
            .collect::<Vec<_>>(),
        vec![ConfigLayerSource::Project {
            dot_codex_folder: AbsolutePathBuf::from_absolute_path(project_config_dir)?,
        }]
    );
    assert_eq!(project_layers.startup_warnings, Vec::<String>::new());
    assert_eq!(
        merged.get("model").and_then(TomlValue::as_str),
        Some("qwen3.8-27b")
    );
    assert_eq!(
        merged
            .get("model_reasoning_effort")
            .and_then(TomlValue::as_str),
        Some("none")
    );
    assert_eq!(merged.get("notify"), None);
    assert_eq!(
        merged.get("web_search").and_then(TomlValue::as_str),
        Some("disabled")
    );
    Ok(())
}

#[tokio::test]
async fn profile_v2_rejects_matching_legacy_profile_in_base_user_config() {
    let tmp = tempdir().expect("tempdir");
    let selected_config = tmp.path().join("work.config.toml");

    std::fs::write(
        tmp.path().join(CONFIG_TOML_FILE),
        r#"
model = "gpt-main"

[profiles.work]
model = "gpt-work"
"#,
    )
    .expect("write default user config");
    std::fs::write(&selected_config, r#"model = "gpt-work-v2""#)
        .expect("write selected user config");

    let mut overrides = LoaderOverrides::without_managed_config_for_tests();
    overrides.user_config_path = Some(AbsolutePathBuf::resolve_path_against_base(
        "work.config.toml",
        tmp.path(),
    ));
    overrides.user_config_profile = Some("work".parse().expect("profile-v2 name"));

    let err = load_config_layers_state(
        &TestFileSystem,
        tmp.path(),
        /*cwd*/ None,
        &[],
        overrides,
        CloudRequirementsLoader::default(),
        &crate::NoopThreadConfigLoader,
    )
    .await
    .expect_err("profile-v2 should reject a matching legacy profile in base user config");

    assert_eq!(
        err.kind(),
        io::ErrorKind::InvalidData,
        "a matching legacy profile should be a hard config error"
    );
    let message = err.to_string();
    assert!(
        message.contains("--profile `work` cannot be used"),
        "unexpected error message: {message}"
    );
    assert!(
        message.contains("config.toml"),
        "unexpected error message: {message}"
    );
    assert!(
        message.contains("[profiles.work]"),
        "unexpected error message: {message}"
    );
    assert!(
        message.contains("https://developers.openai.com/codex/config-advanced#profiles"),
        "unexpected error message: {message}"
    );
}

#[tokio::test]
async fn profile_v2_rejects_matching_legacy_profile_selector_in_base_user_config() {
    let tmp = tempdir().expect("tempdir");
    let selected_config = tmp.path().join("work.config.toml");

    std::fs::write(
        tmp.path().join(CONFIG_TOML_FILE),
        r#"
profile = "work"
model = "gpt-main"
"#,
    )
    .expect("write default user config");
    std::fs::write(&selected_config, r#"model = "gpt-work-v2""#)
        .expect("write selected user config");

    let mut overrides = LoaderOverrides::without_managed_config_for_tests();
    overrides.user_config_path = Some(AbsolutePathBuf::resolve_path_against_base(
        "work.config.toml",
        tmp.path(),
    ));
    overrides.user_config_profile = Some("work".parse().expect("profile-v2 name"));

    let err = load_config_layers_state(
        &TestFileSystem,
        tmp.path(),
        /*cwd*/ None,
        &[],
        overrides,
        CloudRequirementsLoader::default(),
        &crate::NoopThreadConfigLoader,
    )
    .await
    .expect_err("profile-v2 should reject a matching legacy profile selector");

    assert_eq!(
        err.kind(),
        io::ErrorKind::InvalidData,
        "a matching legacy profile selector should be a hard config error"
    );
    let message = err.to_string();
    assert!(
        message.contains("--profile `work` cannot be used"),
        "unexpected error message: {message}"
    );
    assert!(
        message.contains("profile = \"work\""),
        "unexpected error message: {message}"
    );
    assert!(
        message.contains("work.config.toml"),
        "unexpected error message: {message}"
    );
}

#[tokio::test]
async fn profile_v2_allows_unrelated_legacy_profiles_in_base_user_config() {
    let tmp = tempdir().expect("tempdir");
    let selected_config = tmp.path().join("work.config.toml");

    std::fs::write(
        tmp.path().join(CONFIG_TOML_FILE),
        r#"
model = "gpt-main"

[profiles.dev]
model = "gpt-dev"
"#,
    )
    .expect("write default user config");
    std::fs::write(&selected_config, r#"model = "gpt-work-v2""#)
        .expect("write selected user config");

    let mut overrides = LoaderOverrides::without_managed_config_for_tests();
    overrides.user_config_path = Some(AbsolutePathBuf::resolve_path_against_base(
        "work.config.toml",
        tmp.path(),
    ));
    overrides.user_config_profile = Some("work".parse().expect("profile-v2 name"));

    load_config_layers_state(
        &TestFileSystem,
        tmp.path(),
        /*cwd*/ None,
        &[],
        overrides,
        CloudRequirementsLoader::default(),
        &crate::NoopThreadConfigLoader,
    )
    .await
    .expect("profile-v2 should allow unrelated legacy profiles in base user config");
}
