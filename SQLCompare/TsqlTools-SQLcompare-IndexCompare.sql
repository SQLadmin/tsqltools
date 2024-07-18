/*****************************************************************
                 ----------------------- 
                 tsqltools - SQLCOMPARE - Index Compare
                 -----------------------
Version: v1.0 
Release Date: 2017-07-30
Author: Bhuvanesh(@SQLadmin)
Feedback: mailto:r.bhuvanesh@outlook.com
Updates: http://medium.com/sqladmin
Repo: https://github.com/SqlAdmin/tsqltools/
License: 
  tsqltools is free to download.It contains Tsql stored procedures 
  and scripts to help the DBAs and Developers to make their job easier
(C) 2017
 
 
======================================================================

What is TsqlTools-SQLcompare? 

TsqlTools-SQLcompare is a tsqlscript that will help to compare Databases, 
Tables, Objects, Indexices between two servers without any tools.

======================================================================
How to Start?

Use a centalized server  and create LinkedServers from the centralized server.
Or Create LinkedServer on SourceDB server then run this query on SourceDB server.

========================================================================*/
-- Declare necessary variables
DECLARE @SourceDbServer NVARCHAR(100) = '[db01]';  -- Replace with your source DB server name
DECLARE @DestinationDbServer NVARCHAR(100) = '[db02]';  -- Replace with your target DB server name
DECLARE @SourceDbNameQuery NVARCHAR(MAX);
DECLARE @DestinationDbNameQuery NVARCHAR(MAX);

-- Declare table variables to store database names
DECLARE @SourceDatabases TABLE (DbName NVARCHAR(100));
DECLARE @DestinationDatabases TABLE (DbName NVARCHAR(100));

-- Populate source database names
SET @SourceDbNameQuery = N'SELECT name FROM ' + @SourceDbServer + '.master.sys.databases WHERE database_id > 4';
INSERT INTO @SourceDatabases
EXEC sp_executesql @SourceDbNameQuery;

-- Populate destination database names
SET @DestinationDbNameQuery = N'SELECT name FROM ' + @DestinationDbServer + '.master.sys.databases WHERE database_id > 4';
INSERT INTO @DestinationDatabases
EXEC sp_executesql @DestinationDbNameQuery;

-- Temporary tables to store index information
CREATE TABLE #SourceDbIndexes (
    DbName NVARCHAR(100),
    TableName NVARCHAR(500),
    IndexName NVARCHAR(300),
    IndexType NVARCHAR(100)
);

CREATE TABLE #DestinationDbIndexes (
    DbName NVARCHAR(100),
    TableName NVARCHAR(500),
    IndexName NVARCHAR(300),
    IndexType NVARCHAR(100)
);

-- Cursor to iterate through source databases
DECLARE dbCursor CURSOR FOR
SELECT DbName FROM @SourceDatabases;

OPEN dbCursor;

DECLARE @SourceDbName NVARCHAR(100);
FETCH NEXT FROM dbCursor INTO @SourceDbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @SourceSql NVARCHAR(MAX) = '
    INSERT INTO #SourceDbIndexes
    SELECT ''' + @SourceDbName + ''', 
           so.name AS TableName, 
           si.name AS IndexName, 
           si.type_desc AS IndexType
    FROM ' + @SourceDbServer + '.' + @SourceDbName + '.sys.indexes si
    JOIN ' + @SourceDbServer + '.' + @SourceDbName + '.sys.objects so
    ON si.object_id = so.object_id
    WHERE so.type = ''U'' AND si.name IS NOT NULL
    ORDER BY so.name, si.type';

    EXEC sp_executesql @SourceSql;
    FETCH NEXT FROM dbCursor INTO @SourceDbName;
END;

CLOSE dbCursor;
DEALLOCATE dbCursor;

-- Cursor to iterate through destination databases
DECLARE dbCursor CURSOR FOR
SELECT DbName FROM @DestinationDatabases;

OPEN dbCursor;

DECLARE @DestinationDbName NVARCHAR(100);
FETCH NEXT FROM dbCursor INTO @DestinationDbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @DestinationSql NVARCHAR(MAX) = '
    INSERT INTO #DestinationDbIndexes
    SELECT ''' + @DestinationDbName + ''', 
           so.name AS TableName, 
           si.name AS IndexName, 
           si.type_desc AS IndexType
    FROM ' + @DestinationDbServer + '.' + @DestinationDbName + '.sys.indexes si
    JOIN ' + @DestinationDbServer + '.' + @DestinationDbName + '.sys.objects so
    ON si.object_id = so.object_id
    WHERE so.type = ''U'' AND si.name IS NOT NULL
    ORDER BY so.name, si.type';

    EXEC sp_executesql @DestinationSql;
    FETCH NEXT FROM dbCursor INTO @DestinationDbName;
END;

CLOSE dbCursor;
DEALLOCATE dbCursor;

-- Compare indexes and output status
WITH SourceIndexHash AS (
    SELECT DbName, TableName, IndexName, 
           HASHBYTES('SHA1', CONCAT(DbName, TableName, IndexName)) AS IndexHash
    FROM #SourceDbIndexes
),
DestinationIndexHash AS (
    SELECT DbName, TableName, IndexName, 
           HASHBYTES('SHA1', CONCAT(DbName, TableName, IndexName)) AS IndexHash
    FROM #DestinationDbIndexes
)
SELECT 
    COALESCE(s.DbName, d.DbName) AS DbName,
    COALESCE(s.TableName, d.TableName) AS TableName,
    COALESCE(s.IndexName, d.IndexName) AS IndexName,
    CASE
        WHEN s.IndexHash IS NULL THEN 'Available On ' + @DestinationDbServer + ' Only'
        WHEN d.IndexHash IS NULL THEN 'Available On ' + @SourceDbServer + ' Only'
        ELSE 'Available On Both Servers'
    END AS Status
FROM SourceIndexHash s
FULL JOIN DestinationIndexHash d
ON s.IndexHash = d.IndexHash
ORDER BY TableName;

-- Clean up temporary tables
DROP TABLE #SourceDbIndexes;
DROP TABLE #DestinationDbIndexes;
