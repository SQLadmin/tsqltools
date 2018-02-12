/*****************************************************************
                 -------------------------------------
                 tsqltools - RDS - Auto CDC
                 -------------------------------------
Description: This stored procedure will help you to enable CDC 
automatically when a tables is created. This is basically a database
Trigger and it'll ecxecute enable CDC procedure when we creat a 
new table. This is a database level trigger, so it won't replicate
the new tables which are in another database.

How to Run: If you to enable this on DBAdmin database, 
USE DBAdmin
GO
-- Execute the below Query.

-------------------------------------------------------------------

Version: v1.0 
Release Date: 2018-02-10
Author: Bhuvanesh(@SQLadmin)
Feedback: mailto:r.bhuvanesh@outlook.com
Updates: https://github.com/SqlAdmin/tsqltools/
Blog: http://www.sqlgossip.com/automatically-enable-cdc-in-rds-sql-server/
License: GPL-3.0
  tsqltools is free to download.It contains Tsql stored procedures 
  and scripts to help the DBAs and Developers to make job easier
(C) 2018

*******************************************************************/  

-- READ THE DESCRIPTION BEFORE EXECUTE THIS ***

CREATE TABLE [dbo].[DBSchema_Change_Log]
(
    [RecordId] [int] IDENTITY(1,1) NOT NULL,
    [EventTime] [datetime] NULL,
    [LoginName] [varchar](50) NULL,
    [UserName] [varchar](50) NULL,
    [DatabaseName] [varchar](50) NULL,
    [SchemaName] [varchar](50) NULL,
    [ObjectName] [varchar](50) NULL,
    [ObjectType] [varchar](50) NULL,
    [DDLCommand] [varchar](max) NULL

) ON [PRIMARY]
GO

CREATE TRIGGER [auto_cdc] ON Database
FOR CREATE_TABLE  
AS 
DECLARE       @eventInfo XML 
SET           @eventInfo = EVENTDATA() 
INSERT INTO DBSchema_Change_Log
VALUES
    (
        REPLACE(CONVERT(VARCHAR(50),@eventInfo.query('data(/EVENT_INSTANCE/PostTime)')),'T', ' '),
        CONVERT(VARCHAR(50),@eventInfo.query('data(/EVENT_INSTANCE/LoginName)')),
        CONVERT(VARCHAR(50),@eventInfo.query('data(/EVENT_INSTANCE/UserName)')),
        CONVERT(VARCHAR(50),@eventInfo.query('data(/EVENT_INSTANCE/DatabaseName)')),
        CONVERT(VARCHAR(50),@eventInfo.query('data(/EVENT_INSTANCE/SchemaName)')),
        CONVERT(VARCHAR(50),@eventInfo.query('data(/EVENT_INSTANCE/ObjectName)')),
        CONVERT(VARCHAR(50),@eventInfo.query('data(/EVENT_INSTANCE/ObjectType)')),
        CONVERT(VARCHAR(MAX),@eventInfo.query('data(/EVENT_INSTANCE/TSQLCommand/CommandText)')) 
) 
 
declare @tbl varchar(100) =(select top(1)
    OBJECTname
from DBSchema_Change_Log
order by recordid desc)
 DECLARE @schemaname varchar(100) =(select top(1)
    schemaname
from DBSchema_Change_Log
order by recordid desc)
DECLARE @primarykey int =( select case CONSTRAINT_TYPE when 'PRIMARY KEY' THen 1   else 0 end as PRIMARYkey
from INFORMATION_SCHEMA.TABLE_CONSTRAINTS
where TABLE_NAME=@tbl and TABLE_SCHEMA=@schemaname)
 
exec sys.sp_cdc_enable_table 
@source_schema = @schemaname, 
@source_name = @tbl, 
@role_name = NULL, 
@supports_net_changes = @primarykey 
GO
--Enable the Trigger 
ENABLE TRIGGER [auto_cdc] ON database
GO
 
