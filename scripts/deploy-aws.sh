#!/bin/bash
set -euo pipefail

region=${AWS_REGION:-us-east-1}
subnet=${AWS_SUBNET_ID:?Set AWS_SUBNET_ID to the public subnet for the EC2 demo}
bucket=${TF_STATE_BUCKET:?Set TF_STATE_BUCKET to the existing Terraform state bucket}
image=$(cat target/published-image.txt)
if [[ ! "$image" =~ ^[a-z0-9_-]+/textbook-library@sha256:[a-f0-9]{64}$ ]]; then
    echo "Expected a published Docker Hub textbook-library image digest." >&2
    exit 1
fi

export AWS_REGION="$region" AWS_DEFAULT_REGION="$region" AWS_PAGER=""
export TF_VAR_region="$region" TF_VAR_subnet_id="$subnet" TF_IN_AUTOMATION=1
plan_file=$(mktemp -d)
trap 'rm -f "$plan_file/deploy.tfplan"; rmdir "$plan_file"' EXIT

terraform -chdir=terraform init -input=false \
    -backend-config="bucket=$bucket" -backend-config="region=$region" \
    -backend-config="key=textbook-library/demo.tfstate"
terraform -chdir=terraform plan -input=false -lock-timeout=2m -out="$plan_file/deploy.tfplan"
terraform -chdir=terraform apply -input=false -lock-timeout=2m "$plan_file/deploy.tfplan"
instance=$(terraform -chdir=terraform output -raw instance_id)

ssm_online() {
    aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$instance" \
        --query 'InstanceInformationList[0].PingStatus' --output text
}

for attempt in {1..60}; do
    ping_status=$(ssm_online)
    if [[ "$ping_status" == Online ]]; then break; fi
    sleep 5
done
if [[ "$ping_status" != Online ]]; then
    echo "Instance $instance did not register with Systems Manager." >&2
    exit 1
fi

parameters=$(jq -cn --arg command "cloud-init status --wait && /usr/local/bin/deploy-textbook-library '$image'" \
    '{commands: [$command], executionTimeout: ["600"]}')
command_id=$(aws ssm send-command --instance-ids "$instance" --document-name AWS-RunShellScript \
    --parameters "$parameters" --timeout-seconds 600 --query 'Command.CommandId' --output text)
echo "Waiting for deployment command $command_id on $instance."

for attempt in {1..132}; do
    status=$(aws ssm list-command-invocations --command-id "$command_id" \
        --instance-id "$instance" --query 'CommandInvocations[0].Status' --output text)
    case "$status" in
        Pending|InProgress|Delayed|Cancelling|None) sleep 5 ;;
        *)
            aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance" \
                --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}'
            [[ "$status" == Success ]]
            exit
            ;;
    esac
done

echo "Timed out waiting for deployment command $command_id." >&2
exit 1
