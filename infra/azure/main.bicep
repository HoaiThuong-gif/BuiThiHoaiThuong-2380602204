targetScope = 'resourceGroup'
param location string = resourceGroup().location
@maxLength(18)
param prefix string = 'nhombar2380602204'
@allowed(['FreeEvaluation', 'BasicPaid'])
param hostingMode string = 'FreeEvaluation'
@secure()
param sqlAdminPassword string
@secure()
param sqlAppPassword string
@secure()
param jwtKey string
@secure()
param brevoApiKey string
param senderEmail string
@secure()
param firebaseServiceAccountJson string
@description('Public IPv4 of the operator for initial transfer/migrations only; remove this rule after transfer.')
param operatorIp string
var free = hostingMode == 'FreeEvaluation'
var suffix = uniqueString(subscription().subscriptionId, resourceGroup().id)
var appName = '${prefix}-${suffix}'
var sqlName = '${prefix}-sql-${suffix}'
var dbName = 'NhomBar2380602204'

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${prefix}-plan'
  location: location
  kind: 'linux'
  sku: {
    name: free ? 'F1' : 'B1'
    tier: free ? 'Free' : 'Basic'
    capacity: 1
  }
  properties: { reserved: true }
}
resource sql 'Microsoft.Sql/servers@2023-08-01' = {
  name: sqlName
  location: location
  properties: {
    administratorLogin: 'nhombar_owner'
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}
resource database 'Microsoft.Sql/servers/databases@2023-08-01' = {
  parent: sql
  name: dbName
  location: location
  sku: free ? {
    name: 'GP_S_Gen5_2'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  } : {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: free ? {
    useFreeLimit: true
    freeLimitExhaustionBehavior: 'AutoPause'
    maxSizeBytes: 34359738368
    minCapacity: json('0.5')
    requestedBackupStorageRedundancy: 'Local'
  } : {
    maxSizeBytes: 2147483648
    requestedBackupStorageRedundancy: 'Local'
  }
}
resource retention 'Microsoft.Sql/servers/databases/backupShortTermRetentionPolicies@2023-08-01' = {
  parent: database
  name: 'default'
  properties: { retentionDays: 7 }
}
resource app 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|8.0'
      appCommandLine: 'dotnet NhomBar.Api.dll'
      alwaysOn: !free
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      ftpsState: 'Disabled'
    }
  }
}
resource settings 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: app
  name: 'appsettings'
  properties: {
    ASPNETCORE_ENVIRONMENT: 'Production'
    ASPNETCORE_FORWARDEDHEADERS_ENABLED: 'true'
    ConnectionStrings__SqlServer: 'Server=tcp:${sql.properties.fullyQualifiedDomainName},1433;Database=${dbName};User ID=nhombar_app;Password=${sqlAppPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=20'
    Jwt__Key: jwtKey
    Jwt__Issuer: 'NhomBar'
    Jwt__Audience: 'NhomBar.Mobile'
    AllowedHosts: app.properties.defaultHostName
    Deployment__PublicUrl: 'https://${app.properties.defaultHostName}'
    Email__Brevo__ApiKey: brevoApiKey
    Email__Brevo__SenderEmail: senderEmail
    Push__Firebase__ServiceAccountJson: firebaseServiceAccountJson
  }
}
module appSqlAccess './sql-access.bicep' = {
  name: 'app-sql-access'
  params: {
    serverName: sql.name
    ipAddresses: filter(split(app.properties.outboundIpAddresses, ','), ip => !empty(ip))
  }
}
resource operatorAccess 'Microsoft.Sql/servers/firewallRules@2023-08-01' = {
  parent: sql
  name: 'TemporaryOperator'
  properties: {
    startIpAddress: operatorIp
    endIpAddress: operatorIp
  }
}
output apiUrl string = 'https://${app.properties.defaultHostName}'
output webAppName string = app.name
output sqlServerName string = sql.name
output sqlHost string = sql.properties.fullyQualifiedDomainName
output databaseName string = database.name
output mode string = hostingMode
