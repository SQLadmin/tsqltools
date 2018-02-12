/*****************************************************************
                 ----------------------- 
                 T-SQLtools - DBA-Config
                 -----------------------

DESCRIPTION: This is a simple T-SQL query to configure your SQL 
Server with Best Practices. After install SQL Server/Any exsiting 
SQL Server you can Run this. 

Parameters:

+-------------+---------------+-------------------------------+-------------------------------+-----------------------+--------------------------------------------+
| Category    | Paramter      | Purpose                       | Default Value (Best Practice) | Value Type            | Example                                    |
+-------------+---------------+-------------------------------+-------------------------------+-----------------------+--------------------------------------------+
| Memroy      | MinMem        | Assign Minimum Memory         | 0                             | Values in MB          | DECLARE @MinMem int = 1                    |
+-------------+---------------+-------------------------------+-------------------------------+-----------------------+--------------------------------------------+
| Memory      | MaxMem        | Assign Maximum  Memory        | 90                            | Values in Percentage  | DECLARE @MaxMem int=90                     |
+-------------+---------------+-------------------------------+-------------------------------+-----------------------+--------------------------------------------+
| Parallelism | P_MAXDOP      | Set Max Degree of Parallelism | Based on CPU Cores            | Numbers               | DECLARE @P_MAXDOP INT=3                    |
+-------------+---------------+-------------------------------+-------------------------------+-----------------------+--------------------------------------------+
| Parallelism | CostThresHold | Cost value to use Parallelism | 50                            | Numbers               | DECLARE @CostThresHold INT                 |
+-------------+---------------+-------------------------------+-------------------------------+-----------------------+--------------------------------------------+
| Files       | DBfile        | Default Data files            | Current Data file location    | Path for the files    | DECLARE @DBfile nvarchar(500)='C:\Data'    |
+-------------+---------------+-------------------------------+-------------------------------+-----------------------+--------------------------------------------+
| Files       | Logfile       | Default Log files             | Current Log file location     | Path for the Log file | DECLARE @Logfile nvarchar(500)='C:\Log'    |
+-------------+---------------+-------------------------------+-------------------------------+-----------------------+--------------------------------------------+
| Files       | Backup        | Default path for Backup files | Current Backup file path      | Path for Backups      | DECLARE @Backup NVARCHAR(500)='C:\backups' |
+-------------+---------------+-------------------------------+-------------------------------+-----------------------+--------------------------------------------+


Here is how I executed?

DECLARE @MinMem int  -- Let the query calculate this
DECLARE @MaxMem int  -- Let the query calculate this
DECLARE @P_MAXDOP INT  -- Let the query calculate this
DECLARE @CostThresHold INT  -- Let the query calculate this
DECLARE @DBfile nvarchar(500) -- 'C:\Data'
DECLARE @Logfile nvarchar(500) -- 'C:\Log'
DECLARE @Backup NVARCHAR(500)  -- 'C:\Backups'


Credits: This Max_DOP value query written by Kin 
https://dba.stackexchange.com/users/8783/kin


Version: v1.0 
Release Date: 2018-02-12
Author: Bhuvanesh(@SQLadmin)
Feedback: mailto:r.bhuvanesh@outlook.com
Updates: www.sqlgossip.com
License:  GPL-3.0


(C) 2018
 
 
******************************************************************/

-- Global Declarations
DECLARE @MinMem int
DECLARE @MaxMem int
DECLARE @P_MAXDOP INT
DECLARE @CostThresHold INT
DECLARE @DBfile nvarchar(500)
DECLARE @Logfile nvarchar(500)
DECLARE @Backup NVARCHAR(500)

EXEC sp_configure 'show advanced options', 1;

-- Other Settings as per the Best Practice 
EXEC sp_configure 'index create memory', 0
RECONFIGURE;
EXEC sp_configure 'min memory per query', 1024;
RECONFIGURE;
EXEC sp_configure 'priority boost', 0;
RECONFIGURE;
EXEC sp_configure 'max worker threads', 0;
RECONFIGURE;
EXEC sp_configure 'lightweight pooling', 0;
RECONFIGURE;
EXEC sp_configure 'fill factor', 0;
RECONFIGURE;
EXEC sp_configure 'backup compression default', 1;
RECONFIGURE WITH OVERRIDE ;

-- Setting up Min/Max SQL Memory
SET @MinMem = coalesce(nullif(@MinMem, ''), 0)
DECLARE @MaximumMememory int
SET @MaxMem = coalesce(nullif(@MaxMem, ''), 90)
Select @MaximumMememory=(select ([total_physical_memory_kb] / 1024  * @MaxMem/100) as totalmin
    FROM [master].[sys].[dm_os_sys_memory])
Exec sp_configure 'min server memory', @MinMem;
Exec sp_configure 'max server memory', @MaximumMememory;

-- Setting up MAX DOP and Cost Threshold limit
DECLARE @hyperthreadingRatio bit
DECLARE @logicalCPUs int
DECLARE @HTEnabled int
DECLARE @physicalCPU int
DECLARE @SOCKET int
DECLARE @logicalCPUPerNuma int
DECLARE @NoOfNUMA int
DECLARE @MaxDOP int

select @logicalCPUs = cpu_count -- [Logical CPU Count]
    , @hyperthreadingRatio = hyperthread_ratio --  [Hyperthread Ratio]
    , @physicalCPU = cpu_count / hyperthread_ratio -- [Physical CPU Count]
    , @HTEnabled = case 
        when cpu_count > hyperthread_ratio
            then 1
        else 0
        end
-- HTEnabled
from sys.dm_os_sys_info
option
(recompile);

select @logicalCPUPerNuma = COUNT(parent_node_id)
-- [NumberOfLogicalProcessorsPerNuma]
from sys.dm_os_schedulers
where [status] = 'VISIBLE ONLINE'
    and parent_node_id < 64
group by parent_node_id
option
(recompile);

select @NoOfNUMA = count(distinct parent_node_id)
from sys.dm_os_schedulers
-- find NO OF NUMA Nodes 
where [status] = 'VISIBLE ONLINE'
    and parent_node_id < 64
SET @P_MAXDOP = coalesce(nullif(@P_MAXDOP, ''), (select
    --- 8 or less processors and NO HT enabled
    case 
        when @logicalCPUs < 8
            and @HTEnabled = 0
            then CAST(@logicalCPUs as varchar(3))
                --- 8 or more processors and NO HT enabled
        when @logicalCPUs >= 8
            and @HTEnabled = 0
            then  8
                --- 8 or more processors and HT enabled and NO NUMA
        when @logicalCPUs >= 8
            and @HTEnabled = 1
            and @NoofNUMA = 1
            then CAST(@logicalCPUPerNuma / @physicalCPU as varchar(3))
                --- 8 or more processors and HT enabled and NUMA
        when @logicalCPUs >= 8
            and @HTEnabled = 1
            and @NoofNUMA > 1
            then CAST(@logicalCPUPerNuma / @physicalCPU as varchar(3))
        else ''
        end as Recommendations
))
SET @CostThresHold = coalesce(nullif(@CostThresHold, ''), 50)
EXEC sp_configure 'max degree of parallelism', @P_MAXDOP
EXEC sp_configure 'cost threshold for parallelism', @CostThresHold
;

-- Setting up Default Directories for Data/Log/Backup
DECLARE @BackupDirectory NVARCHAR(100)
EXEC master..xp_instance_regread @rootkey = 'HKEY_LOCAL_MACHINE',  
    @key = 'Software\Microsoft\MSSQLServer\MSSQLServer',  
    @value_name = 'BackupDirectory', @BackupDirectory = @BackupDirectory OUTPUT
;
SET @Backup = coalesce(nullif(@Backup, ''), @BackupDirectory)
SET @DBfile = coalesce(nullif(@DBfile, ''), (SELECT CONVERT(nvarchar(500), SERVERPROPERTY('INSTANCEDEFAULTDATAPATH'))))
SET @Logfile = coalesce(nullif(@Logfile, ''), (SELECT CONVERT(nvarchar(500), SERVERPROPERTY('INSTANCEDEFAULTLOGPATH'))))


EXEC   xp_instance_regwrite 
N'HKEY_LOCAL_MACHINE', 
N'Software\Microsoft\MSSQLServer\MSSQLServer', 
N'DefaultData', 
REG_SZ, 
@DBfile

EXEC   xp_instance_regwrite 
N'HKEY_LOCAL_MACHINE', 
N'Software\Microsoft\MSSQLServer\MSSQLServer', 
N'DefaultLog', 
REG_SZ, 
@Logfile

EXEC   xp_instance_regwrite 
N'HKEY_LOCAL_MACHINE', 
N'Software\Microsoft\MSSQLServer\MSSQLServer', 
N'BackupDirectory', 
REG_SZ, 
@Logfile  
GO