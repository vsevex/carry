/**
 * Carry Engine FFI Header
 *
 * C-compatible interface for the Carry sync engine.
 */

#ifndef CARRY_ENGINE_H
#define CARRY_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /**
     * Opaque pointer to a Store instance.
     */
    typedef void *CarryStore;

    // ============================================================================
    // Store Lifecycle
    // ============================================================================

    /**
     * Create a new store.
     *
     * @param schema_json JSON string of Schema
     * @param node_id Node identifier string
     * @return Pointer to Store, or NULL on failure
     */
    CarryStore carry_store_new(const char *schema_json, const char *node_id);

    /**
     * Free a store instance.
     *
     * @param store Pointer to store (may be NULL)
     */
    void carry_store_free(CarryStore store);

    /**
     * Free a string allocated by the engine.
     *
     * @param s Pointer to string (may be NULL)
     */
    void carry_string_free(char *s);

    // ============================================================================
    // Store Operations
    // ============================================================================

    /**
     * Apply an operation to the store.
     *
     * @param store Pointer to store
     * @param op_json JSON string of Operation
     * @param timestamp Current timestamp in milliseconds
     * @return JSON result string (caller must free with carry_string_free)
     */
    char *carry_store_apply(CarryStore store, const char *op_json, int64_t timestamp);

    /**
     * Get a record by collection and ID.
     *
     * @param store Pointer to store
     * @param collection Collection name
     * @param id Record ID
     * @return JSON result string (caller must free with carry_string_free)
     */
    char *carry_store_get(CarryStore store, const char *collection, const char *id);

    /**
     * Query records in a collection.
     *
     * @param store Pointer to store
     * @param collection Collection name
     * @param include_deleted Whether to include deleted records (0 or 1)
     * @return JSON result string (caller must free with carry_string_free)
     */
    char *carry_store_query(CarryStore store, const char *collection, int32_t include_deleted);

    /**
     * Get count of pending operations.
     *
     * @param store Pointer to store
     * @return Number of pending operations
     */
    int64_t carry_store_pending_count(CarryStore store);

    /**
     * Get all pending operations.
     *
     * @param store Pointer to store
     * @return JSON result string (caller must free with carry_string_free)
     */
    char *carry_store_pending_ops(CarryStore store);

    /**
     * Acknowledge operations as synced.
     *
     * @param store Pointer to store
     * @param op_ids_json JSON array of operation IDs
     * @return JSON result string (caller must free with carry_string_free)
     */
    char *carry_store_acknowledge(CarryStore store, const char *op_ids_json);

    /**
     * Increment and return the logical clock.
     *
     * @param store Pointer to store
     * @return JSON result string (caller must free with carry_string_free)
     */
    char *carry_store_tick(CarryStore store);

    // ============================================================================
    // Reconciliation
    // ============================================================================

    /**
     * Reconcile with remote operations.
     *
     * @param store Pointer to store
     * @param remote_ops_json JSON array of remote operations
     * @param strategy Merge strategy (0 = ClockWins, 1 = TimestampWins)
     * @return JSON result string (caller must free with carry_string_free)
     */
    char *carry_store_reconcile(CarryStore store, const char *remote_ops_json, int32_t strategy);

    // ============================================================================
    // Snapshots
    // ============================================================================

    /**
     * Export store state as snapshot.
     *
     * @param store Pointer to store
     * @return JSON result string (caller must free with carry_string_free)
     */
    char *carry_store_export(CarryStore store);

    /**
     * Import store state from snapshot.
     *
     * @param store Pointer to store
     * @param snapshot_json JSON snapshot string
     * @return JSON result string (caller must free with carry_string_free)
     */
    char *carry_store_import(CarryStore store, const char *snapshot_json);

    /**
     * Get snapshot metadata.
     *
     * @param store Pointer to store
     * @return JSON result string (caller must free with carry_string_free)
     */
    char *carry_store_metadata(CarryStore store);

    // ============================================================================
    // Utilities
    // ============================================================================

    /**
     * Get engine version string.
     *
     * @return JSON result string (caller must free with carry_string_free)
     */
    char *carry_version(void);

    /**
     * Get snapshot format version.
     *
     * @return Format version number
     */
    int32_t carry_snapshot_format_version(void);

#ifdef __cplusplus
}
#endif

#endif /* CARRY_ENGINE_H */
