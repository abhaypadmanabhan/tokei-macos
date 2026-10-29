#include "AIUsageDashboardCore.h"
#include <stddef.h>

int TokeiSQLiteHardenConnection(sqlite3 *database) {
    int result = sqlite3_db_config(database, SQLITE_DBCONFIG_DEFENSIVE, 1, NULL);
    if (result != SQLITE_OK) return result;
    result = sqlite3_db_config(database, SQLITE_DBCONFIG_TRUSTED_SCHEMA, 0, NULL);
    if (result != SQLITE_OK) return result;
    // Snapshots copy raw pages; readers accept only ordinary tables.
    return sqlite3_drop_modules(database, NULL);
}
