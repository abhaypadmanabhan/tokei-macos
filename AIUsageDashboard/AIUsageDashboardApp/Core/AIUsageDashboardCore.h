#ifndef AIUsageDashboardCore_h
#define AIUsageDashboardCore_h

#include <sqlite3.h>

// Swift cannot call sqlite3_db_config's variadic C interface directly.
int TokeiSQLiteHardenConnection(sqlite3 *database);

#endif
