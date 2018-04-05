/*****************************************************************
                 ----------------------- 
                 T-SQLtools - DBA-Config
                 -----------------------

DESCRIPTION: This is a simple T-SQL query to configure your SQL 
Server with Best Practices. After install SQL Server/Any exsiting 
SQL Server you can Run this. 

Parameters:

MinMem        	=> Assign Minimum Memory [Default 0]       
MaxMem        	=> Assign Maximum  Memory [Default 90%]       
P_MAXDOP      	=> Set Max Degree of Parallelism [ Default - Based on CPU Cores]
CostThresHold 	=> Cost value to use Parallelism [Default - 50]
DBfile        	=> Default Data files [Default - Current Data file location]           
Logfile       	=> Default Log files [Default- Current Log file location]            
Backup        	=> Default path for Backup files [Default - Current Data backup location ]
TempfilePath	=> Path for adding tempDB files [Default - Current Temp mdf file path]
TempfileSize	=> Size for new temp DB files [Default - 100MB]


Other Parameters will Reset to Default:
1. index create memory = 0
2. min memory per query = 1024
3. priority boost = 0
4. max worker threads = 0
5. lightweight pooling = 0
6. fill factor = 0
7. backup compression default = 1



Credits: This Max_DOP value query written by Kin 
https://dba.stackexchange.com/users/8783/kin


Version: v1.0 
Release Date: 2018-02-12
Author: Bhuvanesh(@SQLadmin)
Feedback: mailto:r.bhuvanesh@outlook.com
Blog: www.sqlgossip.com
License:  GPL-3.0
(C) 2018

*************************
Here is how I executed?
*************************

DECLARE @MinMem int -- Let the query calculate this        
DECLARE @MaxMem int -- Let the query calculate this        
DECLARE @P_MAXDOP INT -- Let the query calculate this      
DECLARE @CostThresHold INT -- Let the query calculate this 
DECLARE @DBfile nvarchar(500) = 'C:\Data'                  
DECLARE @Logfile nvarchar(500) =  'C:\Log'                 
DECLARE @Backup NVARCHAR(500) = 'C:\backups\'              
DECLARE @TempfilePath nvarchar(500) = 'C:\temp\'           
DECLARE @TempfileSize nvarchar(100) = '100MB' 

******************************************************************/

-- Global Declarations
DECLARE @MinMem int
DECLARE @MaxMem int
DECLARE @P_MAXDOP INT
DECLARE @CostThresHold INT
DECLARE @DBfile nvarchar(500)
DECLARE @Logfile nvarchar(500)
DECLARE @Backup NVARCHAR(500)
DECLARE @TempfilePath nvarchar(500) -- its mandatory
DECLARE @TempfileSize nvarchar(100) 


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

-- Add temp files
-- Calculate Number of Required TempDB Files
Declare @cpu int =( SELECT count(cpu_count)
FROM sys.dm_os_sys_info )
Declare @currenttempfine int = (SELECT count(name)
FROM tempdb.sys.database_files)
Declare @requiredtmpfiles int
IF @cpu < 8  Set @requiredtmpfiles = 5
IF @CPU >8  Set @requiredtmpfiles = 9

-- Declare variables for adding new tempDB files
Declare @int int
Declare @MAX_File int

SET @TempfileSize = coalesce(nullif(@TempfileSize, ''), '100MB')

IF @currenttempfine = @requiredtmpfiles    Print 'TempDB Files Are OK'
SET @int=1
Set @MAX_File = (@requiredtmpfiles -@currenttempfine)

-- Adding TempDB Files
WHILE @int <= @MAX_File
   Begin
    Declare @addfiles nvarchar(500)= (select 'ALTER DATABASE [tempdb] ADD FILE (NAME = '+'''tempdb_'+cast(@int as nvarchar(10))+''', FILENAME ='''+@TempfilePath+'tempdb_'+cast(@int as nvarchar(10))+'.ndf'' , SIZE = '+cast(@TempfileSize as nvarchar(10))+')' )
    --print @addfiles
    EXEC (@addfiles)
    SET @int=@int+1
END
IF @currenttempfine > @requiredtmpfiles print Cast(@currenttempfine-@requiredtmpfiles  as nvarchar(100))+' File need to be removed'
GO
 
