param location string = resourceGroup().location
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-entitlement-sod-audit'
  location: location
}
