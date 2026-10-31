#!/usr/bin/env bash
# EWB VPC Peering lab - phase 2: peering + routes (Student: Prakash Jha)
# Run ONLY after you captured the baseline failure (ping from App-A to 10.20.1.10 with no replies).
set -euo pipefail
export AWS_DEFAULT_REGION="ap-south-1"
source ./lab_ids.env

PCX=$(aws ec2 create-vpc-peering-connection --vpc-id "$VPC_A" --peer-vpc-id "$VPC_B" \
  --tag-specifications "ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=ewb-a-b-peer},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=Prakash Jha}]" \
  --query VpcPeeringConnection.VpcPeeringConnectionId --output text)
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id "$PCX" >/dev/null
aws ec2 wait vpc-peering-connection-exists --vpc-peering-connection-ids "$PCX"
echo "PCX=$PCX" >> lab_ids.env
aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids "$PCX" --query 'VpcPeeringConnections[0].Status.Code' --output text

# Routes on BOTH sides + bastion subnet (needed for ProxyJump to App-B)
aws ec2 create-route --route-table-id "$RT_A_PRIV" --destination-cidr-block 10.20.0.0/16 --vpc-peering-connection-id "$PCX" >/dev/null
aws ec2 create-route --route-table-id "$RT_B_PRIV" --destination-cidr-block 10.10.0.0/16 --vpc-peering-connection-id "$PCX" >/dev/null
aws ec2 create-route --route-table-id "$RT_A_PUB"  --destination-cidr-block 10.20.0.0/16 --vpc-peering-connection-id "$PCX" >/dev/null

echo "=== Route tables ==="
aws ec2 describe-route-tables --route-table-ids "$RT_A_PUB" "$RT_A_PRIV" "$RT_B_PRIV" \
  --query 'RouteTables[].{RT:RouteTableId,Assoc:Associations[].SubnetId,Routes:Routes[].[DestinationCidrBlock,GatewayId,VpcPeeringConnectionId]}' --output json
echo
echo "Peering ACTIVE and routes added. Now run tests 02-05 from workbook p.11."
