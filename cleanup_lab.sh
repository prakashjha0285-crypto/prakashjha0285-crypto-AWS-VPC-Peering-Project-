#!/usr/bin/env bash
# EWB VPC Peering lab - cleanup (Student: Prakash Jha). Save ALL evidence first!
set -uo pipefail
export AWS_DEFAULT_REGION="ap-south-1"
source ./lab_ids.env

aws ec2 terminate-instances --instance-ids "$I_BASTION" "$I_APP_A" "$I_APP_B" >/dev/null
aws ec2 wait instance-terminated --instance-ids "$I_BASTION" "$I_APP_A" "$I_APP_B"

# Peer routes, then the peering connection
for RT in "$RT_A_PRIV:10.20.0.0/16" "$RT_B_PRIV:10.10.0.0/16" "$RT_A_PUB:10.20.0.0/16"; do
  aws ec2 delete-route --route-table-id "${RT%%:*}" --destination-cidr-block "${RT##*:}"
done
[ -n "${PCX:-}" ] && aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id "$PCX"

# Security groups
for SG in "$SG_BASTION" "$SG_APP_A" "$SG_APP_B"; do aws ec2 delete-security-group --group-id "$SG"; done

# Subnets, route tables (explicit associations go away with the subnet/table)
for SUB in "$SUB_A_PUB" "$SUB_A_PRIV" "$SUB_B_PRIV"; do aws ec2 delete-subnet --subnet-id "$SUB"; done
for RT in "$RT_A_PUB" "$RT_A_PRIV" "$RT_B_PRIV"; do aws ec2 delete-route-table --route-table-id "$RT"; done

# IGW, VPCs
aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_A"
aws ec2 delete-internet-gateway --internet-gateway-id "$IGW"
aws ec2 delete-vpc --vpc-id "$VPC_A"
aws ec2 delete-vpc --vpc-id "$VPC_B"

aws ec2 delete-key-pair --key-name ewb-lab
rm -f ewb-lab.pem

echo "=== Verification (all should be empty) ==="
aws ec2 describe-instances --filters Name=tag:Project,Values=EWB-VPC-Peering Name=instance-state-name,Values=pending,running,stopped --query 'Reservations[].Instances[].InstanceId'
aws ec2 describe-volumes --filters Name=tag:Project,Values=EWB-VPC-Peering --query 'Volumes[].VolumeId'
aws ec2 describe-vpcs --filters Name=tag:Project,Values=EWB-VPC-Peering --query 'Vpcs[].VpcId'
aws ec2 describe-addresses --query 'Addresses[].PublicIp'
