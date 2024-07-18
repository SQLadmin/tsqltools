/*****************************************************************
                 ----------------------- 
                 tsqltools - SQLCOMPARE - Rows Compare
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

-- Create temporary tables to store table row counts
CREATE TABLE #SourceTbl (
    DbName NVARCHAR(200),
    TableName NVARCHAR(200),
    Rows BIGINT
);

CREATE TABLE #DestTbl (
    DbName NVARCHAR(200),
    TableName NVARCHAR(200),
    Rows BIGINT
);

-- Populate source database names
SET @SourceDbNameQuery = N'SELECT name FROM ' + @SourceDbServer + '.master.sys.databases WHERE database_id > 4';
INSERT INTO @SourceDatabases
EXEC sp_executesql @SourceDbNameQuery;

-- Populate destination database names
SET @DestinationDbNameQuery = N'SELECT name FROM ' + @DestinationDbServer + '.master.sys.databases WHERE database_id > 4';
INSERT INTO @DestinationDatabases
EXEC sp_executesql @DestinationDbNameQuery;

-- Cursor to iterate through source databases
DECLARE dbCursor CURSOR FOR
SELECT DbName FROM @SourceDatabases;

OPEN dbCursor;

DECLARE @SourceDbName NVARCHAR(100);

FETCH NEXT FROM dbCursor INTO @SourceDbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @SourceSql NVARCHAR(MAX);

    -- Construct SQL query to get table row counts from source database
    SET @SourceSql = N'
    SELECT ''' + @SourceDbName + ''' AS DbName, 
           sc.name + ''.'' + ta.name AS TableName, 
           SUM(pa.rows) AS Rows
    FROM ' + @SourceDbServer + '.' + @SourceDbName + '.sys.tables ta
    INNER JOIN ' + @SourceDbServer + '.' + @SourceDbName + '.sys.partitions pa
    ON pa.OBJECT_ID = ta.OBJECT_ID
    INNER JOIN ' + @SourceDbServer + '.' + @SourceDbName + '.sys.schemas sc
    ON ta.schema_id = sc.schema_id
    WHERE ta.is_ms_shipped = 0 AND pa.index_id IN (1, 0)
    GROUP BY sc.name, ta.name
    ORDER BY SUM(pa.rows) DESC';

    -- Execute SQL query and insert results into temporary table
    INSERT INTO #SourceTbl
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
    DECLARE @DestinationSql NVARCHAR(MAX);

    -- Construct SQL query to get table row counts from destination database
    SET @DestinationSql = N'
    SELECT ''' + @DestinationDbName + ''' AS DbName, 
           sc.name + ''.'' + ta.name AS TableName, 
           SUM(pa.rows) AS Rows
    FROM ' + @DestinationDbServer + '.' + @DestinationDbName + '.sys.tables ta
    INNER JOIN ' + @DestinationDbServer + '.' + @DestinationDbName + '.sys.partitions pa
    ON pa.OBJECT_ID = ta.OBJECT_ID
    INNER JOIN ' + @DestinationDbServer + '.' + @DestinationDbName + '.sys.schemas sc
    ON ta.schema_id = sc.schema_id
    WHERE ta.is_ms_shipped = 0 AND pa.index_id IN (1, 0)
    GROUP BY sc.name, ta.name
    ORDER BY SUM(pa.rows) DESC';

    -- Execute SQL query and insert results into temporary table
    INSERT INTO #DestTbl
    EXEC sp_executesql @DestinationSql;

    FETCH NEXT FROM dbCursor INTO @DestinationDbName;
END;

CLOSE dbCursor;
DEALLOCATE dbCursor;

-- Compare table row counts and output status
SELECT a.DbName,
       a.TableName,
       (b.Rows - a.Rows) AS RowsDifference,
       CASE 
           WHEN (b.Rows - a.Rows) >= 100 THEN 'Alert'
           ELSE 'OK'
       END AS Status
FROM #SourceTbl a
JOIN #DestTbl b ON a.DbName = b.DbName AND a.TableName = b.TableName;

-- Clean up temporary tables
DROP TABLE #SourceTbl;
DROP TABLE #DestTbl;

