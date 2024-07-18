/*****************************************************************
                 ----------------------- 
                 tsqltools - SQLCOMPARE - Objects Compare
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
DECLARE @SourceDbName NVARCHAR(100);

-- Declare table variable to store source database names
DECLARE @SourceDatabases TABLE (DbName NVARCHAR(100));

-- Populate source database names
SET @SourceDbNameQuery = N'SELECT name FROM ' + @SourceDbServer + '.master.sys.databases WHERE database_id > 4';
INSERT INTO @SourceDatabases
EXEC sp_executesql @SourceDbNameQuery;

-- Temporary table to store object status
CREATE TABLE #ObjectStatus (
    DbName NVARCHAR(500),
    ObjectName NVARCHAR(500),
    ObjectType NVARCHAR(500),
    Status NVARCHAR(500)
);

-- Cursor to iterate through source databases
DECLARE dbCursor CURSOR FOR
SELECT DbName FROM @SourceDatabases;

OPEN dbCursor;

FETCH NEXT FROM dbCursor INTO @SourceDbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @SourceDbFullName NVARCHAR(500);
    DECLARE @DestinationDbFullName NVARCHAR(500);
    DECLARE @Sql NVARCHAR(MAX);

    -- Construct full database names
    SET @SourceDbFullName = @SourceDbServer + '.' + @SourceDbName;
    SET @DestinationDbFullName = @DestinationDbServer + '.' + @SourceDbName;

    -- Construct SQL query to compare objects between source and destination databases
    SET @Sql = N'
    SELECT ''' + @SourceDbName + ''' AS DbName,
           ISNULL(SoSource.name, SoDestination.name) AS ObjectName,
           COALESCE(SoSource.type_desc, SoDestination.type_desc) AS ObjectType,
           CASE
               WHEN SoSource.object_id IS NULL THEN ''Available on ' + @DestinationDbFullName + '''
               WHEN SoDestination.object_id IS NULL THEN ''Available on ' + @SourceDbFullName + '''
               ELSE ''Available on Both Servers''
           END AS Status
    FROM ' + @SourceDbFullName + '.sys.objects SoSource
    FULL OUTER JOIN ' + @DestinationDbFullName + '.sys.objects SoDestination
    ON SoSource.name = SoDestination.name COLLATE database_default
    AND SoSource.type = SoDestination.type COLLATE database_default
    WHERE COALESCE(SoSource.type_desc, SoDestination.type_desc) NOT IN (''INTERNAL_TABLE'', ''SYSTEM_TABLE'', ''SERVICE_QUEUE'')
    ORDER BY COALESCE(SoSource.type_desc, SoDestination.type_desc)';

    -- Execute SQL query and insert results into temporary table
    INSERT INTO #ObjectStatus
    EXEC sp_executesql @Sql;

    FETCH NEXT FROM dbCursor INTO @SourceDbName;
END;

CLOSE dbCursor;
DEALLOCATE dbCursor;

-- Query to select and order objects by type
SELECT * FROM #ObjectStatus WHERE ObjectType = 'USER_TABLE' ORDER BY DbName ASC;
SELECT * FROM #ObjectStatus WHERE ObjectType = 'CHECK_CONSTRAINT' ORDER BY DbName ASC;
SELECT * FROM #ObjectStatus WHERE ObjectType = 'DEFAULT_CONSTRAINT' ORDER BY DbName ASC;
SELECT * FROM #ObjectStatus WHERE ObjectType = 'FOREIGN_KEY_CONSTRAINT' ORDER BY DbName ASC;
SELECT * FROM #ObjectStatus WHERE ObjectType = 'PRIMARY_KEY_CONSTRAINT' ORDER BY DbName ASC;
SELECT * FROM #ObjectStatus WHERE ObjectType = 'UNIQUE_CONSTRAINT' ORDER BY DbName ASC;
SELECT * FROM #ObjectStatus WHERE ObjectType = 'SQL_TRIGGER' ORDER BY DbName ASC;
SELECT * FROM #ObjectStatus WHERE ObjectType = 'VIEW' ORDER BY DbName ASC;
SELECT * FROM #ObjectStatus WHERE ObjectType = 'SQL_STORED_PROCEDURE' ORDER BY DbName ASC;

-- Select remaining object types not listed above
SELECT * FROM #ObjectStatus
WHERE ObjectType NOT IN (
    'USER_TABLE',
    'CHECK_CONSTRAINT',
    'DEFAULT_CONSTRAINT',
    'FOREIGN_KEY_CONSTRAINT',
    'PRIMARY_KEY_CONSTRAINT',
    'UNIQUE_CONSTRAINT',
    'SQL_TRIGGER',
    'VIEW',
    'SQL_STORED_PROCEDURE'
)
ORDER BY DbName ASC;

-- Clean up temporary table
DROP TABLE #ObjectStatus;

 



 

  
