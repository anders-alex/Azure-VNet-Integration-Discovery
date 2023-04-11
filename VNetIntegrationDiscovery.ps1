#Creates a collection of subnet connected devices and the resource group they belong to. 
$connectedDevicesCollection = New-Object System.Collections.ArrayList
$subscriptions = Get-AzSubscription

Function Get-SubnetInfo ($subnetName, $vnetName, $subscriptionName)
{
    $subnetInfo = @{}    
    $subnetLookup = $connectedDevicesCollection | Where-Object {$_.SubscriptionName -eq $subscriptionName -and $_.VNetName -eq $vnetName -and $_.SubnetName -eq $subnetName}
    if ($subnetLookup.Count -gt 0)
    {
        $subnetInfo.ServiceEndpoints = $subnetLookup[0].ServiceEndpoints
        $subnetInfo.SubnetAddressSpace = $subnetLookup[0].SubnetAddressSpace
        $subnetInfo.SubnetId = $subnetLookup[0].SubnetId
    }
    else 
    {
        $subnet = (Get-AzVirtualNetwork -Name $vnetName).Subnets | Where-Object Name -eq $subnetName
        $delimiter = ""
        if ($subnet.ServiceEndpoints.count -gt 0)
        {       
            foreach ($serviceEndpointItem in $subnet.ServiceEndpoints)
            {                   
                $subnetInfo.ServiceEndpoints = $subnetInfo.ServiceEndpoints + $delimiter + $serviceEndpointItem.Service
                $delimiter = "; "                                
            }
        }
        $subnetInfo.SubnetAddressSpace = $subnet.AddressPrefix[0]
        $subnetInfo.SubnetId = $subnet.Id
    }
    return $subnetInfo       
}

foreach ($subscriptionItem in $subscriptions)
{
    Select-AzSubscription -Subscription $subscriptionItem.Name
    #Loop through all VNets and get any connected devices.
    $vnets = Get-AzVirtualNetwork
        foreach ($vnetItem in $vnets)
        {
            foreach ($subnetItem in $vnetItem.Subnets)
            {
                $serviceEndpoints = ""
                $delimiter = ""
                if ($subnetItem.ServiceEndpoints.count -gt 0)
                {  
                    foreach ($serviceEndpointItem in $subnetItem.ServiceEndpoints)
                    {                   
                        $serviceEndpoints = $serviceEndpoints + $delimiter + $serviceEndpointItem.Service
                        $delimiter = "; "                                
                    }
                }                               
                foreach ($ipConfigurationItem in $subnetItem.IpConfigurations)
                {
                    $connectedDeviceObject = New-Object System.Object
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value ($ipConfigurationItem.Id.Split("/"))[4]
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $vnetItem.Name
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $subnetItem.Name
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $subnetItem.Id
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetItem.AddressPrefix[0]
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $ipConfigurationItem.Id
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $serviceEndpoints
                    $connectedDevicesCollection.Add($connectedDeviceObject)       
                }
            }
        }
    #Get any subnet connected Application Gateways.
    $appGateways = Get-AzApplicationGateway
    if ($appGateways.Count -gt 0) 
    {
        $appGatewayIpConfig = $appGateways | Select-Object -ExpandProperty GatewayIpConfigurationsText | ConvertFrom-Json
        foreach ($ipConfigItem in $appGatewayIpConfig)
        {
            $vnet = Get-AzVirtualNetwork | Where-Object Name -eq ($ipConfigItem.subnet.Id.Split("/"))[8]
            $subnet = $vnet.Subnets | Where-Object Name -eq ($ipConfigItem.subnet.Id.Split("/"))[10]
            $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName $ipConfigItem.subnet.Id.Split("/")[8] -subnetName $ipConfigItem.subnet.Id.Split("/")[10])
            $connectedDeviceObject = New-Object System.Object
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value $ipConfigItem.subnet.Id.Split("/")[4]
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $ipConfigItem.subnet.Id.Split("/")[8]
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $ipConfigItem.subnet.Id.Split("/")[10]
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $ipConfigItem.subnet.Id
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $ipConfigItem.Id
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
            $connectedDevicesCollection.Add($connectedDeviceObject)       
        }
    }
    #Get any subnet connected non-Isolated App Service Plans.
    $appServicePlans = (Invoke-AzRestMethod -ResourceProviderName "Microsoft.Web" -ResourceType "serverfarms" -ApiVersion "2019-08-01" -Method "GET").Content | ConvertFrom-Json
    $appServicePlans = $appServicePlans.value | Select-Object id -ExpandProperty properties | Where-Object hostingEnvironment -eq $null
    if ($appServicePlans.Count -gt 0)
    {
        foreach ($appServicePlanItem in $appServicePlans) 
        {
            $vnetConnection = (Invoke-AzRestMethod -ResourceProviderName "Microsoft.Web" -ResourceGroupName $appServicePlanItem.ResourceGroup -ResourceType "serverfarms" `
            -Name ($appServicePlanItem.Name + "/virtualNetworkConnections") -ApiVersion "2019-08-01" -Method "GET").Content | ConvertFrom-Json
            if ($vnetConnection.Count -gt 0)
            {
                $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName ($vnetConnection | Select-Object -ExpandProperty properties).vnetResourceId.Split("/")[8]`
                 -subnetName ($vnetConnection | Select-Object -ExpandProperty properties).vnetResourceId.Split("/")[10])
                $connectedDeviceObject = New-Object System.Object
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value $appServicePlanItem.ResourceGroup
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value ($vnetConnection | Select-Object -ExpandProperty properties).vnetResourceId.Split("/")[8]
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value ($vnetConnection | Select-Object -ExpandProperty properties).vnetResourceId.Split("/")[10]
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $subnetInfo.SubnetId
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $appServicePlanItem.Id
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
                $connectedDevicesCollection.Add($connectedDeviceObject)       
            }

        }
    }
    #Get any subnet connected ACIs.
    $acis = Get-AzContainerGroup
    if ($acis.Count -gt 0) 
    {
        foreach ($aciItem in $acis) 
        {
            $aci = (Invoke-AzRestMethod -ResourceProviderName "Microsoft.ContainerInstance" -ResourceGroupName $aciItem.ResourceGroupName -ResourceType "containerGroups" `
            -Name $aciItem.Name -ApiVersion "2019-12-01" -Method "GET").Content | ConvertFrom-Json
            if ($aci.properties.ipAddress.type -eq "Private")
            {
                $vnetConnection = (Invoke-AzRestMethod -ResourceProviderName "Microsoft.Network" -ResourceGroupName ($aci.properties.networkProfile).id.Split("/")[4] -ResourceType "networkProfiles" `
                -Name ($aci.properties.networkProfile).id.Split("/")[8] -ApiVersion "2019-12-01" -Method "GET").Content | ConvertFrom-Json
                $subnet = ($vnetConnection.properties.containerNetworkInterfaceConfigurations[0].properties.ipConfigurations[0].properties.subnet.id).Split("/")[10]
                $vnet = ($vnetConnection.properties.containerNetworkInterfaceConfigurations[0].properties.ipConfigurations[0].properties.subnet.id).Split("/")[8]
                $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName $vnet -subnetName $subnet)
                $connectedDeviceObject = New-Object System.Object
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value $aciItem.ResourceGroupName
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $vnet
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $subnet
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $vnetConnection.properties.containerNetworkInterfaceConfigurations[0].properties.ipConfigurations[0].properties.subnet.id
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $aci.id
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
                $connectedDevicesCollection.Add($connectedDeviceObject)       
            }
            

        }
    }
    #Get any subnet connected App Service Envitonments.
    $ases = Get-AzResource -ResourceType Microsoft.Web/hostingEnvironments
    if ($ases.Count -gt 0)
    {
        foreach ($aseItem in $ases) 
        {
            $ase = Get-AzResource -Name $aseItem.Name -ResourceType Microsoft.Web/hostingEnvironments | Get-AzResource -ExpandProperties
            $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName $ase.Properties.vnetName -subnetName $ase.Properties.vnetSubnetName)
            $connectedDeviceObject = New-Object System.Object
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value $aseItem.ResourceGroupName
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $ase.Properties.vnetName
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $ase.Properties.vnetSubnetName
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $subnetInfo.SubnetId
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $ase.Id
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
            $connectedDevicesCollection.Add($connectedDeviceObject)       
        }
    }
    #Get any subnet connected SQL Managed Instances.
    $sqlMIs = Get-AzSqlInstance
    if ($sqlMIs.Count -gt 0)
    {
        foreach ($sqlMIItem in $sqlMIs) 
        {
            $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName $sqlMIItem.SubnetId.split("/")[8] -subnetName $sqlMIItem.SubnetId.split("/")[10])
            $connectedDeviceObject = New-Object System.Object
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value $sqlMIItem.ResourceGroupName
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $sqlMIItem.SubnetId.split("/")[8]
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $sqlMIItem.SubnetId.split("/")[10]
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $sqlMIItem.SubnetId
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $sqlMIItem.id
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
            $connectedDevicesCollection.Add($connectedDeviceObject)       
        }
    }
    #Get any subnet connected Batch Accounts.
    $batchAccounts = Get-AzBatchAccount
    if ($batchAccounts.Count -0)
    {
        foreach ($batchAccountItem in $batchAccounts) 
        {
            $pools = Get-AzBatchPool -BatchContext $batchAccountItem
            foreach ($poolItem in $pools) {
                $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName $poolItem.NetworkConfiguration.SubnetId.Split("/")[8] -subnetName SubnetName $poolItem.NetworkConfiguration.SubnetId.Split("/")[10])
                $connectedDeviceObject = New-Object System.Object
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value $batchAccountItem.ResourceGroupName
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $poolItem.NetworkConfiguration.SubnetId.Split("/")[8]
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $poolItem.NetworkConfiguration.SubnetId.Split("/")[10]
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $poolItem.NetworkConfiguration.SubnetId
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $poolItem.id
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
                $connectedDevicesCollection.Add($connectedDeviceObject)      
            }
            
        }
    }
    #Get any subnet connected Integration Service Accounts.
    $ises = ((Invoke-AzRestMethod -ResourceProviderName "Microsoft.Logic" -ResourceType "integrationServiceEnvironments" -ApiVersion "2019-05-01" -Method "GET").Content) | ConvertFrom-Json
    
    if ($ises.value.Count -gt 0)
    {
        foreach ($iseItem in $ises.value)
        {
            $subnets = $iseItem.properties.networkConfiguration.subnets
            foreach ($subnetItem in $subnets)
            {
                $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName $subnetItem.name.split("/")[0] -subnetName $subnetItem.name.split("/")[1])
                $connectedDeviceObject = New-Object System.Object
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value ($iseItem.id).Split("/")[4]
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $subnetItem.name.split("/")[0]
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $subnetItem.name.split("/")[1]
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $subnetInfo.SubnetId
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $iseItem.id
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
                $connectedDevicesCollection.Add($connectedDeviceObject)      
            }
        }
    }
    #Get any subnet connected Databricks workspaces.
    $databricks = Get-AzDatabricksWorkspace
    if ($databricks.count -gt 0)
    {
        foreach ($databrickItem in $databricks) 
        {
            #Check if workspace is VNet injected or not.
            if ($null -ne $databrickItem.CustomVirtualNetworkIdValue)
            {
                #Add private subnet.
                $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName $databrickItem.CustomVirtualNetworkIdValue.Split("/")[8] -subnetName $databrickItem.CustomPrivateSubnetNameValue)
                $connectedDeviceObject = New-Object System.Object
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value ($databrickItem.Id).Split("/")[4]
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $databrickItem.CustomVirtualNetworkIdValue.Split("/")[8]
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $databrickItem.CustomPrivateSubnetNameValue
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $subnetInfo.SubnetId
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $databrickItem.Id
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
                $connectedDevicesCollection.Add($connectedDeviceObject)
                #Add public subnet.
                $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName ($databrickItem.CustomVirtualNetworkIdValue).Split("/")[8] -subnetName $databrickItem.CustomPublicSubnetNameValue)
                $connectedDeviceObject = New-Object System.Object
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value ($databrickItem.Id).Split("/")[4]
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value ($databrickItem.CustomVirtualNetworkIdValue).Split("/")[8]
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $databrickItem.CustomPublicSubnetNameValue
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $subnetInfo.SubnetId
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $databrickItem.Id
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
                $connectedDevicesCollection.Add($connectedDeviceObject)
            }       
        }
    }
    #Get any subnet connected AKS instances.
    $aks = Get-AzAksCluster
    if ($aks.count -gt 0)
    {
        foreach ($aksItem in $aks) 
        {
            $nodePools = Get-AzAksNodePool -ResourceGroupName ($aksItem.Id).Split("/")[4] -ClusterName $aksItem.Name
            foreach($nodePoolItem in $nodePools)
            {
                if ($null -ne $nodePoolItem.VnetSubnetID) 
                {
                    $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName $nodePoolItem.VnetSubnetID.Split("/")[8] -subnetName $nodePoolItem.VnetSubnetID.Split("/")[10])
                    $connectedDeviceObject = New-Object System.Object
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value $aksItem.NodeResourceGroup
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $nodePoolItem.VnetSubnetID.Split("/")[8]
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $nodePoolItem.VnetSubnetID.Split("/")[10]
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $nodePoolItem.VnetSubnetID
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $nodePoolItem.id
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
                    $connectedDevicesCollection.Add($connectedDeviceObject)
                }
            }

        }
    }
    #Get any subnet connected Redis instances.
    $redis = Get-AzRedisCache | Where-Object Sku -eq "Premium"
    if ($redis.count -gt 0) 
    {
        foreach ($redisItem in $redis) 
        {
            $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName $redisItem.SubnetID.Split("/")[8] -subnetName $redisItem.SubnetID.Split("/")[10])
            $connectedDeviceObject = New-Object System.Object
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value $redisItem.ResourceGroupName
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $redisItem.SubnetID.Split("/")[8]
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $redisItem.SubnetID.Split("/")[10]
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $redisItem.SubnetID
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $redisItem.Id
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
            $connectedDevicesCollection.Add($connectedDeviceObject)  
        }
    }
    #Get any subnet connected AML Service instances.
    $aml = (Invoke-AzRestMethod -ResourceProviderName "Microsoft.MachineLearningServices" -ResourceType "workspaces" -SubscriptionId $subscriptionItem.SubscriptionId  -ApiVersion "2019-05-01" -Method "GET").Content | ConvertFrom-Json
    if ($aml.value.Count -gt 0)
    {
        foreach ($amlItem in $aml)
        {
            $rgName = $amlItem.value.Id.Split("/")[4]
            $resourceType = "workspaces/" + $amlItem.value.name + "/computes"
            $amlCompute = (Invoke-AzRestMethod -ResourceProviderName "Microsoft.MachineLearningServices" -ResourceType $resourceType -SubscriptionId $subscriptionItem.SubscriptionId -ResourceGroupName $rgName -ApiVersion "2019-05-01" -Method "GET").Content | ConvertFrom-Json
            foreach ($amlComputeItem in $amlCompute.value)
            {
                if ($amlComputeItem.properties.computeType -eq "AKS" -or $amlComputeItem.properties.computeType -eq "ComputeInstance" -or $amlComputeItem.properties.computeType -eq "AMLCompute")
                {
                    if ($amlComputeItem.properties.computeType -eq "AKS")
                    {
                        $subnetId = $amlComputeItem.properties.properties.aksNetworkingConfiguration.subnetId
                    }
                    else 
                    {
                        $subnetId = $amlComputeItem.properties.properties.subnet.id
                    }
                    if ($null -ne $subnetId)
                    {
                        $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName $subnetId.Split("/")[8] -subnetName $subnetId.Split("/")[10])
                        $connectedDeviceObject = New-Object System.Object
                        $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
                        $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value $amlComputeItem.id.Split("/")[4]
                        $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $subnetId.Split("/")[8]
                        $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $subnetId.Split("/")[10]
                        $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $subnetId
                        $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
                        $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $amlComputeItem.id
                        $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
                        $connectedDevicesCollection.Add($connectedDeviceObject) 
                    }
                }
            }
        }
    }
    #Get any subnet connected API Management instances.
    $apim = Get-AzApiManagement
    if ($apim.Count -gt 0) 
    {
        foreach ($apimItem in $apim) 
        {
            $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName $apimItem.VirtualNetwork.SubnetResourceId.Split("/")[8] -subnetName $apimItem.VirtualNetwork.SubnetResourceId.Split("/")[10])
            $connectedDeviceObject = New-Object System.Object
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value $apimItem.ResourceGroupName
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $apimItem.VirtualNetwork.SubnetResourceId.Split("/")[8]
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $apimItem.VirtualNetwork.SubnetResourceId.Split("/")[10]
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $apimItem.VirtualNetwork.SubnetResourceId
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $apimItem.Id
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
            $connectedDevicesCollection.Add($connectedDeviceObject)    
        }
    }
    #Get any subnet connected HD Insight clusters.
    $hdi = Get-AzHDInsightCluster | Where-Object SubnetName -ne $null
    if ($hdi.Count -gt 0)
    {
        foreach ($hdiItem in $hdi) 
        {           
            $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName $hdiItem.VirtualNetworkId.Split("/")[8] -subnetName $hdiItem.SubnetName)
            $connectedDeviceObject = New-Object System.Object
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value $hdiItem.ResourceGroup
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $hdiItem.VirtualNetworkId.Split("/")[8]
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $hdiItem.SubnetName
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $subnetInfo.SubnetId
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $hdiItem.Id
            $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
            $connectedDevicesCollection.Add($connectedDeviceObject)   
        }
    }
    #Get any NAT Gateways.
    $ngw = (Invoke-AzRestMethod -ResourceProviderName "Microsoft.Network" -ResourceType "natGateways" -SubscriptionId $subscriptionItem.SubscriptionId  -ApiVersion "2020-07-01" -Method "GET").Content | ConvertFrom-Json
    if ($ngw.value.Count -gt 0)
    {
        foreach ($ngwItem in $ngw.value) {
            $subnets = $ngwItem.properties.subnets
            foreach ($subnetItem in $subnets) 
            {
                $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName $subnetItem.Id.Split("/")[8] -subnetName $subnetItem.Id.Split("/")[10])
                $connectedDeviceObject = New-Object System.Object
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value $ngwItem.id.Split("/")[4]
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $subnetItem.Id.Split("/")[8]
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $subnetItem.Id.Split("/")[10]
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $subnetItem.Id
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $ngwItem.id
                $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
                $connectedDevicesCollection.Add($connectedDeviceObject)
            }
        }
    }
    #Get any subnet connected NetApp Accounts/Volumes.
    $netAppAccounts = (Invoke-AzRestMethod -ResourceProviderName "Microsoft.NetApp" -ResourceType "netAppAccounts" -SubscriptionId $subscriptionItem.SubscriptionId -ApiVersion "2020-09-01" -Method "GET").Content | ConvertFrom-Json
    if ($netAppAccounts.value.Count -gt 0) 
    {
        foreach($netAppAccountItem in $netAppAccounts.value)
        {
            $resourceType = "netAppAccounts/" + $netAppAccountItem.name + "/capacitypools"
            $rgName = $netAppAccountItem.id.Split("/")[4]
            $netAppPools = (Invoke-AzRestMethod -ResourceProviderName "Microsoft.NetApp" -ResourceType "netAppAccounts/wus-netapp/capacitypools" -SubscriptionId $subscriptionItem.SubscriptionId`
                            -ResourceGroupName $rgName -ApiVersion "2020-09-01" -Method "GET").Content | ConvertFrom-Json
            foreach ($netAppPoolItem in $netAppPools.value) 
            {
                $resourceType = "netAppAccounts/" + $netAppAccountItem.name + "/capacitypools/" + $netAppPoolItem.name.Split("/")[1] + "/volumes"
                $netAppVolumes = (Invoke-AzRestMethod -ResourceProviderName "Microsoft.NetApp" -ResourceType $resourceType -SubscriptionId $subscriptionItem.SubscriptionId`
                                 -ResourceGroupName $rgName -ApiVersion "2020-09-01" -Method "GET").Content | ConvertFrom-Json
                foreach ($netAppVolumeItem in $netAppVolumes.value)
                {
                    $subnetInfo = (Get-SubnetInfo -subscriptionName $subscriptionItem.Name -vnetName $netAppVolumeItem.properties.subnetId.Split("/")[8] -subnetName $netAppVolumeItem.properties.subnetId.Split("/")[10])
                    $connectedDeviceObject = New-Object System.Object
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubscriptionName -Value $subscriptionItem.Name
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedRGName -Value $netAppVolumeItem.id.Split("/")[4] 
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name VNetName -Value $netAppVolumeItem.properties.subnetId.Split("/")[8]
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetName -Value $netAppVolumeItem.properties.subnetId.Split("/")[10]
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetId -Value $netAppVolumeItem.properties.subnetId
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name SubnetAddressSpace -Value $subnetInfo.SubnetAddressSpace
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ConnectedResourceId -Value $netAppVolumeItem.id
                    $connectedDeviceObject | Add-Member -MemberType NoteProperty -Name ServiceEndpoints -Value $subnetInfo.ServiceEndpoints
                    $connectedDevicesCollection.Add($connectedDeviceObject)
                }                                 
            }
        }
    }
}
$connectedDevicesCollection | Export-Csv -Path export.csv -NoTypeInformation
