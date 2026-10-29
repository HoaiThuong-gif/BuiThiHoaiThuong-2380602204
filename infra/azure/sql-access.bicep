param serverName string
param ipAddresses array
resource sql 'Microsoft.Sql/servers@2023-08-01' existing = { name: serverName }
resource rules 'Microsoft.Sql/servers/firewallRules@2023-08-01' = [for (ip, i) in ipAddresses: {
  parent: sql
  name: 'NhomBarApp-${i}'
  properties: {
    startIpAddress: ip
    endIpAddress: ip
  }
}]
