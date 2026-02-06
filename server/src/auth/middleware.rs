//! Authentication middleware.
//!
//! This provides a simple Bearer token extraction mechanism.
//! In production, you would validate the token against a database or JWT.

use axum::{
    extract::FromRequestParts,
    http::{header::AUTHORIZATION, request::Parts, StatusCode},
};

use crate::AppState;

/// Authenticated user extracted from request.
#[derive(Debug, Clone)]
pub struct AuthUser {
    /// The bearer token (or node ID in development mode)
    #[allow(dead_code)]
    pub token: String,
}

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = (StatusCode, &'static str);

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        // Try to get Authorization header
        let auth_header = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|value| value.to_str().ok());

        match auth_header {
            Some(header) if header.starts_with("Bearer ") => {
                let token = header.trim_start_matches("Bearer ").to_string();

                // In production, validate the token here
                // For now, we just accept any token
                if token.is_empty() {
                    return Err((StatusCode::UNAUTHORIZED, "Empty bearer token"));
                }

                // If auth_secret is configured, we could validate against it
                // This is a placeholder for more sophisticated auth
                if let Some(ref _secret) = state.config.auth_secret {
                    // TODO: Implement proper token validation (JWT, etc.)
                    // For now, accept any non-empty token
                }

                Ok(AuthUser { token })
            }
            Some(_) => Err((
                StatusCode::UNAUTHORIZED,
                "Invalid authorization header format",
            )),
            None => {
                // In development mode, allow requests without auth
                // In production, you'd return an error here
                if state.config.auth_secret.is_none() {
                    // No auth configured, allow anonymous access
                    Ok(AuthUser {
                        token: "anonymous".to_string(),
                    })
                } else {
                    Err((StatusCode::UNAUTHORIZED, "Missing authorization header"))
                }
            }
        }
    }
}

/// Optional authenticated user - doesn't reject if missing.
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct OptionalAuthUser(pub Option<AuthUser>);

impl FromRequestParts<AppState> for OptionalAuthUser {
    type Rejection = (StatusCode, &'static str);

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        match AuthUser::from_request_parts(parts, state).await {
            Ok(user) => Ok(OptionalAuthUser(Some(user))),
            Err(_) => Ok(OptionalAuthUser(None)),
        }
    }
}
