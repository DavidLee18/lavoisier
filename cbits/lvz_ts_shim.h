/* lvz_ts_shim.h — a thin C shim over the tree-sitter runtime.
 *
 * tree-sitter's node API passes and returns `TSNode` (and `TSPoint`) *by value*.
 * The Haskell FFI cannot pass or return C structs by value, so every by-value
 * entry point is wrapped here as a pointer-based function: nodes are handed to
 * Haskell as an opaque, heap-allocated `LvzNode *` that Haskell frees explicitly.
 * This mirrors what the (archived) haskell-tree-sitter package did, and keeps the
 * Haskell side (`Lavoisier.Context.TreeSitter`) a set of plain pointer FFI imports.
 */
#ifndef LVZ_TS_SHIM_H
#define LVZ_TS_SHIM_H

#include <stdint.h>
#include <tree_sitter/api.h>

/* An opaque, heap-allocated copy of a TSNode (which is itself a small by-value
 * struct). Haskell holds a `Ptr LvzNode` and must `lvz_node_free` it. */
typedef struct LvzNode LvzNode;

/* Grammar entry points (each vendored grammar exports `tree_sitter_<lang>`). */
const TSLanguage *lvz_ts_lang_rust(void);
const TSLanguage *lvz_ts_lang_python(void);
const TSLanguage *lvz_ts_lang_javascript(void);
const TSLanguage *lvz_ts_lang_typescript(void);

/* Parse `src` (length `len` bytes) with `lang`; returns a tree to be freed with
 * lvz_tree_delete, or NULL on failure. Owns its own parser internally. */
TSTree *lvz_ts_parse(const TSLanguage *lang, const char *src, uint32_t len);
void lvz_tree_delete(TSTree *tree);

/* Root node of a tree, as a fresh LvzNode * (free with lvz_node_free). */
LvzNode *lvz_tree_root(TSTree *tree);

/* Node accessors. `lvz_node_type` returns a static string owned by the grammar
 * (do not free). Child accessors return a fresh LvzNode * (free it), or NULL if
 * the requested child does not exist / is null. */
const char *lvz_node_type(const LvzNode *node);
uint32_t lvz_node_start_byte(const LvzNode *node);
uint32_t lvz_node_end_byte(const LvzNode *node);
int lvz_node_is_named(const LvzNode *node);
uint32_t lvz_node_child_count(const LvzNode *node);
uint32_t lvz_node_named_child_count(const LvzNode *node);
LvzNode *lvz_node_child(const LvzNode *node, uint32_t i);
LvzNode *lvz_node_named_child(const LvzNode *node, uint32_t i);
LvzNode *lvz_node_child_by_field_name(const LvzNode *node, const char *name, uint32_t name_len);

/* Field name of the i-th child (NULL if that child has no field). Static string. */
const char *lvz_node_field_name_for_child(const LvzNode *node, uint32_t i);

void lvz_node_free(LvzNode *node);

#endif /* LVZ_TS_SHIM_H */
