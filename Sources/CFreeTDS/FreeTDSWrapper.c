//
//  FreeTDSWrapper.c
//  FreeTDSKit
//
//  Created by David Oliver on 12/27/24.
//
#include <stdlib.h>
#include <string.h>
#include "/opt/homebrew/include/sybdb.h"

#include "FreeTDSWrapper.h"

const char* getDBVersion(void) {
    return dbversion();
}

// Initialize DB-Library
int initializeDBLibrary(void) {
    return dbinit() == SUCCEED ? 0 : -1;
}

// Connect to the database
DBPROCESS* connectToDatabase(const char* server, const char* user, const char* password, const char* database) {
    LOGINREC *login;
    DBPROCESS *dbproc;

    dbinit();
    login = dblogin();
    if (login == NULL) {
        return NULL;
    }
    DBSETLUSER(login, user);
    DBSETLPWD(login, password);
    DBSETLAPP(login, "FreeTDSWrapper");
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
RowData* fetchResults(DBPROCESS* dbproc, int* rowCount) {
    int result_code;
    int rows_allocated = 10; // Initial allocation size
    int current_row = 0;
    RowData* rows = malloc(rows_allocated * sizeof(RowData));

    if (rows == NULL) {
        *rowCount = 0;
        return NULL;
    }

    while ((result_code = dbresults(dbproc)) != NO_MORE_RESULTS) {
        if (result_code == SUCCEED) {
            int ncols = dbnumcols(dbproc);

            while (dbnextrow(dbproc) != NO_MORE_ROWS) {
                if (current_row >= rows_allocated) {
                    // Reallocate more space if needed
                    rows_allocated *= 2;
                    RowData* temp = realloc(rows, rows_allocated * sizeof(RowData));
                    if (temp == NULL) {
                        // Handle memory allocation failure
                        for (int i = 0; i < current_row; i++) {
                            free(rows[i].columnNames);
                            free(rows[i].columnValues);
                        }
                        free(rows);
                        *rowCount = 0;
                        return NULL;
                    }
                    rows = temp;
                }

                rows[current_row].columnCount = ncols;
                rows[current_row].columnNames = malloc(ncols * sizeof(char*));
                rows[current_row].columnValues = malloc(ncols * sizeof(char*));

                if (rows[current_row].columnNames == NULL || rows[current_row].columnValues == NULL) {
                    // Handle memory allocation failure
                    for (int i = 0; i <= current_row; i++) {
                        free(rows[i].columnNames);
                        free(rows[i].columnValues);
                    }
                    free(rows);
                    *rowCount = 0;
                    return NULL;
                }

                for (int i = 1; i <= ncols; i++) {
                    const char* colName = dbcolname(dbproc, i);
                    int dataLength = dbdatlen(dbproc, i);
                    BYTE* data = dbdata(dbproc, i);

                    rows[current_row].columnNames[i - 1] = strdup(colName ? colName : "");
                    if (data && dataLength > 0) {
                        rows[current_row].columnValues[i - 1] = malloc(dataLength + 1);
                        if (rows[current_row].columnValues[i - 1] != NULL) {
                            memcpy(rows[current_row].columnValues[i - 1], data, dataLength);
                            rows[current_row].columnValues[i - 1][dataLength] = '\0'; // Null-terminate
                        }
                    } else {
                        rows[current_row].columnValues[i - 1] = strdup("");
                    }
                }
                current_row++;
            }
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
    }
    free(rows);
}

// Close the connection
void closeConnection(DBPROCESS* dbproc) {
    dbclose(dbproc);
    dbexit();
}
