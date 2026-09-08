//
//  Header.h
//  FreeTDSKit
//
//  Created by David Oliver on 12/27/24.
//

#ifndef FreeTDSWrapper_h
#define FreeTDSWrapper_h

#include <sybdb.h>

// Retrieve the error text for the most recent operation. When the server
// reported messages, this is every one of them, oldest first, joined with " | ";
// otherwise it is the DB-Library error text.
const char* getLastTdsErrorMessage(void);

// Discard the messages recorded for the previous operation. Called at the start
// of connect/execute; also safe to call from client code.
void clearTdsMessages(void);

// Server messages recorded during the most recent operation, oldest first.
// SQL Server reports the specific cause first and a generic summary afterwards,
// so index 0 is normally the message that explains the failure.
int getTdsMessageCount(void);
long getTdsMessageNumber(int index);
int getTdsMessageSeverity(int index);
int getTdsMessageState(int index);
int getTdsMessageLine(int index);
const char* getTdsMessageText(int index);
const char* getTdsMessageServer(int index);
const char* getTdsMessageProcedure(int index);
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
