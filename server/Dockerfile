# Build stage
FROM rust:1.93.0-alpine AS builder

# Install build dependencies
RUN apk add --no-cache musl-dev openssl-dev openssl-libs-static pkgconfig

WORKDIR /app

# Copy workspace files
COPY Cargo.toml ./
COPY engine ./engine
COPY server ./server

# Build the server
RUN cargo build --release --package carry-server

# Runtime stage
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache ca-certificates

WORKDIR /app

# Copy the binary from builder
COPY --from=builder /app/target/release/carry-server /app/carry-server

# Copy migrations
COPY --from=builder /app/server/migrations /app/migrations

EXPOSE 3000

CMD ["/app/carry-server"]
