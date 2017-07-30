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
 
 
/*======================================================================

What is TsqlTools-SQLcompare? 

TsqlTools-SQLcompare is a tsqlscript that will help to compare Databases, 
Tables, Objects, Indexices between two servers without any tools.

========================================================================*/
DECLARE @SOURCEDBSERVER varchar(100)
DECLARE @DESTINATIONDBSERVER varchar(100)
DECLARE @SOURCE_SQL_DBNAME nvarchar(300)
DECLARE @SOURCE_DATABASENAME TABLE (  dbname varchar(100))
DECLARE @DESTINATION_SQL_DBNAME nvarchar(300)
DECLARE @DESTINATION_DATABASENAME TABLE (  dbname varchar(100))


SELECT @SOURCEDBSERVER = '[db01]' --==> Replace Your Source DB serverName Here

SELECT @DESTINATIONDBSERVER = '[db02]' --==> Replace Your Target DB serverName Here

SELECT
  @SOURCE_SQL_DBNAME = 'select name from ' + @SOURCEDBSERVER + '.master.sys.databases where database_id>4'
INSERT INTO @SOURCE_DATABASENAME EXEC sp_executesql @SOURCE_SQL_DBNAME
SELECT
  @DESTINATION_SQL_DBNAME = 'select name from ' + @DESTINATIONDBSERVER + '.master.sys.databases where database_id>4'
INSERT INTO @DESTINATION_DATABASENAME EXEC sp_executesql @DESTINATION_SQL_DBNAME
 

CREATE TABLE #SOURCEDB_INDEX (
  DB nvarchar(100),
  TableName nvarchar(500),
  IndexName varchar(300),
  Type varchar(100)
)
CREATE TABLE #DESTINATIONDB_INDEX (
  DB nvarchar(100),
  TableName nvarchar(500),
  IndexName varchar(300),
  Type varchar(100)
)


 
DECLARE dbcursor CURSOR FOR
SELECT
  dbname
FROM @SOURCE_DATABASENAME

OPEN dbcursor
DECLARE @Source_DBname varchar(100)
FETCH NEXT FROM dbcursor INTO @Source_DBNAME
WHILE @@FETCH_STATUS = 0
BEGIN

  DECLARE @SOURCE_SQL nvarchar(max)

  SELECT
    @SOURCE_SQL ='  
  insert into #SOURCEDB_INDEX SELECT ' + '''' + @Source_DBname + '''' + ',
  so.name AS TableName,
  si.name AS IndexName,
  si.type_desc AS IndexType
  FROM ' + @SOURCEDBSERVER + '.' + @Source_DBname + '.sys.indexes si
  JOIN ' + @SOURCEDBSERVER + '.' + @Source_DBname + '.sys.objects so 
  ON si.[object_id] = so.[object_id]
  WHERE
  so.type = ' + '''U''' + '
  AND si.name IS NOT NULL ORDER BY
  so.name, si.type
  '

 
  EXEC sp_executesql @SOURCE_SQL
  FETCH NEXT FROM dbcursor INTO @Source_DBname
END

CLOSE dbcursor

DEALLOCATE dbcursor
 
 


 
DECLARE dbcursor CURSOR FOR
SELECT
  dbname
FROM @DESTINATION_DATABASENAME

OPEN dbcursor
DECLARE @DESTINATION_DBname varchar(100)
FETCH NEXT FROM dbcursor INTO @DESTINATION_DBNAME
WHILE @@FETCH_STATUS = 0
BEGIN

  DECLARE @DESTINATION_SQL nvarchar(max)

  SELECT
    @DESTINATION_SQL ='
  insert into #DESTINATIONDB_INDEX SELECT ' + '''' + @DESTINATION_DBname + '''' + ',         
  so.name AS TableName,
  si.name AS IndexName,
  si.type_desc AS IndexType
  FROM ' + @DESTINATIONDBSERVER + '.' + @DESTINATION_DBname + '.sys.indexes si
  JOIN ' + @DESTINATIONDBSERVER + '.' + @DESTINATION_DBname + '.sys.objects so 
  ON si.[object_id] = so.[object_id]
  WHERE
  so.type = ' + '''U''' + '
  AND si.name IS NOT NULL ORDER BY
  so.name, si.type     '

  
  EXEC sp_executesql @DESTINATION_SQL
  FETCH NEXT FROM dbcursor INTO @DESTINATION_DBname
END

CLOSE dbcursor

DEALLOCATE dbcursor
 

;
WITH cte
AS (SELECT
  DB,
  TableName,
  IndexName,
  HASHBYTES('sha1', concat(DB, TableName, IndexName)) AS tb1
FROM #SOURCEDB_INDEX)
SELECT
  ISNULL(c.DB, b.DB) AS DB,
  ISNULL(c.TableName, b.TableName) AS TableName,
  ISNULL(c.IndexName, b.IndexName) AS IndexName,
  CASE
    WHEN c.tb1 IS NULL THEN 'Available On ' + @DESTINATIONDBSERVER + ' Only'
    WHEN c.tb1 IS NOT NULL AND
      b.tb1 IS NOT NULL THEN 'Available On Both Servers'
    WHEN b.tb1 IS NULL THEN 'Available On ' + @SOURCEDBSERVER + ' Only'
  END AS 'Status'
FROM cte c
FULL JOIN (SELECT
  DB,
  TableName,
  IndexName,
  HASHBYTES('sha1', concat(DB, TableName, IndexName)) AS tb1
FROM #DESTINATIONDB_INDEX) b
  ON b.tb1 = c.tb1
ORDER BY tablename

DROP TABLE #SOURCEDB_INDEX
DROP TABLE #DESTINATIONDB_INDEX