//
//  FreeTDSWrapper.c
//  FreeTDSKit
//
//  Created by David Oliver on 12/27/24.
//

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sybdb.h>

#include "FreeTDSWrapper.h"

#define MAX_TDS_MESSAGES 8
#define TDS_MESSAGE_TEXT_LEN 512
#define TDS_MESSAGE_NAME_LEN 128

// Severity 11 and above is an actual error; below that the server is sending
// informational text (PRINT output, "changed database context", and friends).
#define TDS_MIN_ERROR_SEVERITY 11

typedef struct {
    long number;
    int severity;
    int state;
    int line;
    char text[TDS_MESSAGE_TEXT_LEN];
    char server[TDS_MESSAGE_NAME_LEN];
    char procedure[TDS_MESSAGE_NAME_LEN];
} TdsMessage;

// A single failure often produces several messages. SQL Server sends the
// specific cause first and a generic summary afterwards -- Azure answers a bad
// database name with "Cannot open database ... requested by the login" followed
// by "Login failed for user ...". Keeping only the newest message therefore
// throws away the only one that says what went wrong, so record them all in
// arrival order and report the whole set.
typedef struct {
    TdsMessage messages[MAX_TDS_MESSAGES];
    int count;   // messages retained (capped at MAX_TDS_MESSAGES)
    int seen;    // messages reported, including any dropped
    char lastError[1024];
    char combined[MAX_TDS_MESSAGES * (TDS_MESSAGE_TEXT_LEN + 128) + 64];
} TdsMessageLog;

// Each connection has its own log, hung off the DBPROCESS with dbsetuserdata,
// so one connection's errors can never be reported as -- or clobbered by --
// another's, and two connections failing at once never touch the same memory.
//
// A connection that is still logging in has no log of its own yet, so messages
// raised then go to the calling thread's log. dbopen runs on one thread from
// start to finish, which makes that thread the one to read them on.
static _Thread_local TdsMessageLog threadLog;

static TdsMessageLog* logFor(DBPROCESS *dbproc) {
    if (dbproc != NULL) {
        TdsMessageLog *log = (TdsMessageLog *)dbgetuserdata(dbproc);
        if (log != NULL) {
            return log;
        }
    }
    return &threadLog;
}

static void copyField(char *dest, size_t size, const char *src) {
    snprintf(dest, size, "%s", src ? src : "");
}

void tdsClearMessages(DBPROCESS *dbproc) {
    TdsMessageLog *log = logFor(dbproc);
    log->count = 0;
    log->seen = 0;
    log->lastError[0] = '\0';
    log->combined[0] = '\0';
}

// Message handler to capture detailed SQL Server error messages.
static int messageHandler(DBPROCESS *dbproc, DBINT msgno, int msgstate, int severity,
                          char *msgtext, char *srvname, char *procname, int line) {
    if (severity < TDS_MIN_ERROR_SEVERITY) {
        return 0;
    }
    TdsMessageLog *log = logFor(dbproc);
    log->seen++;
    // Once full, keep what we have: the earliest messages are the specific ones.
    if (log->count >= MAX_TDS_MESSAGES) {
        return 0;
    }
    TdsMessage *message = &log->messages[log->count++];
    message->number = (long)msgno;
    message->severity = severity;
    message->state = msgstate;
    message->line = line;
    copyField(message->text, sizeof(message->text), msgtext);
    copyField(message->server, sizeof(message->server), srvname);
    copyField(message->procedure, sizeof(message->procedure), procname);
    return 0;
}

static int errorHandler(DBPROCESS *dbproc, int severity, int dberr, int oserr, char *dberrstr, char *oserrstr) {
    TdsMessageLog *log = logFor(dbproc);
    snprintf(log->lastError, sizeof(log->lastError), "DB-Lib error %d (severity %d): %s [%s]",
             dberr, severity, dberrstr ? dberrstr : "", oserrstr ? oserrstr : "no os error");

    // A query that outran its timeout should cost the caller that query, not
    // the connection. INT_TIMEOUT has db-lib cancel the running command on the
    // server and return FAIL while leaving the DBPROCESS usable, where
    // INT_CANCEL returns FAIL and marks the connection dead -- every later
    // query on it then fails with "DBPROCESS is dead or not enabled".
    //
    // db-lib accepts INT_TIMEOUT for SYBETIME alone and treats it as INT_EXIT
    // for anything else, so this stays a special case for that one error.
    if (dberr == SYBETIME) {
        return INT_TIMEOUT;
    }
    return INT_CANCEL;
}

int tdsMessageCount(DBPROCESS *dbproc) { return logFor(dbproc)->count; }

static const TdsMessage* messageAt(DBPROCESS *dbproc, int index) {
    TdsMessageLog *log = logFor(dbproc);
    if (index < 0 || index >= log->count) { return NULL; }
    return &log->messages[index];
}

long tdsMessageNumber(DBPROCESS *dbproc, int index) {
    const TdsMessage *m = messageAt(dbproc, index);
    return m ? m->number : 0;
}

int tdsMessageSeverity(DBPROCESS *dbproc, int index) {
    const TdsMessage *m = messageAt(dbproc, index);
    return m ? m->severity : 0;
}

int tdsMessageState(DBPROCESS *dbproc, int index) {
    const TdsMessage *m = messageAt(dbproc, index);
    return m ? m->state : 0;
}

int tdsMessageLine(DBPROCESS *dbproc, int index) {
    const TdsMessage *m = messageAt(dbproc, index);
    return m ? m->line : 0;
}

const char* tdsMessageText(DBPROCESS *dbproc, int index) {
    const TdsMessage *m = messageAt(dbproc, index);
    return m ? m->text : "";
}

const char* tdsMessageServer(DBPROCESS *dbproc, int index) {
    const TdsMessage *m = messageAt(dbproc, index);
    return m ? m->server : "";
}

const char* tdsMessageProcedure(DBPROCESS *dbproc, int index) {
    const TdsMessage *m = messageAt(dbproc, index);
    return m ? m->procedure : "";
}

// Prefer the SQL Server messages (from messageHandler) when available, as they
// contain the actual error text (e.g. "Incorrect syntax near ','"). Every
// message is included, oldest first, because the first one is usually the cause
// and the later ones the consequence. Fall back to the DB-Lib wrapper message
// only when the server recorded nothing.
const char* tdsLastErrorMessage(DBPROCESS *dbproc) {
    TdsMessageLog *log = logFor(dbproc);
    if (log->count == 0) { return log->lastError; }

    size_t offset = 0;
    log->combined[0] = '\0';
    for (int i = 0; i < log->count; i++) {
        const TdsMessage *m = &log->messages[i];
        int written = snprintf(log->combined + offset, sizeof(log->combined) - offset,
                               "%sMsg %ld, Level %d, State %d, Line %d: %s",
                               i == 0 ? "" : " | ",
                               m->number, m->severity, m->state, m->line, m->text);
        if (written < 0 || (size_t)written >= sizeof(log->combined) - offset) {
            return log->combined;
        }
        offset += (size_t)written;
    }

    int dropped = log->seen - log->count;
    if (dropped > 0) {
        snprintf(log->combined + offset, sizeof(log->combined) - offset,
                 " | (%d further message%s suppressed)", dropped, dropped == 1 ? "" : "s");
    }
    return log->combined;
}

const char* getDBVersion(void) {
    return dbversion();
}

static pthread_once_t dbLibraryOnce = PTHREAD_ONCE_INIT;
static int dbLibraryStatus = -1;

static void installHandlers(void) {
    dberrhandle(errorHandler);
    dbmsghandle(messageHandler);
}

static void initializeDBLibraryOnce(void) {
    dbLibraryStatus = dbinit() == SUCCEED ? 0 : -1;
    // After dbinit, which resets the error handler to FreeTDS's default --
    // and that one calls exit() on a failed connection.
    installHandlers();
}

// DB-Library stays initialized for the life of the process. Pairing dbinit
// with dbexit per connection would be fragile: dbexit closes *every* open
// connection once its reference count reaches zero.
int initializeDBLibrary(void) {
    pthread_once(&dbLibraryOnce, initializeDBLibraryOnce);
    return dbLibraryStatus;
}

// Connect to the database
DBPROCESS* connectToDatabase(const char* server, const char* user, const char* password, const char* database,
                             const int timeout, const char* encryption, const char* caFile,
                             const char* certificateHostName) {
    LOGINREC *login;
    DBPROCESS *dbproc;

    tdsClearMessages(NULL);
    if (initializeDBLibrary() != 0) {
        snprintf(threadLog.lastError, sizeof(threadLog.lastError), "DB-Library initialization failed");
        return NULL;
    }
    login = dblogin();
    if (login == NULL) {
        return NULL;
    }
    dbsetlogintime(timeout);
    
    DBSETLUSER(login, user);
    DBSETLPWD(login, password);
    DBSETLAPP(login, "FreeTDSWrapper");
    // Select the target database via the login packet rather than a post-connect
    // `USE <database>` (dbuse). Azure SQL Database does not support the USE
    // statement, so the database must be specified at login time. This also
    // works for on-prem SQL Server.
    if (database != NULL && database[0] != '\0') {
        DBSETLDBNAME(login, database);
    }
    // FreeTDS only *requests* encryption by default: a server (or anyone in
    // between) that answers "not supported" gets the login in clear text, and
    // one that answers "off" gets every query and result in clear text. And it
    // checks the server certificate only when given a CA file. Set both
    // explicitly so neither depends on defaults or on a freetds.conf.
    if (encryption != NULL && encryption[0] != '\0' && DBSETLENCRYPTION(login, encryption) == FAIL) {
        snprintf(threadLog.lastError, sizeof(threadLog.lastError), "Invalid encryption setting \"%s\"", encryption);
        dbloginfree(login);
        return NULL;
    }
    if (dbsetltlsverify(login, caFile, certificateHostName) == FAIL) {
        snprintf(threadLog.lastError, sizeof(threadLog.lastError), "Could not set TLS certificate verification");
        dbloginfree(login);
        return NULL;
    }
    // Again here, in case anything else in the process has called dbinit since
    // (see initializeDBLibraryOnce). The handlers are process-wide and these
    // are the same values, so concurrent connects can't disagree.
    installHandlers();
    dbproc = dbopen(login, server);
    dbloginfree(login);
    if (dbproc == NULL) {
        return NULL;
    }
    // From here on the connection's messages are its own.
    TdsMessageLog *log = calloc(1, sizeof(TdsMessageLog));
    if (log == NULL) {
        dbclose(dbproc);
        snprintf(threadLog.lastError, sizeof(threadLog.lastError), "Out of memory");
        return NULL;
    }
    dbsetuserdata(dbproc, (BYTE *)log);
    return dbproc;
}

// Bound the time a query on this connection may run.
//
// dbsetopt(DBSETTIME) sets the timeout on this DBPROCESS alone. The obvious
// alternative, dbsettime(), writes a process-global value and pushes it onto
// every connection that has not set its own, so one caller's patience would
// become everybody's.
int setQueryTimeout(DBPROCESS* dbproc, int seconds) {
    if (dbproc == NULL) {
        return -1;
    }
    // DB-Library treats a non-positive timeout as "wait indefinitely", and
    // dbsetopt rejects it, so leave the default in place instead.
    if (seconds <= 0) {
        return 0;
    }
    char param[32];
    snprintf(param, sizeof(param), "%d", seconds);
    return dbsetopt(dbproc, DBSETTIME, param, -1) == SUCCEED ? 0 : -1;
}

// Execute a query
int executeQuery(DBPROCESS* dbproc, const char* query) {
    tdsClearMessages(dbproc);
    if (dbcmd(dbproc, query) == FAIL) {
        return -1;
    }
    if (dbsqlexec(dbproc) == FAIL) {
        return -1;
    }
    return 0;
}

// Fetch results
// Function to fetch results and return an array of RowData
// Format a fixed-width numeric column as text for the Swift side to parse.
// Reads the value at its real width (memcpy, since dbdata gives no alignment
// guarantee) and prints floats with enough digits to round-trip exactly.
// Returns 1 and sets *out (NULL if allocation failed) when colType is numeric.
static int formatNumber(int colType, const BYTE* data, int dataLength, char** out) {
    char buf[32];
    switch (colType) {
        case SYBINT1: {
            unsigned char v; if (dataLength != sizeof v) return 0;
            memcpy(&v, data, sizeof v); snprintf(buf, sizeof buf, "%u", v); break;
        }
        case SYBINT2: {
            short v; if (dataLength != sizeof v) return 0;
            memcpy(&v, data, sizeof v); snprintf(buf, sizeof buf, "%d", v); break;
        }
        case SYBINT4: {
            int v; if (dataLength != sizeof v) return 0;
            memcpy(&v, data, sizeof v); snprintf(buf, sizeof buf, "%d", v); break;
        }
        case SYBINT8: {
            long long v; if (dataLength != sizeof v) return 0;
            memcpy(&v, data, sizeof v); snprintf(buf, sizeof buf, "%lld", v); break;
        }
        case SYBFLT8: {
            double v; if (dataLength != sizeof v) return 0;
            memcpy(&v, data, sizeof v); snprintf(buf, sizeof buf, "%.17g", v); break;
        }
        case SYBREAL: {
            float v; if (dataLength != sizeof v) return 0;
            memcpy(&v, data, sizeof v); snprintf(buf, sizeof buf, "%.9g", (double)v); break;
        }
        default:
            return 0;
    }
    *out = strdup(buf);
    return 1;
}

RowData* fetchResultsWithType(DBPROCESS* dbproc, int* rowCount) {
    int result_code;
    int rows_allocated = 0;
    int current_row = 0;
    RowData* rows = NULL;

    while ((result_code = dbresults(dbproc)) != NO_MORE_RESULTS) {
        // Errors raised while producing a result set (a bad object name, a
        // failing statement later in a batch) arrive here rather than from
        // dbsqlexec. Returning NULL lets the caller report the server message.
        if (result_code == FAIL) {
            freeFetchedResults(rows, current_row);
            *rowCount = 0;
            return NULL;
        }
        if (result_code != SUCCEED) continue;
        int ncols = dbnumcols(dbproc);
        
        while (dbnextrow(dbproc) != NO_MORE_ROWS) {
            // Expand the rows array as needed
            if (current_row >= rows_allocated) {
                int new_alloc = rows_allocated == 0 ? 4 : rows_allocated * 2;
                RowData* temp = realloc(rows, new_alloc * sizeof(RowData));
                if (temp == NULL) {
                    freeFetchedResults(rows, current_row);
                    *rowCount = 0;
                    return NULL;
                }
                rows = temp;
                rows_allocated = new_alloc;
            }

            // Populate this row
            rows[current_row].columnCount = ncols;
            rows[current_row].columnNames = malloc(ncols * sizeof(char*));
            rows[current_row].columnValues = malloc(ncols * sizeof(char*));
            rows[current_row].columnTypes = malloc(ncols * sizeof(int));
            rows[current_row].columnLengths = malloc(ncols * sizeof(int));
            if (!rows[current_row].columnNames || !rows[current_row].columnValues || !rows[current_row].columnTypes
                || !rows[current_row].columnLengths) {
                freeFetchedResults(rows, current_row);
                *rowCount = 0;
                return NULL;
            }

            for (int i = 1; i <= ncols; i++) {
                const char* colName = dbcolname(dbproc, i);
                int colType = dbcoltype(dbproc, i);
                rows[current_row].columnNames[i - 1] = strdup(colName ? colName : "");
                rows[current_row].columnTypes[i - 1] = colType;

                BYTE* data = dbdata(dbproc, i);
                int dataLength = dbdatlen(dbproc, i);
                char* value;
                int valueLength = 0;
                if (data && colType == 36 && dataLength == 16) {
                    // uniqueidentifier arrives as 16 raw bytes; the Swift side
                    // parses text, so format it here. SQL Server stores the
                    // first three groups little-endian.
                    value = malloc(37);
                    if (value) {
                        snprintf(value, 37,
                                 "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                                 data[3], data[2], data[1], data[0],
                                 data[5], data[4],
                                 data[7], data[6],
                                 data[8], data[9],
                                 data[10], data[11], data[12], data[13], data[14], data[15]);
                        valueLength = 36;
                    }
                } else if (data && dataLength > 0 && formatNumber(colType, data, dataLength, &value)) {
                    if (value) {
                        valueLength = (int)strlen(value);
                    }
                } else if (data && dataLength > 0) {
                    value = malloc(dataLength + 1);
                    if (value) {
                        memcpy(value, data, dataLength);
                        value[dataLength] = '\0';
                        valueLength = dataLength;
                    }
                } else {
                    value = strdup("");
                }
                rows[current_row].columnValues[i - 1] = value;
                rows[current_row].columnLengths[i - 1] = value ? valueLength : 0;
            }
            current_row++;
        }
    }

    *rowCount = current_row;
    if (rows == NULL) {
        // DML (INSERT/UPDATE/DELETE) returns no rows — allocate a sentinel so
        // callers can distinguish success-with-no-rows from a real failure (NULL).
        rows = malloc(1);
    }
    return rows;
}


//Function to free the allocated memory for fetched results
void freeFetchedResults(RowData* rows, int rowCount) {
    for (int i = 0; i < rowCount; i++) {
        for (int j = 0; j < rows[i].columnCount; j++) {
            free(rows[i].columnNames[j]);
            free(rows[i].columnValues[j]);
        }
        free(rows[i].columnNames);
        free(rows[i].columnValues);
        free(rows[i].columnTypes);
        free(rows[i].columnLengths);
    }
    free(rows);
}

// Close the connection
void closeConnection(DBPROCESS* dbproc) {
    if (dbproc == NULL) {
        return;
    }
    TdsMessageLog *log = (TdsMessageLog *)dbgetuserdata(dbproc);
    dbclose(dbproc);
    free(log);
}
