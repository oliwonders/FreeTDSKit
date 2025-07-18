//
//  FreeTDSWrapper.c
//  FreeTDSKit
//
//  Created by David Oliver on 12/27/24.
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sybdb.h>

#include "FreeTDSWrapper.h"

static char lastErrorMessage[1024] = "";

// Message handler to capture detailed SQL Server error messages.
static int messageHandler(DBPROCESS *dbproc, DBINT msgno, int msgstate, int severity,
                          char *msgtext, char *srvname, char *procname, int line) {
    // Format similar to SQL Server clients: Msg <msgno>, Level <severity>, State <msgstate>, Line <line>: <msgtext>
    snprintf(lastErrorMessage, sizeof(lastErrorMessage),
             "Msg %ld, Level %d, State %d, Line %d: %s",
             (long)msgno, severity, msgstate, line, msgtext);
    return 0;
}
static int errorHandler(DBPROCESS *dbproc, int severity, int dberr, int oserr, char *dberrstr, char *oserrstr) {
    snprintf(lastErrorMessage, sizeof(lastErrorMessage), "DB-Lib error %d (severity %d): %s [%s]", dberr, severity, dberrstr, oserrstr ? oserrstr : "no os error");
    return INT_CANCEL;
}

const char* getLastTdsErrorMessage(void) {
    return lastErrorMessage;
}

const char* getDBVersion(void) {
    return dbversion();
}

// Initialize DB-Library
int initializeDBLibrary(void) {
    return dbinit() == SUCCEED ? 0 : -1;
}

// Connect to the database
DBPROCESS* connectToDatabase(const char* server, const char* user, const char* password, const char* database, const int timeout) {
    LOGINREC *login;
    DBPROCESS *dbproc;

    dbinit();
    login = dblogin();
    if (login == NULL) {
        return NULL;
    }
    dbsetlogintime(timeout);
    
    DBSETLUSER(login, user);
    DBSETLPWD(login, password);
    DBSETLAPP(login, "FreeTDSWrapper");
    dberrhandle(errorHandler);
    dbmsghandle(messageHandler);
    dbproc = dbopen(login, server);
    dbloginfree(login);
    if (dbproc == NULL) {
        return NULL;
    }
    if (dbuse(dbproc, database) == FAIL) {
        dbclose(dbproc);
        return NULL;
    }
    return dbproc;
}

// Execute a query
int executeQuery(DBPROCESS* dbproc, const char* query) {
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
RowData* fetchResultsWithType(DBPROCESS* dbproc, int* rowCount) {
    int result_code;
    int rows_allocated = 0;
    int current_row = 0;
    RowData* rows = NULL;

    while ((result_code = dbresults(dbproc)) != NO_MORE_RESULTS) {
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
            if (!rows[current_row].columnNames || !rows[current_row].columnValues || !rows[current_row].columnTypes) {
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
                if (data && dataLength > 0) {
                    value = malloc(dataLength + 1);
                    if (value) {
                        memcpy(value, data, dataLength);
                        value[dataLength] = '\0';
                        switch (colType) {
                            case SYBINT1:
                            case SYBINT2:
                            case SYBINT4:
                                snprintf(value, dataLength + 1, "%d", *(int*)data);
                                break;
                            case SYBFLT8:
                            case SYBREAL:
                                snprintf(value, dataLength + 1, "%f", *(double*)data);
                                break;
                            default:
                                break;
                        }
                    }
                } else {
                    value = strdup("");
                }
                rows[current_row].columnValues[i - 1] = value;
            }
            current_row++;
        }
    }

    *rowCount = current_row;
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
    }
    free(rows);
}

// Close the connection
void closeConnection(DBPROCESS* dbproc) {
    dbclose(dbproc);
    dbexit();
}
