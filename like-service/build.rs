fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::configure().compile_protos(
        &[
            "src/proto/like.proto",
            "src/proto/user.proto",
            "src/proto/post.proto",
        ],
        &["src/proto"],
    )?;
    Ok(())
}
