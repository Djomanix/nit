/* This C header file is generated by NIT to compile modules and programs that requires symbol. */
#ifndef symbol_3_sep
#define symbol_3_sep
#include "hash._sep.h"
#include <nit_common.h>

extern const classtable_elt_t VFT_Symbol[];
#define LOCATE_symbol "symbol"
extern const int SFT_symbol[];
#define COLOR_symbol___String___to_symbol SFT_symbol[0]
#define ID_Symbol SFT_symbol[1]
#define COLOR_Symbol SFT_symbol[2]
#define COLOR_symbol___Symbol____string SFT_symbol[3]
#define INIT_TABLE_POS_Symbol SFT_symbol[4]
#define COLOR_symbol___Symbol___init SFT_symbol[5]
typedef val_t (* symbol___String___to_symbol_t)(val_t  self);
val_t symbol___String___to_symbol(val_t  self);
#define LOCATE_symbol___String___to_symbol "symbol::String::to_symbol"
#define ATTR_symbol___Symbol____string(recv) ATTR(recv, COLOR_symbol___Symbol____string)
typedef val_t (* symbol___Symbol___to_s_t)(val_t  self);
val_t symbol___Symbol___to_s(val_t  self);
#define LOCATE_symbol___Symbol___to_s "symbol::Symbol::(string::Object::to_s)"
typedef void (* symbol___Symbol___init_t)(val_t  self, val_t  param0, int* init_table);
void symbol___Symbol___init(val_t  self, val_t  param0, int* init_table);
val_t NEW_symbol___Symbol___init(val_t  param0);
#define LOCATE_symbol___Symbol___init "symbol::Symbol::init"
#endif