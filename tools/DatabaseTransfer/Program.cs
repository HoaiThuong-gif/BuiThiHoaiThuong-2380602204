using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using NhomBar;

// Copies rows into an EMPTY target, never restores/deletes the source database.
var localCheck=args.Contains("--local-copy-check");
if(!localCheck&&!args.Contains("--confirm-empty-target"))throw new InvalidOperationException("Review the target and pass --confirm-empty-target.");
var localSettings=new ConfigurationBuilder().AddJsonFile(Path.GetFullPath("backend/appsettings.json"),optional:true).AddJsonFile(Path.GetFullPath("backend/appsettings.Development.json"),optional:true).AddJsonFile(Path.GetFullPath("backend/appsettings.local.json"),optional:true).Build();
var sourceString=Environment.GetEnvironmentVariable("NHOMBAR_SOURCE_SQL")??localSettings.GetConnectionString("SqlServer")??throw new InvalidOperationException("Source SQL connection is not configured.");
var testName="NhomBarTransferTests_"+Guid.NewGuid().ToString("N");
var targetString=localCheck?$"Server=.;Database={testName};Trusted_Connection=True;Encrypt=False;TrustServerCertificate=True":Environment.GetEnvironmentVariable("NHOMBAR_TARGET_SQL")??throw new InvalidOperationException("Set NHOMBAR_TARGET_SQL securely in this process.");
var targetConfig=new SqlConnectionStringBuilder(targetString);
if(!localCheck&&(!targetConfig.DataSource.Contains(".database.windows.net",StringComparison.OrdinalIgnoreCase)||targetConfig.InitialCatalog!="NhomBar2380602204"||targetConfig.TrustServerCertificate||targetConfig.Encrypt.ToString() is "False" or "Optional"))throw new InvalidOperationException("Target must be the encrypted Azure SQL database NhomBar2380602204.");
await using var targetDb=new AppDb(new DbContextOptionsBuilder<AppDb>().UseSqlServer(targetString).Options);
try {
    if(await targetDb.Database.CanConnectAsync()){
        await using var existing=new SqlConnection(targetString);await existing.OpenAsync();
        await using var check=new SqlCommand("SELECT SUM(p.rows) FROM sys.tables t JOIN sys.partitions p ON p.object_id=t.object_id AND p.index_id IN(0,1) WHERE t.is_ms_shipped=0 AND t.name<>'__EFMigrationsHistory'",existing);
        var count=await check.ExecuteScalarAsync();if(count is not null and not DBNull&&Convert.ToInt64(count)>0)throw new InvalidOperationException("Target already contains rows. Nothing was overwritten.");
    }
    await targetDb.Database.MigrateAsync();
    await using var source=new SqlConnection(sourceString);await source.OpenAsync();
    await using var target=new SqlConnection(targetString);await target.OpenAsync();
    await using var sourceTransaction=(SqlTransaction)await source.BeginTransactionAsync(IsolationLevel.Serializable);
    await using var targetTransaction=(SqlTransaction)await target.BeginTransactionAsync();
    var tables=new HashSet<string>(StringComparer.Ordinal);
    await using(var cmd=new SqlCommand("SELECT name FROM sys.tables WHERE is_ms_shipped=0 AND schema_id=SCHEMA_ID('dbo') AND name<>'__EFMigrationsHistory'",source,sourceTransaction)){
        await using var reader=await cmd.ExecuteReaderAsync();while(await reader.ReadAsync())tables.Add(reader.GetString(0));
    }
    var expected=targetDb.Model.GetEntityTypes().Select(x=>x.GetTableName()!).ToHashSet(StringComparer.Ordinal);
    if(!tables.SetEquals(expected))throw new InvalidOperationException("Source schema differs from this app. Apply reviewed migrations first; no data was copied.");
    var dependencies=tables.ToDictionary(t=>t,_=>new HashSet<string>());
    await using(var cmd=new SqlCommand("SELECT OBJECT_NAME(parent_object_id),OBJECT_NAME(referenced_object_id) FROM sys.foreign_keys WHERE parent_object_id<>referenced_object_id",source,sourceTransaction)){
        await using var reader=await cmd.ExecuteReaderAsync();while(await reader.ReadAsync())if(dependencies.TryGetValue(reader.GetString(0),out var set)&&tables.Contains(reader.GetString(1)))set.Add(reader.GetString(1));
    }
    var copied=new HashSet<string>();
    while(copied.Count<tables.Count){
        var ready=tables.Where(t=>!copied.Contains(t)&&dependencies[t].All(copied.Contains)).ToList();
        if(ready.Count==0)throw new InvalidOperationException("Circular dependencies require a reviewed transfer plan.");
        foreach(var table in ready){
            var quoted="[dbo].["+table.Replace("]","]]")+"]";
            await using(var cmd=new SqlCommand("SELECT * FROM "+quoted,source,sourceTransaction)){cmd.CommandTimeout=300;
                await using var reader=await cmd.ExecuteReaderAsync();using var bulk=new SqlBulkCopy(target,SqlBulkCopyOptions.CheckConstraints|SqlBulkCopyOptions.KeepIdentity,targetTransaction){DestinationTableName=quoted,EnableStreaming=true,BatchSize=500,BulkCopyTimeout=300};
                for(int i=0;i<reader.FieldCount;i++)bulk.ColumnMappings.Add(reader.GetName(i),reader.GetName(i));await bulk.WriteToServerAsync(reader);
            }
            var original=await Digest(source,sourceTransaction,quoted);var clone=await Digest(target,targetTransaction,quoted);
            if(original!=clone)throw new InvalidOperationException("Verification failed for "+table+"; target transaction will be rolled back.");
            Console.WriteLine("VERIFIED: "+table+" (SHA-256 match; values not logged)");copied.Add(table);
        }
    }
    await targetTransaction.CommitAsync();await sourceTransaction.CommitAsync();
    Console.WriteLine($"VERIFIED: {copied.Count} tables transferred with original identifiers, account hashes and relationships. Source was read only.");
}finally{
    if(localCheck&&targetDb.Database.GetDbConnection().Database==testName)await targetDb.Database.EnsureDeletedAsync();
}
static async Task<string> Digest(SqlConnection connection,SqlTransaction transaction,string table){
    using var hash=IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
    await using var command=new SqlCommand("SELECT * FROM "+table+" ORDER BY [Id] FOR JSON PATH, INCLUDE_NULL_VALUES",connection,transaction){CommandTimeout=300};
    await using var reader=await command.ExecuteReaderAsync();while(await reader.ReadAsync())hash.AppendData(Encoding.Unicode.GetBytes(reader.GetString(0)));
    return Convert.ToHexString(hash.GetHashAndReset());
}
