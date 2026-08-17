/* lvz_ts_shim.c — see lvz_ts_shim.h. Pointer-based wrappers over the by-value
 * tree-sitter node API, so the Haskell FFI can drive the parser. */
#include "lvz_ts_shim.h"

#include <stdlib.h>

/* Each vendored grammar exports this symbol from its parser.c. */
extern const TSLanguage *tree_sitter_rust(void);
extern const TSLanguage *tree_sitter_python(void);
extern const TSLanguage *tree_sitter_javascript(void);
extern const TSLanguage *tree_sitter_typescript(void);

struct LvzNode {
  TSNode node;
};

const TSLanguage *lvz_ts_lang_rust(void) { return tree_sitter_rust(); }
const TSLanguage *lvz_ts_lang_python(void) { return tree_sitter_python(); }
const TSLanguage *lvz_ts_lang_javascript(void) { return tree_sitter_javascript(); }
const TSLanguage *lvz_ts_lang_typescript(void) { return tree_sitter_typescript(); }

TSTree *lvz_ts_parse(const TSLanguage *lang, const char *src, uint32_t len) {
  TSParser *parser = ts_parser_new();
  if (parser == NULL) {
    return NULL;
  }
  if (!ts_parser_set_language(parser, lang)) {
    ts_parser_delete(parser);
    return NULL;
  }
  TSTree *tree = ts_parser_parse_string(parser, NULL, src, len);
  ts_parser_delete(parser);
  return tree;
}

void lvz_tree_delete(TSTree *tree) {
  if (tree != NULL) {
    ts_tree_delete(tree);
  }
}

/* Wrap a by-value TSNode in a heap cell, unless it is the null node. */
static LvzNode *wrap(TSNode node) {
  if (ts_node_is_null(node)) {
    return NULL;
  }
  LvzNode *cell = (LvzNode *)malloc(sizeof(LvzNode));
  if (cell == NULL) {
    return NULL;
  }
  cell->node = node;
  return cell;
}

LvzNode *lvz_tree_root(TSTree *tree) { return wrap(ts_tree_root_node(tree)); }

const char *lvz_node_type(const LvzNode *node) { return ts_node_type(node->node); }
uint32_t lvz_node_start_byte(const LvzNode *node) { return ts_node_start_byte(node->node); }
uint32_t lvz_node_end_byte(const LvzNode *node) { return ts_node_end_byte(node->node); }
int lvz_node_is_named(const LvzNode *node) { return ts_node_is_named(node->node) ? 1 : 0; }
uint32_t lvz_node_child_count(const LvzNode *node) { return ts_node_child_count(node->node); }
uint32_t lvz_node_named_child_count(const LvzNode *node) {
  return ts_node_named_child_count(node->node);
}

LvzNode *lvz_node_child(const LvzNode *node, uint32_t i) {
  return wrap(ts_node_child(node->node, i));
}
LvzNode *lvz_node_named_child(const LvzNode *node, uint32_t i) {
  return wrap(ts_node_named_child(node->node, i));
}
LvzNode *lvz_node_child_by_field_name(const LvzNode *node, const char *name, uint32_t name_len) {
  return wrap(ts_node_child_by_field_name(node->node, name, name_len));
}

const char *lvz_node_field_name_for_child(const LvzNode *node, uint32_t i) {
  return ts_node_field_name_for_child(node->node, i);
}

void lvz_node_free(LvzNode *node) { free(node); }
