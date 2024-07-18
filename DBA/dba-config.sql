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
DECLARE @MinMem INT = 0;
DECLARE @MaxMem INT = 90;
DECLARE @P_MAXDOP INT;
DECLARE @CostThreshold INT = 50;
DECLARE @DBFile NVARCHAR(500);
DECLARE @LogFile NVARCHAR(500);
DECLARE @Backup NVARCHAR(500);
DECLARE @TempFilePath NVARCHAR(500); -- It's mandatory
DECLARE @TempFileSize NVARCHAR(100) = '100MB';

-- Show advanced options
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;

-- Other settings as per best practices
EXEC sp_configure 'index create memory', 0;
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
RECONFIGURE WITH OVERRIDE;

-- Setting up Min/Max SQL Memory
DECLARE @MaximumMemory INT;
SELECT @MaximumMemory = (total_physical_memory_kb / 1024 * @MaxMem / 100)
FROM [master].[sys].[dm_os_sys_memory];

EXEC sp_configure 'min server memory', @MinMem;
EXEC sp_configure 'max server memory', @MaximumMemory;
RECONFIGURE;

-- Setting up MAX DOP and Cost Threshold limit
DECLARE @HyperThreadingRatio BIT;
DECLARE @LogicalCPUs INT;
DECLARE @HTEnabled INT;
DECLARE @PhysicalCPU INT;
DECLARE @NoOfNUMA INT;
DECLARE @LogicalCPUPerNuma INT;

SELECT @LogicalCPUs = cpu_count,
       @HyperThreadingRatio = hyperthread_ratio,
       @PhysicalCPU = cpu_count / hyperthread_ratio,
       @HTEnabled = CASE WHEN cpu_count > hyperthread_ratio THEN 1 ELSE 0 END
FROM sys.dm_os_sys_info
OPTION (RECOMPILE);

SELECT @LogicalCPUPerNuma = COUNT(parent_node_id)
FROM sys.dm_os_schedulers
WHERE [status] = 'VISIBLE ONLINE' AND parent_node_id < 64
GROUP BY parent_node_id
OPTION (RECOMPILE);

SELECT @NoOfNUMA = COUNT(DISTINCT parent_node_id)
FROM sys.dm_os_schedulers
WHERE [status] = 'VISIBLE ONLINE' AND parent_node_id < 64;

SET @P_MAXDOP = COALESCE(NULLIF(@P_MAXDOP, ''), 
    CASE 
        WHEN @LogicalCPUs < 8 AND @HTEnabled = 0 THEN @LogicalCPUs
        WHEN @LogicalCPUs >= 8 AND @HTEnabled = 0 THEN 8
        WHEN @LogicalCPUs >= 8 AND @HTEnabled = 1 AND @NoOfNUMA = 1 THEN @LogicalCPUPerNuma / @PhysicalCPU
        WHEN @LogicalCPUs >= 8 AND @HTEnabled = 1 AND @NoOfNUMA > 1 THEN @LogicalCPUPerNuma / @PhysicalCPU
        ELSE ''
    END);

EXEC sp_configure 'max degree of parallelism', @P_MAXDOP;
EXEC sp_configure 'cost threshold for parallelism', @CostThreshold;
RECONFIGURE;

-- Setting up Default Directories for Data/Log/Backup
DECLARE @BackupDirectory NVARCHAR(100);
EXEC master..xp_instance_regread @rootkey = 'HKEY_LOCAL_MACHINE',  
    @key = 'Software\Microsoft\MSSQLServer\MSSQLServer',  
    @value_name = 'BackupDirectory', @BackupDirectory = @BackupDirectory OUTPUT;

SET @Backup = COALESCE(NULLIF(@Backup, ''), @BackupDirectory);
SET @DBFile = COALESCE(NULLIF(@DBFile, ''), (SELECT CONVERT(NVARCHAR(500), SERVERPROPERTY('INSTANCEDEFAULTDATAPATH'))));
SET @LogFile = COALESCE(NULLIF(@LogFile, ''), (SELECT CONVERT(NVARCHAR(500), SERVERPROPERTY('INSTANCEDEFAULTLOGPATH'))));

EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'DefaultData', REG_SZ, @DBFile;
EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'DefaultLog', REG_SZ, @LogFile;
EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'BackupDirectory', REG_SZ, @Backup;

-- Add temp files
-- Calculate Number of Required TempDB Files
DECLARE @CPU INT = (SELECT cpu_count FROM sys.dm_os_sys_info);
DECLARE @CurrentTempFileCount INT = (SELECT COUNT(name) FROM tempdb.sys.database_files);
DECLARE @RequiredTempFiles INT;

IF @CPU < 8 SET @RequiredTempFiles = 5;
ELSE IF @CPU >= 8 SET @RequiredTempFiles = 9;

-- Declare variables for adding new tempDB files
DECLARE @Int INT = 1;
DECLARE @MaxFile INT = @RequiredTempFiles - @CurrentTempFileCount;

-- Adding TempDB Files
WHILE @Int <= @MaxFile
BEGIN
    DECLARE @AddFiles NVARCHAR(500) = 'ALTER DATABASE [tempdb] ADD FILE (NAME = ''tempdb_' + CAST(@Int AS NVARCHAR(10)) + ''', FILENAME = ''' + @TempFilePath + 'tempdb_' + CAST(@Int AS NVARCHAR(10)) + '.ndf'', SIZE = ' + @TempFileSize + ')';
    EXEC (@AddFiles);
    SET @Int = @Int + 1;
END;

IF @CurrentTempFileCount > @RequiredTempFiles 
    PRINT CAST(@CurrentTempFileCount - @RequiredTempFiles AS NVARCHAR(100)) + ' file(s) need to be removed';
GO

