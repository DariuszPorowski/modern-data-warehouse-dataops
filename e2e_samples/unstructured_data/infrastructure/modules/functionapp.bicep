@description('The environment for the deployment.')
@allowed([
  'dev'
  'stg'
  'prod'
])
param env string
@description('The location of the resource.')
param location string
@description('The name of the FunctionApp.')
param function_app_name string
@description('The name of Team for tagging purposes.')
param TeamName string
@description('The name of the storage account.')
param storage_account_name string
@description('The version of the node runtime.')
param linuxFxVersion string = 'NODE|22'
@description('The name given to the hosting plan.')
param hosting_plan_name string
@description('The site config always on setting.')
param alwaysOn bool = true
@description('The name of the SQL server.')
@secure()
param sql_server_name string
@description('The name of the SQL database.')
@secure()
param sql_db_name string
@description('The app insights.')
param app_insights_name string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storage_account_name
}

resource sqlServer 'Microsoft.Sql/servers@2024-05-01-preview' existing = {
  name: sql_server_name
}

resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' existing = {
  name: hosting_plan_name
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: app_insights_name
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: function_app_name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'functionapp,linux'
  tags: {
    TeamName: TeamName
    Environment: env
  }
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      acrUseManagedIdentityCreds: true
      alwaysOn: alwaysOn
      appSettings: [
        {
          name: 'SQL_DATABASE_NAME'
          value: sql_db_name
        }
        {
          name: 'SQL_SERVER_NAME'
          value: sql_server_name
        }
        {
          name: 'SQL_DATABASE_SYNC'
          value: 'false' // revert to false after function app first deployment, last line of deployment script?
        }
        {
          name: 'BLOB_STORAGE_ACCOUNT_NAME'
          value: storage_account_name
        }
        {
          name: 'BLOB_STORAGE_ACCOUNT_KEY'
          value: storageAccount.listKeys().keys[0].value
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'ENABLE_ORYX_BUILD'
          value: '0'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage_account_name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'AzureWebJobFeatureFlags'
          value: 'EnableWorkerIndexing'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage_account_name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(function_app_name)
        }
      ]
      cors: {
        allowedOrigins: [
          '*' // Allow all origins
        ]
      }
      linuxFxVersion: linuxFxVersion
    }
    // clientAffinityEnabled: false
    // virtualNetworkSubnetId: null
    publicNetworkAccess: 'Enabled'
    httpsOnly: true
  }
}

resource ftpPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: functionApp
  name: 'ftp'
  properties: {
    allow: true
  }
}

resource scmPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: functionApp
  name: 'scm'
  properties: {
    allow: true
  }
}

resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    ) // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource sqlContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(sqlServer.id, 'Contributor')
  scope: sqlServer
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b24988ac-6180-42a0-ab88-20f7382dd24c'
    ) // Contributor
    principalId: functionApp.identity.principalId
  }
}

resource sqlServerContributorAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(sqlServer.id, 'SQL Server Contributor')
  scope: sqlServer
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '6d8ee4ec-f05a-4a1d-8b00-a9b17e38b437'
    ) // SQL Server Contributor
    principalId: functionApp.identity.principalId
  }
}

resource sqlDBContributorAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(sqlServer.id, 'SQL DB Contributor')
  scope: sqlServer
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '9b7fa17d-e63e-47b0-bb0a-15c516ac86ec'
    ) // SQL DB Contributor
    principalId: functionApp.identity.principalId
  }
}
output functionapp_name string = functionApp.name
output functionapp_url string = functionApp.properties.defaultHostName
