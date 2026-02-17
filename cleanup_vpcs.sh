#!/usr/bin/env bash
set -euo pipefail
export AWS_PAGER=""

echo "Listing NON-default VPCs..."
VPCS=$(aws ec2 describe-vpcs \
  --query "Vpcs[?IsDefault==\`false\`].VpcId" \
  --output text)

if [[ -z "${VPCS}" ]]; then
  echo "No non-default VPCs found. Nothing to delete."
  exit 0
fi

echo "Non-default VPCs to delete:"
echo "${VPCS}" | tr '\t' '\n'
echo

for VPC_ID in ${VPCS}; do
  echo "=============================="
  echo "Cleaning VPC: ${VPC_ID}"
  echo "=============================="

  # Terminate instances in VPC
  INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text || true)
  if [[ -n "${INSTANCES}" ]]; then
    echo "Terminating instances: ${INSTANCES}"
    aws ec2 terminate-instances --instance-ids ${INSTANCES} >/dev/null
    aws ec2 wait instance-terminated --instance-ids ${INSTANCES}
  else
    echo "No instances."
  fi

  # Delete ALBs/NLBs in VPC
  LBS=$(aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?VpcId=='${VPC_ID}'].LoadBalancerArn" \
    --output text || true)
  if [[ -n "${LBS}" ]]; then
    echo "Deleting load balancers..."
    for LB in ${LBS}; do
      aws elbv2 delete-load-balancer --load-balancer-arn "${LB}" >/dev/null
    done
    echo "Waiting a bit for load balancers to disappear..."
    sleep 30
  else
    echo "No load balancers."
  fi

  # Delete VPC endpoints
  ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "VpcEndpoints[].VpcEndpointId" \
    --output text || true)
  if [[ -n "${ENDPOINTS}" ]]; then
    echo "Deleting VPC endpoints: ${ENDPOINTS}"
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids ${ENDPOINTS} >/dev/null
  else
    echo "No VPC endpoints."
  fi

  # Delete NAT gateways (and release EIPs if found)
  NATS=$(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=${VPC_ID}" \
    --query "NatGateways[].NatGatewayId" \
    --output text || true)
  if [[ -n "${NATS}" ]]; then
    echo "Deleting NAT gateways: ${NATS}"
    for NAT in ${NATS}; do
      aws ec2 delete-nat-gateway --nat-gateway-id "${NAT}" >/dev/null || true
    done
    echo "Waiting for NAT gateways to delete (can take a few minutes)..."
    # wait loop
    for i in {1..60}; do
      STILL=$(aws ec2 describe-nat-gateways --nat-gateway-ids ${NATS} \
        --query "NatGateways[?State!='deleted'].NatGatewayId" --output text 2>/dev/null || true)
      [[ -z "${STILL}" ]] && break
      sleep 10
    done
  else
    echo "No NAT gateways."
  fi

  # Detach & delete Internet Gateways
  IGWS=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --query "InternetGateways[].InternetGatewayId" \
    --output text || true)
  if [[ -n "${IGWS}" ]]; then
    echo "Detaching & deleting IGWs: ${IGWS}"
    for IGW in ${IGWS}; do
      aws ec2 detach-internet-gateway --internet-gateway-id "${IGW}" --vpc-id "${VPC_ID}" >/dev/null || true
      aws ec2 delete-internet-gateway --internet-gateway-id "${IGW}" >/dev/null || true
    done
  else
    echo "No IGWs."
  fi

  # Delete non-main route tables
  RTS=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "RouteTables[?Associations[?Main==\`false\`]].RouteTableId" \
    --output text || true)
  if [[ -n "${RTS}" ]]; then
    echo "Deleting non-main route tables: ${RTS}"
    for RT in ${RTS}; do
      # disassociate any associations
      ASSOCS=$(aws ec2 describe-route-tables --route-table-ids "${RT}" \
        --query "RouteTables[].Associations[?Main==\`false\`].RouteTableAssociationId" \
        --output text || true)
      for A in ${ASSOCS}; do
        aws ec2 disassociate-route-table --association-id "${A}" >/dev/null || true
      done
      aws ec2 delete-route-table --route-table-id "${RT}" >/dev/null || true
    done
  else
    echo "No non-main route tables."
  fi

  # Delete subnets
  SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "Subnets[].SubnetId" \
    --output text || true)
  if [[ -n "${SUBNETS}" ]]; then
    echo "Deleting subnets: ${SUBNETS}"
    for SN in ${SUBNETS}; do
      aws ec2 delete-subnet --subnet-id "${SN}" >/dev/null || true
    done
  else
    echo "No subnets."
  fi

  # Delete security groups except default
  SGS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" \
    --output text || true)
  if [[ -n "${SGS}" ]]; then
    echo "Deleting security groups: ${SGS}"
    for SG in ${SGS}; do
      aws ec2 delete-security-group --group-id "${SG}" >/dev/null || true
    done
  else
    echo "No non-default security groups."
  fi

  # Finally delete the VPC
  echo "Deleting VPC: ${VPC_ID}"
  aws ec2 delete-vpc --vpc-id "${VPC_ID}"
  echo "Deleted VPC: ${VPC_ID}"
  echo
done

echo "Done. Remaining VPCs:"
aws ec2 describe-vpcs --query "Vpcs[*].{VpcId:VpcId,IsDefault:IsDefault,Cidr:CidrBlock,Name:Tags[?Key=='Name']|[0].Value}" --output table
