//! Error types for the Carry engine.

use crate::{CollectionName, RecordId, SchemaVersion, Version};
use thiserror::Error;

/// All possible errors from the Carry engine.
#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum Error {
    // Validation errors
    #[error("collection not found: {0}")]
    CollectionNotFound(CollectionName),

    #[error("record not found: {0}")]
    RecordNotFound(RecordId),

    #[error("invalid payload: {0}")]
    InvalidPayload(String),

    #[error("missing required field: {0}")]
    MissingRequiredField(String),

    #[error("type mismatch for field '{field}': expected {expected}, got {got}")]
    TypeMismatch {
        field: String,
        expected: String,
        got: String,
    },

    // Operation errors
    #[error("record already exists: {0}")]
    RecordAlreadyExists(RecordId),

    #[error("version mismatch: expected {expected}, got {actual}")]
    VersionMismatch { expected: Version, actual: Version },

    #[error("operation on deleted record: {0}")]
    OperationOnDeleted(RecordId),

    // State errors
    #[error("invalid snapshot: {0}")]
    InvalidSnapshot(String),

    #[error("schema version mismatch: expected {expected}, got {actual}")]
    SchemaVersionMismatch {
        expected: SchemaVersion,
        actual: SchemaVersion,
    },
}

/// Result type for engine operations.
pub type Result<T> = std::result::Result<T, Error>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_display() {
        let err = Error::CollectionNotFound("users".into());
        assert_eq!(err.to_string(), "collection not found: users");

        let err = Error::VersionMismatch {
            expected: 1,
            actual: 2,
        };
        assert_eq!(err.to_string(), "version mismatch: expected 1, got 2");

        let err = Error::TypeMismatch {
            field: "age".into(),
            expected: "Int".into(),
            got: "String".into(),
        };
        assert_eq!(
            err.to_string(),
            "type mismatch for field 'age': expected Int, got String"
        );
    }
}
