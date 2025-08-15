use std::{env, path::PathBuf};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());

    tonic_build::configure()
        .file_descriptor_set_path(out_dir.join("like_service_descriptor.bin"))
        .compile_protos(
            &[
                "src/proto/like.proto",
                "src/proto/user.proto",
                "src/proto/post.proto",
            ],
            &["src/proto"],
        )?;
    Ok(())
}
