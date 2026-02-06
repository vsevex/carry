//! Schema definition and validation.
//!
//! Schemas define the structure of collections and enable validation
//! of operations before they are applied.

use crate::{error::Result, CollectionName, Error, Operation, SchemaVersion};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Field types supported in schemas.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FieldType {
    String,
    Int,
    Float,
    Bool,
    Timestamp,
    /// Arbitrary nested JSON
    Json,
}

impl std::fmt::Display for FieldType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FieldType::String => write!(f, "String"),
            FieldType::Int => write!(f, "Int"),
            FieldType::Float => write!(f, "Float"),
            FieldType::Bool => write!(f, "Bool"),
            FieldType::Timestamp => write!(f, "Timestamp"),
            FieldType::Json => write!(f, "Json"),
        }
    }
}

/// Definition of a field in a collection.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FieldDef {
    /// Field name
    pub name: String,
    /// Field type
    pub field_type: FieldType,
    /// Whether this field is required
    pub required: bool,
}

impl FieldDef {
    /// Create a new required field definition.
    pub fn required(name: impl Into<String>, field_type: FieldType) -> Self {
        Self {
            name: name.into(),
            field_type,
            required: true,
        }
    }

    /// Create a new optional field definition.
    pub fn optional(name: impl Into<String>, field_type: FieldType) -> Self {
        Self {
            name: name.into(),
            field_type,
            required: false,
        }
    }

    /// Validate a JSON value against this field definition.
    pub fn validate(&self, value: Option<&serde_json::Value>) -> Result<()> {
        match value {
            None if self.required => Err(Error::MissingRequiredField(self.name.clone())),
            None => Ok(()),
            Some(serde_json::Value::Null) if self.required => {
                Err(Error::MissingRequiredField(self.name.clone()))
            }
            Some(serde_json::Value::Null) => Ok(()),
            Some(v) => self.validate_type(v),
        }
    }

    fn validate_type(&self, value: &serde_json::Value) -> Result<()> {
        let valid = match self.field_type {
            FieldType::String => value.is_string(),
            FieldType::Int => value.is_i64() || value.is_u64(),
            FieldType::Float => value.is_f64() || value.is_i64() || value.is_u64(),
            FieldType::Bool => value.is_boolean(),
            FieldType::Timestamp => value.is_u64() || value.is_i64(),
            FieldType::Json => true, // Any JSON is valid
        };

        if valid {
            Ok(())
        } else {
            Err(Error::TypeMismatch {
                field: self.name.clone(),
                expected: self.field_type.to_string(),
                got: json_type_name(value).to_string(),
            })
        }
    }
}

fn json_type_name(value: &serde_json::Value) -> &'static str {
    match value {
        serde_json::Value::Null => "Null",
        serde_json::Value::Bool(_) => "Bool",
        serde_json::Value::Number(n) if n.is_i64() || n.is_u64() => "Int",
        serde_json::Value::Number(_) => "Float",
        serde_json::Value::String(_) => "String",
        serde_json::Value::Array(_) => "Array",
        serde_json::Value::Object(_) => "Object",
    }
}

/// Schema for a collection.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CollectionSchema {
    /// Collection name
    pub name: CollectionName,
    /// Field definitions
    pub fields: Vec<FieldDef>,
}

impl CollectionSchema {
    /// Create a new collection schema.
    pub fn new(name: impl Into<CollectionName>, fields: Vec<FieldDef>) -> Self {
        Self {
            name: name.into(),
            fields,
        }
    }

    /// Validate a payload against this schema.
    pub fn validate_payload(&self, payload: &serde_json::Value) -> Result<()> {
        let obj = payload
            .as_object()
            .ok_or_else(|| Error::InvalidPayload("payload must be an object".into()))?;

        for field in &self.fields {
            field.validate(obj.get(&field.name))?;
        }

        Ok(())
    }
}

/// Schema for the entire store.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Schema {
    /// Schema version for migrations
    pub version: SchemaVersion,
    /// Collection schemas by name
    pub collections: HashMap<CollectionName, CollectionSchema>,
}

impl Schema {
    /// Create a new schema.
    pub fn new(version: SchemaVersion) -> Self {
        Self {
            version,
            collections: HashMap::new(),
        }
    }

    /// Add a collection to the schema.
    pub fn add_collection(&mut self, collection: CollectionSchema) -> &mut Self {
        self.collections.insert(collection.name.clone(), collection);
        self
    }

    /// Builder-style method to add a collection.
    pub fn with_collection(mut self, collection: CollectionSchema) -> Self {
        self.add_collection(collection);
        self
    }

    /// Get a collection schema by name.
    pub fn get_collection(&self, name: &str) -> Option<&CollectionSchema> {
        self.collections.get(name)
    }

    /// Validate an operation against the schema.
    pub fn validate_operation(&self, op: &Operation) -> Result<()> {
        let collection_name = op.collection();

        let collection_schema = self
            .collections
            .get(collection_name)
            .ok_or_else(|| Error::CollectionNotFound(collection_name.clone()))?;

        // Validate payload for create and update operations
        match op {
            Operation::Create(create_op) => {
                collection_schema.validate_payload(&create_op.payload)?;
            }
            Operation::Update(update_op) => {
                collection_schema.validate_payload(&update_op.payload)?;
            }
            Operation::Delete(_) => {
                // Delete operations don't need payload validation
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::operation::CreateOp;
    use crate::LogicalClock;
    use serde_json::json;

    fn test_schema() -> Schema {
        Schema::new(1).with_collection(CollectionSchema::new(
            "users",
            vec![
                FieldDef::required("name", FieldType::String),
                FieldDef::required("age", FieldType::Int),
                FieldDef::optional("email", FieldType::String),
            ],
        ))
    }

    #[test]
    fn validate_valid_payload() {
        let schema = test_schema();
        let collection = schema.get_collection("users").unwrap();

        let payload = json!({"name": "Alice", "age": 30});
        assert!(collection.validate_payload(&payload).is_ok());

        let payload_with_optional = json!({"name": "Bob", "age": 25, "email": "bob@example.com"});
        assert!(collection.validate_payload(&payload_with_optional).is_ok());
    }

    #[test]
    fn validate_missing_required_field() {
        let schema = test_schema();
        let collection = schema.get_collection("users").unwrap();

        let payload = json!({"name": "Alice"}); // missing age
        let result = collection.validate_payload(&payload);

        assert!(matches!(result, Err(Error::MissingRequiredField(f)) if f == "age"));
    }

    #[test]
    fn validate_wrong_type() {
        let schema = test_schema();
        let collection = schema.get_collection("users").unwrap();

        let payload = json!({"name": "Alice", "age": "thirty"}); // age should be int
        let result = collection.validate_payload(&payload);

        assert!(matches!(result, Err(Error::TypeMismatch { field, .. }) if field == "age"));
    }

    #[test]
    fn validate_null_required_field() {
        let schema = test_schema();
        let collection = schema.get_collection("users").unwrap();

        let payload = json!({"name": null, "age": 30});
        let result = collection.validate_payload(&payload);

        assert!(matches!(result, Err(Error::MissingRequiredField(f)) if f == "name"));
    }

    #[test]
    fn validate_collection_not_found() {
        let schema = test_schema();
        let clock = LogicalClock::with_counter("node-1", 1);
        let op = Operation::Create(CreateOp::new(
            "op-1",
            "post-1",
            "posts", // doesn't exist
            json!({"title": "Hello"}),
            1000,
            clock,
        ));

        let result = schema.validate_operation(&op);
        assert!(matches!(result, Err(Error::CollectionNotFound(c)) if c == "posts"));
    }

    #[test]
    fn validate_create_operation() {
        let schema = test_schema();
        let clock = LogicalClock::with_counter("node-1", 1);

        let valid_op = Operation::Create(CreateOp::new(
            "op-1",
            "user-1",
            "users",
            json!({"name": "Alice", "age": 30}),
            1000,
            clock.clone(),
        ));
        assert!(schema.validate_operation(&valid_op).is_ok());

        let invalid_op = Operation::Create(CreateOp::new(
            "op-2",
            "user-2",
            "users",
            json!({"name": "Bob"}), // missing age
            1000,
            clock,
        ));
        assert!(schema.validate_operation(&invalid_op).is_err());
    }

    #[test]
    fn field_type_display() {
        assert_eq!(FieldType::String.to_string(), "String");
        assert_eq!(FieldType::Int.to_string(), "Int");
        assert_eq!(FieldType::Json.to_string(), "Json");
    }

    #[test]
    fn schema_serialization() {
        let schema = test_schema();
        let json = serde_json::to_string(&schema).unwrap();
        let parsed: Schema = serde_json::from_str(&json).unwrap();
        assert_eq!(schema, parsed);
    }

    #[test]
    fn json_field_accepts_any() {
        let collection =
            CollectionSchema::new("events", vec![FieldDef::required("data", FieldType::Json)]);

        // All these should be valid for Json type
        assert!(collection
            .validate_payload(&json!({"data": "string"}))
            .is_ok());
        assert!(collection.validate_payload(&json!({"data": 123})).is_ok());
        assert!(collection.validate_payload(&json!({"data": true})).is_ok());
        assert!(collection
            .validate_payload(&json!({"data": [1, 2, 3]}))
            .is_ok());
        assert!(collection
            .validate_payload(&json!({"data": {"nested": "object"}}))
            .is_ok());
    }
}
