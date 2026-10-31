#!/usr/bin/env bash
# EWB VPC Peering lab - build script (Student: Prakash Jha)
# Run in AWS CloudShell or a terminal with the AWS CLI configured for your LAB account.
# Creates everything in the workbook, then prints an inventory of real IDs.
set -euo pipefail

REGION="ap-south-1"
export AWS_DEFAULT_REGION="$REGION"
STUDENT="Prakash Jha"
TAGS_SPEC() { echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT}]"; }

MYIP="$(curl -s https://checkip.amazonaws.com)/32"
echo "Your public IP for bastion SSH rule: $MYIP"

AZ="$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text)"

# ---------- VPC A ----------
VPC_A=$(aws ec2 create-vpc --cidr-block 10.10.0.0/16 --tag-specifications "$(TAGS_SPEC vpc ewb-vpc-a)" --query Vpc.VpcId --output text)
SUB_A_PUB=$(aws ec2 create-subnet --vpc-id "$VPC_A" --cidr-block 10.10.1.0/24 --availability-zone "$AZ" --tag-specifications "$(TAGS_SPEC subnet ewb-a-public)" --query Subnet.SubnetId --output text)
SUB_A_PRIV=$(aws ec2 create-subnet --vpc-id "$VPC_A" --cidr-block 10.10.2.0/24 --availability-zone "$AZ" --tag-specifications "$(TAGS_SPEC subnet ewb-a-private)" --query Subnet.SubnetId --output text)
IGW=$(aws ec2 create-internet-gateway --tag-specifications "$(TAGS_SPEC internet-gateway ewb-igw-a)" --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_A"

RT_A_PUB=$(aws ec2 create-route-table --vpc-id "$VPC_A" --tag-specifications "$(TAGS_SPEC route-table ewb-rt-a-public)" --query RouteTable.RouteTableId --output text)
aws ec2 associate-route-table --route-table-id "$RT_A_PUB" --subnet-id "$SUB_A_PUB" >/dev/null
aws ec2 create-route --route-table-id "$RT_A_PUB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" >/dev/null

RT_A_PRIV=$(aws ec2 create-route-table --vpc-id "$VPC_A" --tag-specifications "$(TAGS_SPEC route-table ewb-rt-a-private)" --query RouteTable.RouteTableId --output text)
aws ec2 associate-route-table --route-table-id "$RT_A_PRIV" --subnet-id "$SUB_A_PRIV" >/dev/null

# ---------- VPC B ----------
VPC_B=$(aws ec2 create-vpc --cidr-block 10.20.0.0/16 --tag-specifications "$(TAGS_SPEC vpc ewb-vpc-b)" --query Vpc.VpcId --output text)
SUB_B_PRIV=$(aws ec2 create-subnet --vpc-id "$VPC_B" --cidr-block 10.20.1.0/24 --availability-zone "$AZ" --tag-specifications "$(TAGS_SPEC subnet ewb-b-private)" --query Subnet.SubnetId --output text)
RT_B_PRIV=$(aws ec2 create-route-table --vpc-id "$VPC_B" --tag-specifications "$(TAGS_SPEC route-table ewb-rt-b-private)" --query RouteTable.RouteTableId --output text)
aws ec2 associate-route-table --route-table-id "$RT_B_PRIV" --subnet-id "$SUB_B_PRIV" >/dev/null

# ---------- Security groups ----------
SG_BASTION=$(aws ec2 create-security-group --group-name ewb-sg-bastion --description "EWB bastion" --vpc-id "$VPC_A" --tag-specifications "$(TAGS_SPEC security-group ewb-sg-bastion)" --query GroupId --output text)
SG_APP_A=$(aws ec2 create-security-group --group-name ewb-sg-app-a --description "EWB App-A" --vpc-id "$VPC_A" --tag-specifications "$(TAGS_SPEC security-group ewb-sg-app-a)" --query GroupId --output text)
SG_APP_B=$(aws ec2 create-security-group --group-name ewb-sg-app-b --description "EWB App-B" --vpc-id "$VPC_B" --tag-specifications "$(TAGS_SPEC security-group ewb-sg-app-b)" --query GroupId --output text)

aws ec2 authorize-security-group-ingress --group-id "$SG_BASTION" --protocol tcp --port 22 --cidr "$MYIP" >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG_APP_A" --protocol tcp --port 22 --cidr 10.10.1.10/32 >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG_APP_A" --protocol icmp --port 8 --cidr 10.20.1.10/32 >/dev/null   # echo request (type 8)
aws ec2 authorize-security-group-ingress --group-id "$SG_APP_B" --protocol tcp --port 22 --cidr 10.10.1.10/32 >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG_APP_B" --protocol icmp --port 8 --cidr 10.10.2.10/32 >/dev/null

# ---------- Key pair (private key stays on THIS machine; download it to your laptop) ----------
aws ec2 create-key-pair --key-name ewb-lab --key-type rsa --tag-specifications "$(TAGS_SPEC key-pair ewb-lab)" --query KeyMaterial --output text > ewb-lab.pem
chmod 400 ewb-lab.pem
echo "Key saved as ./ewb-lab.pem - download it to ~/.ssh/ewb-lab.pem on your laptop, never copy it onto an instance."

# ---------- Instances ----------
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
launch() { # name subnet sg ip public(yes/no)
  local pubflag="--no-associate-public-ip-address"; [ "$5" = yes ] && pubflag="--associate-public-ip-address"
  aws ec2 run-instances --image-id "$AMI" --instance-type t3.micro --key-name ewb-lab \
    --subnet-id "$2" --security-group-ids "$3" --private-ip-address "$4" $pubflag \
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=8,DeleteOnTermination=true}' \
    --tag-specifications "$(TAGS_SPEC instance "$1")" --query 'Instances[0].InstanceId' --output text
}
I_BASTION=$(launch ewb-bastion "$SUB_A_PUB"  "$SG_BASTION" 10.10.1.10 yes)
I_APP_A=$(launch ewb-app-a   "$SUB_A_PRIV" "$SG_APP_A"   10.10.2.10 no)
I_APP_B=$(launch ewb-app-b   "$SUB_B_PRIV" "$SG_APP_B"   10.20.1.10 no)
aws ec2 wait instance-running --instance-ids "$I_BASTION" "$I_APP_A" "$I_APP_B"
BASTION_IP=$(aws ec2 describe-instances --instance-ids "$I_BASTION" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

cat > lab_ids.env <<EOF
VPC_A=$VPC_A
VPC_B=$VPC_B
SUB_A_PUB=$SUB_A_PUB
SUB_A_PRIV=$SUB_A_PRIV
SUB_B_PRIV=$SUB_B_PRIV
IGW=$IGW
RT_A_PUB=$RT_A_PUB
RT_A_PRIV=$RT_A_PRIV
RT_B_PRIV=$RT_B_PRIV
SG_BASTION=$SG_BASTION
SG_APP_A=$SG_APP_A
SG_APP_B=$SG_APP_B
I_BASTION=$I_BASTION
I_APP_A=$I_APP_A
I_APP_B=$I_APP_B
BASTION_IP=$BASTION_IP
EOF

echo
echo "=== PHASE 1 DONE: network + instances built, NO peering yet ==="
echo "Now do the BASELINE test (workbook p.8): ssh ewb-app-a, then: ping -c 4 10.20.1.10  (expect no replies). Save it!"
echo "Then run ./peer_lab.sh"
echo "Bastion public IP: $BASTION_IP   (put it in ~/.ssh/config as HostName)"
