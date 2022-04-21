--Source: https://github.com/GPep/ToolsDB/blob/master/SPs/AGHealthCheck.sql

USE [Tools]
GO


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('AGHealthCheck') IS NULL
  EXEC ('CREATE PROCEDURE AGHealthCheck AS RETURN 0;')
GO

ALTER PROCEDURE AGHealthCheck
AS
BEGIN

-- =============================================
-- Author:		Glenn Pepper
-- Create date: 2018-09-18
-- Version 1.0
-- Description:	This Stored Procedure Checks the health status 
-- of AG groups and emails details to the DBAs. This is normally run as Morning Check
-- but is also triggered by an AlwaysON Alert.
-- =============================================

IF OBJECT_ID('tempdb.dbo.#AGHealthStatus','u') IS NOT NULL
BEGIN
DROP TABLE #AGHealthStatus
END

IF OBJECT_ID('tempdb.dbo.#PrimaryNode','u') IS NOT NULL
BEGIN
DROP TABLE #PrimaryNode
END


DECLARE @agName varchar(20)

SET @agName = (SELECT top 1 ag.name FROM sys.availability_groups ag)

--Check if this is the Primary Node before running scripts
IF (SELECT dbo.fn_hadr_group_is_primary(@agName) ) = 1
BEGIN

--Confirm current primary node
SELECT hags.primary_replica AS PrimaryNode
  INTO #PrimaryNode
  FROM sys.dm_hadr_availability_group_states hags
  INNER JOIN sys.availability_groups ag ON ag.group_id = hags.group_id



--Check health status of AlwaysOn AGs Secondaries
DECLARE @HADRName  varchar(25)
SET @HADRName = @@SERVERNAME
select n.group_name,n.replica_server_name,n.node_name,rs.role_desc,
db_name(drs.database_id) as 'DBName',drs.synchronization_state_desc,drs.synchronization_health_desc
INTO #AGHealthStatus
from sys.dm_hadr_availability_replica_cluster_nodes n
join sys.dm_hadr_availability_replica_cluster_states cs
on n.replica_server_name = cs.replica_server_name
join sys.dm_hadr_availability_replica_states rs 
on rs.replica_id = cs.replica_id
join sys.dm_hadr_database_replica_states drs
on rs.replica_id=drs.replica_id
where n.replica_server_name <> @HADRName

--Send Details to DBA Team

DECLARE @ServerName NVARCHAR(50);
DECLARE @EMAIL_SUBJECT NVARCHAR(250);
DECLARE @EMAILADDRESS NVARCHAR(200); 

SET @ServerName = @@SERVERNAME
SET @EMAIL_SUBJECT = N'AG Health Status on ' + @ServerName
SET @EMAILADDRESS = (SELECT Email_Address FROM msdb.dbo.sysoperators WHERE enabled = 1)

DECLARE @msg varchar(max), @tbl varchar(max), @tbl2 varchar(max), @tbl3 varchar(max)

SET @tbl = '<font face=verdana size=2><B>This is the current Primary Node</B></font><br /><br />
			<style type="text/css">h2, body {font-family: Arial, verdana;} table{font-size:11px; border-collapse:collapse;} td{background-color:#ffffff; border:1px solid black; padding:3px;} th{background-color:#46f610;border:1px solid black; padding:3px;}</style>
			<table cellpadding=2 cellspacing=2><tr><th><B>PRIMARY NODE</B></th>'
			+ 
			CAST((SELECT td=PrimaryNode,''
			FROM #PrimaryNode for xml path('tr'), type
				) as varchar(max) )
			+ '</table><BR>

			<font face=verdana size=2><B>This is the current health status of the Availability group databases for this AlwaysOn Cluster</b></font><br /><br />'
			+
			'<table cellpadding=2 cellspacing=2><tr><th><B>Group Name</B></th><th><B>Replica Server Name</B></th><th><B>Node Name</B></th><th><B>Role Description</B></th><th><B>DB Name</B></th>
			<th><B>Synchronization State</B></th><th><B>Current Health Status</B></th>'
			+
			CAST((select td = group_name, '', td = replica_server_name,'', td = node_name,'', td = role_desc,'',
			td = DBName, '', td = synchronization_state_desc, '', td = synchronization_health_desc,''
			FROM #AGHealthStatus
			for xml path('tr'), type
				) as varchar(max) )
			+ '</table><BR>'


exec msdb.dbo.sp_send_dbmail 
	@profile_name = @ServerName,
	@subject = @EMAIL_SUBJECT, 
	@body = @tbl, @body_format = 'HTML', 
	@recipients = @EMAILADDRESS

END

ELSE 
RETURN 
END

