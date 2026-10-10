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
    // Byte length of each value, excluding the trailing NUL. Binary values can
    // contain zero bytes, so strlen() on columnValues would truncate them.
    int *columnLengths;
    int columnCount;
} RowData;


const char* getDBVersion(void);
int initializeDBLibrary(void);
// encryption: FreeTDS "encryption" value ("strict", "require" or "request").
// caFile: PEM file the server certificate must chain to; NULL or "" skips
//   verification (except with "strict", which always verifies).
// certificateHostName: name the certificate must match; NULL or "" means the
//   host in `server`.
DBPROCESS* connectToDatabase(const char* server, const char* user, const char* password, const char* database,
                             const int timeout, const char* encryption, const char* caFile,
                             const char* certificateHostName);
int executeQuery(DBPROCESS* dbproc, const char* query);

// Bound how long a query on this connection may run, in seconds. Applies to
// this DBPROCESS only, unlike dbsettime(), which is process-global. A value of
// 0 or less leaves DB-Library's default in place, which waits indefinitely.
// Returns 0 on success.
int setQueryTimeout(DBPROCESS* dbproc, int seconds);
RowData* fetchResultsWithType(DBPROCESS* dbproc, int* rowCount);
void freeFetchedResults(RowData* rows, int rowCount);
void closeConnection(DBPROCESS* dbproc);


#endif /* FreeTDSWrapper_h */
