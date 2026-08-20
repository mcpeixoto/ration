// Resolves sqlite3.h from the compiler's header search path rather than a fixed
// absolute path, so the module also builds against a SQLite installed outside
// /usr/include (e.g. a user-local prefix passed with -Xcc -I).
#include <sqlite3.h>
