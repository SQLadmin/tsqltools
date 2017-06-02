/*****************************************************************
                 -------------------------
                 tsqltools - Security Audit
                 -------------------------

Version: v1.0 
Release Date: 2017-06-02
Author: Bhuvanesh(@SQLadmin)
Feedback: mailto:r.bhuvanesh@outlook.com
Updates: http://medium.com/sqladmin
License: 
  tsqltools is free to download.It contains Tsql stored procedures 
  and scripts to help the DBAs and Developers to make job easier
(C) 2017
*******************************************************************/  

IF OBJECT_ID('tempdb.dbo.#Result', 'U') IS NOT NULL
  DROP TABLE #result

CREATE TABLE #result (
  checks nvarchar(500),
  recommendation nvarchar(500)
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
      WHEN serviceaccount LIKE 'NT %' THEN 'Try to change an AD account or Administrator Account'
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

SELECT
  *
FROM #result