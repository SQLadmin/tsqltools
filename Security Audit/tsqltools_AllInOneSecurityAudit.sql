/*****************************************************************
                 -------------------------------------
                 tsqltools - All In One Security Audit
                 -------------------------------------

Version: v1.0 
Release Date: 2017-06-02
Author: Bhuvanesh(@SQLadmin)
Feedback: mailto:r.bhuvanesh@outlook.com
Updates: https://github.com/SqlAdmin/tsqltools/

License: 
  tsqltools is free to download.It contains Tsql stored procedures 
  and scripts to help the DBAs and Developers to make job easier
(C) 2017

*******************************************************************/  
/*
Checks:
-------
1. SQL services account - All sql services must run under an AD account or Administrator account
2. Default directories  - Data,Log and backup directories must not be in C:\ drive
3. Startup Type         - SQL serices should be start automatically
4. SA Account name      - Its a best practice to rename SA account 
5. Disable SA account   - Create an alternate SQL user with SYSADMIN priileges and disable SA account
6. Password Check       - Change SQL users password at every 3 months, 
                          Don't make Username and password is same, 
                          Don't user blank passwords
7. SysAdmin User        - List of users who have sysadmin role.
8. SQL Port Type        - SQL is using Static Port or Dynamic Port
9. SQL Port             - Use any port other than 1433.
10. Number of databases - Use 100 or < 100 databases for a server.
11. Buildin Administrator - Disables Buildin\Administrator group from sql login. 
12. Database level Access - Limit the db_owner users.                         
*/


IF OBJECT_ID('tempdb.dbo.#Result', 'U') IS NOT NULL
  DROP TABLE #result

CREATE TABLE #result (
  CHECKS nvarchar(500),
  RECOMMENTATION nvarchar(500)
)

IF OBJECT_ID('tempdb.dbo.#ServiceAccount', 'U') IS NOT NULL
  DROP TABLE #serviceaccount

CREATE TABLE #serviceaccount (
  servicename varchar(100),
  serviceaccount varchar(100)
)

INSERT INTO #serviceaccount
  SELECT
    servicename,
    service_account
  FROM sys.dm_server_services;

--select * from #ServiceAccount 
INSERT INTO #result
  SELECT
    Concat('Service Account - ', servicename),
    CASE
        WHEN serviceaccount like 'NT%' or serviceaccount like 'Local%' THEN 'Try to change an AD account or Administrator Account'
      ELSE 'OK'
    END AS Recommendation
  FROM #serviceaccount

IF OBJECT_ID('tempdb.dbo.#DataDirectory', 'U') IS NOT NULL
  DROP TABLE #datadirectory

CREATE TABLE #datadirectory (
  directorytype varchar(500),
  defaultdirectory nvarchar(500)
)

DECLARE @DefaultBackup nvarchar(512)

EXEC master.dbo.Xp_instance_regread N'HKEY_LOCAL_MACHINE',
                                    N'Software\Microsoft\MSSQLServer\MSSQLServer',
                                    N'BackupDirectory',
                                    @DefaultBackup OUTPUT

INSERT INTO #datadirectory
  SELECT
    'Data',
    CONVERT(nvarchar(500), SERVERPROPERTY('INSTANCEDEFAULTDATAPATH'))

INSERT INTO #datadirectory
  SELECT
    'Log',
    CONVERT(nvarchar(500), SERVERPROPERTY('INSTANCEDEFAULTLOGPATH'))

INSERT INTO #datadirectory
  SELECT
    'Backup',
    @DefaultBackup

--select * from #DataDirectory 
INSERT INTO #result
  SELECT
    Concat('Default Directory - ', directorytype),
    CASE
      WHEN defaultdirectory LIKE 'C:\%' THEN 'Please Avoid to keep Data files in C: drive'
      ELSE 'OK'
    END AS Recommendation
  FROM #datadirectory

IF OBJECT_ID('tempdb.dbo.#StartupType', 'U') IS NOT NULL
  DROP TABLE #startuptype

CREATE TABLE #startuptype (
  sqlservice varchar(50),
  startuptype nvarchar(50)
)

INSERT INTO #startuptype
  SELECT
    servicename,
    startup_type_desc
  FROM sys.dm_server_services;

--select * from #StartupType 
INSERT INTO #result
  SELECT
    Concat('Startup Type - ', sqlservice),
    CASE
      WHEN startuptype LIKE 'Manual' THEN 'Make this startup type as Automatic'
      ELSE 'OK'
    END AS Recommendation
  FROM #startuptype

IF OBJECT_ID('tempdb.dbo.#saname', 'U') IS NOT NULL
  DROP TABLE #saname

CREATE TABLE #saname (
  NAME varchar(20)
)

INSERT INTO #saname
  SELECT
    NAME
  FROM sys.sql_logins
  WHERE sid = 0x01;

INSERT INTO #result
  SELECT
    Concat('SA account name - ', NAME),
    CASE
      WHEN NAME = 'sa' THEN 'Rename SA account to someother name'
      ELSE 'OK'
    END AS Recomendation
  FROM #saname

IF OBJECT_ID('tempdb.dbo.#saaccountstatus', 'U') IS NOT NULL
  DROP TABLE #saaccountstatus

CREATE TABLE #saaccountstatus (
  NAME varchar(10),
  status int
)

INSERT INTO #saaccountstatus
  SELECT
    NAME,
    is_disabled
  FROM sys.server_principals
  WHERE NAME = 'sa'

INSERT INTO #result
  SELECT
    'SA Account Status',
    CASE
      WHEN status = 1 THEN 'OK'
      ELSE 'Its a best practice to disable SA account or rename it'
    END AS Recomendation
  FROM #saaccountstatus

IF OBJECT_ID('tempdb.dbo.#PasswordCheck', 'U') IS NOT NULL
  DROP TABLE #passwordcheck

CREATE TABLE #passwordcheck (
  passwordtype varchar(20),
  logins varchar(50)
)

INSERT INTO #passwordcheck
  SELECT
    'Name = Password',
    NAME
  FROM sys.sql_logins
  WHERE Pwdcompare(NAME, password_hash) = 1;

INSERT INTO #passwordcheck
  SELECT
    'Blank Password',
    NAME
  FROM sys.sql_logins
  WHERE Pwdcompare('', password_hash) = 1;

--select * from  #PasswordCheck 
DECLARE @lastPassword TABLE (
  date date,
  logins varchar(100)
)

INSERT INTO @lastPassword
  SELECT
    CONVERT(date, LOGINPROPERTY([name], 'PasswordLastSetTime')) AS
    'PasswordChanged',
    NAME
  FROM sys.sql_logins
  WHERE NOT (LEFT([name], 2) = '##'
  AND RIGHT([name], 2) = '##')
  ORDER BY CONVERT(date, LOGINPROPERTY([name], 'PasswordLastSetTime'))

INSERT INTO #passwordcheck
  SELECT
    Concat(DATEDIFF(DAY, date, (SELECT
      CAST(GETDATE() AS date))
    ), ' Days Ago'
    ) AS
    LastUpdated,
    logins
  FROM @lastPassword

INSERT INTO #result
  SELECT
    Concat('Password Check - ', logins),
    CASE
      WHEN passwordtype = 'Name = Password' THEN 'User Name and password is same'
      WHEN passwordtype = 'Blank Password' THEN 'Blank Password'
      WHEN passwordtype LIKE '%Days Ago%' THEN 'Password updated before 90Days Ago'
      ELSE 'OK'
    END
  FROM #passwordcheck

IF OBJECT_ID('tempdb.dbo.#sysadminusers', 'U') IS NOT NULL
  DROP TABLE #sysadminusers

CREATE TABLE #sysadminusers (
  logins varchar(50)
)

INSERT INTO #sysadminusers
  SELECT
    NAME
  FROM master.sys.server_principals
  WHERE IS_SRVROLEMEMBER('sysadmin', NAME) = 1
  ORDER BY NAME

INSERT INTO #result
  SELECT
    Concat('Admin User - ', logins),
    'This user has SysAdmin role' AS Recomentation
  FROM #sysadminusers

IF OBJECT_ID('tempdb.dbo.#sqlport', 'U') IS NOT NULL
  DROP TABLE #sqlport

CREATE TABLE #sqlport (
  porttype varchar(20),
  portnumber int
)

DECLARE @portNo nvarchar(10)

EXEC Xp_instance_regread @rootkey = 'HKEY_LOCAL_MACHINE',
                         @key =
                         'Software\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib\Tcp\IpAll',
                         @value_name = 'TcpDynamicPorts',
                         @value = @portNo OUTPUT

INSERT INTO #sqlport
  SELECT
    'Dynamic Port',
    @portNo

GO

DECLARE @portNo nvarchar(10)

EXEC Xp_instance_regread @rootkey = 'HKEY_LOCAL_MACHINE',
                         @key =
                         'Software\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib\Tcp\IpAll',
                         @value_name = 'TcpPort',
                         @value = @portNo OUTPUT

INSERT INTO #sqlport
  SELECT
    'Static Port',
    @portNo

--select * from #sqlport 
INSERT INTO #result
  SELECT
    Concat('SQL Port - ', porttype),
    portnumber
  FROM #sqlport
  WHERE portnumber IS NOT NULL

INSERT INTO #result
  SELECT
    Concat('SQL Port Number ', portnumber),
    CASE
      WHEN portnumber = 1433 THEN 'Please change Default port Number for SQL Server'
      WHEN portnumber != 1433 THEN 'OK'
    END
  FROM #sqlport
  WHERE portnumber IS NOT NULL

IF OBJECT_ID('tempdb.dbo.#numberofdb', 'U') IS NOT NULL
  DROP TABLE #numberofdb

CREATE TABLE #numberofdb (
  count int
)

INSERT INTO #numberofdb
  SELECT
    COUNT(*)
  FROM sys.databases

INSERT INTO #result
  SELECT
    Concat('Number of DB - ', count),
    CASE
      WHEN count > 100 THEN 'Please remove unwanted Databases'
      ELSE 'OK'
    END
  FROM #numberofdb

IF OBJECT_ID('tempdb.dbo.#buildinadmin', 'U') IS NOT NULL
  DROP TABLE #buildinadmin

CREATE TABLE #buildinadmin (
  login sysname,
  status smallint
)

INSERT INTO #buildinadmin
  SELECT
    NAME,
    status
  FROM sys.syslogins
  WHERE NAME = 'BUILTIN\Administrators'

IF EXISTS (SELECT
    *
  FROM #buildinadmin
  WHERE status = 9)
  INSERT INTO #result
    SELECT
      'Is Buildin AdminGroup enabled',
      CASE
        WHEN status = '9' THEN 'Please remove BUILTIN\Administrators login'
      END
    FROM #buildinadmin
ELSE
  INSERT INTO #result
    SELECT
      'Is Buildin AdminGroup enabled',
      'OK'
 Insert into #result 
 values 
 ('For More Updates','https://github.com/SqlAdmin/tsqltools/')
SELECT
  *
FROM #result

-------------------------------
-- Database Level Privileges --
-------------------------------
DECLARE @DB_USers TABLE (
  DBName sysname,
  UserName sysname,
  LoginType sysname,
  AssociatedRole varchar(max),
  create_date datetime,
  modify_date datetime
)

INSERT @DB_USers
EXEC sp_MSforeachdb '
use [?]
SELECT ''?'' AS DB_Name,
case prin.name when ''dbo'' then prin.name + '' (''+ (select SUSER_SNAME(owner_sid) from master.sys.databases where name =''?'') + '')'' else prin.name end AS UserName,
prin.type_desc AS LoginType,
isnull(USER_NAME(mem.role_principal_id),'''') AS AssociatedRole ,create_date,modify_date
FROM sys.database_principals prin
LEFT OUTER JOIN sys.database_role_members mem ON prin.principal_id=mem.member_principal_id
WHERE prin.sid IS NOT NULL and prin.sid NOT IN (0x00) and
prin.is_fixed_role <> 1 AND prin.name NOT LIKE ''##%'''

SELECT

  DBname,
  UserName,
  LoginType,
  create_date as CreateDate,
  modify_date as ModifiedDate,

  STUFF((SELECT
    ',' + CONVERT(varchar(500), associatedrole)

  FROM @DB_USers user2

  WHERE user1.DBName = user2.DBName
  AND user1.UserName = user2.UserName

  FOR xml PATH ('')), 1, 1, '') AS PermissionUser

FROM @DB_USers user1

GROUP BY dbname,
         username,
         logintype,
         create_date,
         modify_date

ORDER BY DBName, username
