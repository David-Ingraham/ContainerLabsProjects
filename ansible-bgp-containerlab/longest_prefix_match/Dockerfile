FROM rust:alpine
WORKDIR /app
COPY src ./src
COPY Cargo.toml .
COPY Cargo.lock .
RUN cargo build --release
RUN chmod +x target/release/longest_prefix_match
CMD ["./target/release/longest_prefix_match"]