//
//  Header.h
//  FreeTDSKit
//
//  Created by David Oliver on 12/27/24.
//


#ifndef FreeTDSWrapper_h
#define FreeTDSWrapper_h

#include "/opt/homebrew/include/sybdb.h"

// Structure to hold a single row's data
typedef struct {
    char **columnNames;
    char **columnValues;
    int columnCount;
} RowData;


const char* getDBVersion(void);
int initializeDBLibrary(void);
DBPROCESS* connectToDatabase(const char* server, const char* user, const char* password, const char* database);
int executeQuery(DBPROCESS* dbproc, const char* query);
RowData* fetchResults(DBPROCESS* dbproc, int* rowCount);
void freeFetchedResults(RowData* rows, int rowCount);
void closeConnection(DBPROCESS* dbproc);


#endif /* FreeTDSWrapper_h */
