//
//  FreeTDSWrapper.h
//  FreeTDSKit
//
//  Created by David Oliver on 12/27/24.
//

#ifndef FreeTDSWrapper_h
#define FreeTDSWrapper_h

#include <sybdb.h>

// Messages are kept per connection. Every function below that takes a
// DBPROCESS reads that connection's messages; pass NULL for messages raised
// before a connection existed -- a failed connectToDatabase -- which are kept
// per thread, so read them on the thread that tried to connect.
//
// DB-Library allows one thread at a time per DBPROCESS; the caller serializes.

// The error text for the most recent operation. When the server reported
// messages, this is every one of them, oldest first, joined with " | ";
// otherwise it is the DB-Library error text. Valid until the next operation on
// the same connection.
const char* tdsLastErrorMessage(DBPROCESS* dbproc);

// Discard the messages recorded for the previous operation. Called at the start
// of connect/execute.
void tdsClearMessages(DBPROCESS* dbproc);

// Server messages recorded during the most recent operation, oldest first.
// SQL Server reports the specific cause first and a generic summary afterwards,
// so index 0 is normally the message that explains the failure.
int tdsMessageCount(DBPROCESS* dbproc);
long tdsMessageNumber(DBPROCESS* dbproc, int index);
int tdsMessageSeverity(DBPROCESS* dbproc, int index);
int tdsMessageState(DBPROCESS* dbproc, int index);
int tdsMessageLine(DBPROCESS* dbproc, int index);
const char* tdsMessageText(DBPROCESS* dbproc, int index);
const char* tdsMessageServer(DBPROCESS* dbproc, int index);
const char* tdsMessageProcedure(DBPROCESS* dbproc, int index);

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
// Initialize DB-Library and install the message handlers. Safe to call any
// number of times from any thread; only the first call does anything.
int initializeDBLibrary(void);
// encryption: FreeTDS "encryption" value ("strict", "require" or "request").
// caFile: PEM file the server certificate must chain to; NULL or "" skips
//   verification (except with "strict", which always verifies).
// certificateHostName: name the certificate must match; NULL or "" means the
//   host in `server`.
// On failure returns NULL; read the reason with a NULL dbproc on this thread.
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
// Close the connection and free its messages. The DBPROCESS must not be used
// again, by this thread or any other.
void closeConnection(DBPROCESS* dbproc);


#endif /* FreeTDSWrapper_h */
