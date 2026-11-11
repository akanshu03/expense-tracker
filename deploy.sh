#!/usr/bin/env bash
# Blue/green deploy to ECS via CodeDeploy. Exits non-zero if the deployment
# fails; CodeDeploy has already rolled traffic back to the previous (blue) task set.
set -euo pipefail

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
: "${ENV:?--env required}" "${IMAGE:?--image required}"

NAME="expense-tracker-${ENV}"
CLUSTER="$NAME"
SERVICE="$NAME"
CD_APP="$NAME"
CD_GROUP="$NAME"

echo ">> Current task definition for ${SERVICE}"
CURRENT_TD_ARN=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].taskDefinition' --output text)

echo ">> Registering new revision with image ${IMAGE}"
aws ecs describe-task-definition --task-definition "$CURRENT_TD_ARN" \
  --query 'taskDefinition' > /tmp/td.json

jq --arg IMAGE "$IMAGE" --arg VER "${IMAGE##*:}" '
  del(.taskDefinitionArn,.revision,.status,.requiresAttributes,.compatibilities,.registeredAt,.registeredBy)
  | .containerDefinitions[0].image = $IMAGE
  | .containerDefinitions[0].environment |= (map(select(.name!="APP_VERSION")) + [{name:"APP_VERSION",value:$VER}])
' /tmp/td.json > /tmp/td-new.json

NEW_TD_ARN=$(aws ecs register-task-definition --cli-input-json file:///tmp/td-new.json \
  --query 'taskDefinition.taskDefinitionArn' --output text)
echo ">> New task definition: ${NEW_TD_ARN}"

CONTAINER_NAME=$(jq -r '.containerDefinitions[0].name' /tmp/td-new.json)
CONTAINER_PORT=$(jq -r '.containerDefinitions[0].portMappings[0].containerPort' /tmp/td-new.json)

APPSPEC=$(jq -nc --arg td "$NEW_TD_ARN" --arg c "$CONTAINER_NAME" --argjson p "$CONTAINER_PORT" '
  {version:0.0, Resources:[{TargetService:{Type:"AWS::ECS::Service",
   Properties:{TaskDefinition:$td, LoadBalancerInfo:{ContainerName:$c, ContainerPort:$p}}}}]}')

DEPLOYMENT_ID=$(aws deploy create-deployment \
  --application-name "$CD_APP" --deployment-group-name "$CD_GROUP" \
  --revision "{\"revisionType\":\"AppSpecContent\",\"appSpecContent\":{\"content\":$(jq -Rs . <<<"$APPSPEC")}}" \
  --description "image ${IMAGE##*:}" \
  --query deploymentId --output text)
echo ">> CodeDeploy deployment: ${DEPLOYMENT_ID}"

if aws deploy wait deployment-successful --deployment-id "$DEPLOYMENT_ID"; then
  echo ">> Deployment ${DEPLOYMENT_ID} succeeded"
else
  echo "!! Deployment ${DEPLOYMENT_ID} FAILED - CodeDeploy rolled back to the previous version" >&2
  aws deploy get-deployment --deployment-id "$DEPLOYMENT_ID" \
    --query 'deploymentInfo.{status:status,rollback:rollbackInfo,error:errorInformation}' >&2
  exit 1
fi
