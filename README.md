# Azure VNet Integation Discovery
This PowerShell script loops through all subscriptions and checks for specific PaaS services to see if they are VNet Integrated. The output is a CSV file containing the applicable PaaS resource with the connect VNet, Subnet, Resource Group, and any Service Endpoints that are enabled on the subnet.
