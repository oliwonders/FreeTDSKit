//
//  Header.h
//  FreeTDSKit
//
//  Created by David Oliver on 12/27/24.
//

#ifndef FreeTDSWrapper_h
#define FreeTDSWrapper_h

#include <sybdb.h>
//#include "/opt/homebrew/include/sybdb.h"

// Structure to hold a single row's data
typedef struct {
    char **columnNames;
    char **columnValues;
    int *columnTypes; // Array to hold column data types (e.g., integers representing SYBINT, SYBREAL, etc.)
    int columnCount;
} RowData;


const char* getDBVersion(void);
int initializeDBLibrary(void);
DBPROCESS* connectToDatabase(const char* server, const char* user, const char* password, const char* database, const int timeout);
int executeQuery(DBPROCESS* dbproc, const char* query);
RowData* fetchResultsWithType(DBPROCESS* dbproc, int* rowCount);
void freeFetchedResults(RowData* rows, int rowCount);
void closeConnection(DBPROCESS* dbproc);


#endif /* FreeTDSWrapper_h */
