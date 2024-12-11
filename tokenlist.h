#include "common.h"

TokenList* TokenList_new(size_t capacity);
void TokenList_append(TokenList*, Token*);
/// Expensive. Avoid.
void TokenList_prepend(TokenList*, Token*);