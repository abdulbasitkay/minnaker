#!/bin/bash
set -x
set -e

# TODO: Move this all to templates

BASE_DIR=/etc/spinnaker
PROJECT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../" >/dev/null 2>&1 && pwd )

PVC="minio-pvc"
# We are using the bucket kayenta instead of the spinnaker bucket, because Kayenta crashes if it's using the same bucket (haven't dug into this yet)
KAYENTA_BUCKET="kayenta"
FRONT50_BUCKET="spinnaker"
APPLICATION_NAME="democanary"

cp -rv ${PROJECT_DIR}/templates/demo ${BASE_DIR}/templates

# TODO: Detect existence
if [[ ! -f ${BASE_DIR}/.hal/.secret/demo_canary_pipeline_uuid ]]; then
  echo "Generating Canary Config UUID (${BASE_DIR}/.hal/.secret/demo_canary_pipeline_uuid)"
  uuidgen > ${BASE_DIR}/.hal/.secret/demo_canary_pipeline_uuid
else
  echo "Canary Config UUID already exists (${BASE_DIR}/.hal/.secret/demo_canary_pipeline_uuid)"
fi

if [[ ! -f ${BASE_DIR}/.hal/.secret/demo_canary_config_uuid ]]; then
  echo "Generating Canary Config UUID (${BASE_DIR}/.hal/.secret/demo_canary_config_uuid)"
  uuidgen > ${BASE_DIR}/.hal/.secret/demo_canary_config_uuid
else
  echo "Canary Config UUID already exists (${BASE_DIR}/.hal/.secret/demo_canary_config_uuid)"
fi

PIPELINE_UUID=$(cat ${BASE_DIR}/.hal/.secret/demo_canary_pipeline_uuid)
CANARY_CONFIG_UUID=$(cat ${BASE_DIR}/.hal/.secret/demo_canary_config_uuid)

MINIO_PATH=$(kubectl -n spinnaker get pv -ojsonpath="{.items[?(@.spec.claimRef.name==\"${PVC}\")].spec.hostPath.path}")

FRONT50_PATH=${MINIO_PATH}/${FRONT50_BUCKET}/front50
KAYENTA_PATH=${MINIO_PATH}/${KAYENTA_BUCKET}/kayenta
mkdir -p ${KAYENTA_PATH}/canary_config

mkdir -p ${FRONT50_PATH}/{applications,pipelines}
mkdir -p ${FRONT50_PATH}/applications/${APPLICATION_NAME}
mkdir -p ${FRONT50_PATH}/pipelines/${PIPELINE_UUID}

TIMESTAMP=$(date +%s000)
ISO_TIMESTAMP=$(date +"%Y-%m-%dT%T.000Z")

sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
  ${BASE_DIR}/templates/demo/democanary/applications/democanary/application-metadata.json.tmpl \
  > ${FRONT50_PATH}/applications/${APPLICATION_NAME}/application-metadata.json

# tee ${FRONT50_PATH}/applications/${APPLICATION_NAME}/application-metadata.json <<-EOF
# {
#   "name": "DEMOCANARY",
#   "description": null,
#   "email": "demo@armory.io",
#   "updateTs": "__TIMESTAMP__",
#   "createTs": "__TIMESTAMP__",
#   "lastModifiedBy": "demo",
#   "cloudProviders": "kubernetes",
#   "trafficGuards": [],
#   "instancePort": 80,
#   "user": "demo",
#   "dataSources": {
#     "disabled": [],
#     "enabled": [
#       "canaryConfigs"
#     ]
#   }
# }
# EOF

sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
  ${BASE_DIR}/templates/demo/democanary/applications/democanary/application-permissions.json.tmpl \
  > ${FRONT50_PATH}/applications/${APPLICATION_NAME}/application-permissions.json

# tee ${FRONT50_PATH}/applications/${APPLICATION_NAME}/application-permissions.json <<-EOF
# {
#   "name": "democanary",
#   "lastModified": $(date +%s000),
#   "lastModifiedBy": "demo",
#   "permissions": {}
# }
# EOF

sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
  ${BASE_DIR}/templates/demo/democanary/applications/last-modified.json.tmpl \
  > ${FRONT50_PATH}/applications/last-modified.json

# tee ${FRONT50_PATH}/applications/last-modified.json <<-EOF
# {"lastModified":$(date +%s000)}
# EOF

# tee /tmp/democanary-pipeline.json <<-'EOF'
# {
#   "application": "democanary",
#   "name": "Canary Demo",
#   "id": "__PIPELINE_UUID__",
#   "updateTs": "__TIMESTAMP__",
#   "index": 0,
#   "expectedArtifacts": [],
#   "keepWaitingPipelines": false,
#   "lastModifiedBy": "demo",
#   "limitConcurrent": true,
#   "parameterConfig": [
#     {
#       "default": "random",
#       "description": "",
#       "hasOptions": true,
#       "label": "",
#       "name": "tag",
#       "options": [
#         {
#           "value": "monday"
#         },
#         {
#           "value": "tuesday"
#         },
#         {
#           "value": "wednesday"
#         },
#         {
#           "value": "thursday"
#         },
#         {
#           "value": "friday"
#         },
#         {
#           "value": "saturday"
#         },
#         {
#           "value": "sunday"
#         },
#         {
#           "value": "random"
#         }
#       ],
#       "pinned": true,
#       "required": true
#     }
#   ],
#   "stages": [
#     {
#       "account": "spinnaker",
#       "app": "democanary",
#       "cloudProvider": "kubernetes",
#       "comments": "The first time this pipeline runs; this stage may fail.  This is fine.",
#       "completeOtherBranchesThenFail": false,
#       "continuePipeline": true,
#       "expectedArtifacts": [],
#       "failPipeline": false,
#       "location": "prod",
#       "manifestName": "deployment hello-world-prod",
#       "mode": "static",
#       "name": "Get Info",
#       "refId": "2",
#       "requisiteStageRefIds": [],
#       "type": "findArtifactsFromResource"
#     },
#     {
#       "comments": "<pre>\nCurrent Image: Get current image from hello-world-prod deployment (if it's valid), otherwise default to 'justinrlee/hello-world:monday'\nCurrent Instances: Get current replica count from hello-world-prod deployment (if it's valid), otherwise default to 4\nNew Image: Build from trigger.\n</pre>",
#       "failOnFailedExpressions": true,
#       "name": "Evaluate Variables",
#       "refId": "3",
#       "requisiteStageRefIds": [
#         "2",
#         "5"
#       ],
#       "type": "evaluateVariables",
#       "variables": [
#         {
#           "key": "current_image",
#           "value": "${#stage(\"Get Info\").status == \"FAILED_CONTINUE\" ? \"justinrlee/hello-world:monday\" : #stage(\"Get Info\").context.artifacts.^[type== \"docker/image\"].reference}"
#         },
#         {
#           "key": "current_instances",
#           "value": "${#stage(\"Get Info\").status == \"FAILED_CONTINUE\" ? 4 : #stage(\"Get Info\").context.manifest.spec.replicas}"
#         },
#         {
#           "key": "new_image",
#           "value": "justinrlee/hello-world:${trigger.parameters.tag == \"random\" ? new String[7]{\"monday\",\"tuesday\",\"wednesday\",\"thursday\",\"friday\",\"saturday\",\"sunday\"}[new java.util.Random().nextInt(7)] : trigger.parameters.tag}"
#         },
#         {
#           "key": "random_day",
#           "value": "${new String[7]{\"monday\",\"tuesday\",\"wednesday\",\"thursday\",\"friday\",\"saturday\",\"sunday\"}[new java.util.Random().nextInt(7)]}"
#         }
#       ]
#     },
#     {
#       "account": "spinnaker",
#       "cloudProvider": "kubernetes",
#       "manifests": [
#         {
#           "apiVersion": "apps/v1",
#           "kind": "Deployment",
#           "metadata": {
#             "annotations": {
#               "strategy.spinnaker.io/max-version-history": "2"
#             },
#             "name": "hello-world-baseline"
#           },
#           "spec": {
#             "replicas": 1,
#             "selector": {
#               "matchLabels": {
#                 "app": "hello-world",
#                 "group": "baseline"
#               }
#             },
#             "template": {
#               "metadata": {
#                 "annotations": {
#                   "prometheus.io/path": "/metrics",
#                   "prometheus.io/port": "8080",
#                   "prometheus.io/scrape": "true"
#                 },
#                 "labels": {
#                   "app": "hello-world",
#                   "group": "baseline"
#                 }
#               },
#               "spec": {
#                 "containers": [
#                   {
#                     "image": "${current_image}",
#                     "imagePullPolicy": "Always",
#                     "name": "hello-world",
#                     "ports": [
#                       {
#                         "containerPort": 8080
#                       }
#                     ]
#                   }
#                 ]
#               }
#             }
#           }
#         }
#       ],
#       "moniker": {
#         "app": "democanary"
#       },
#       "name": "Deploy Baseline",
#       "namespaceOverride": "prod",
#       "refId": "4",
#       "requisiteStageRefIds": [
#         "3"
#       ],
#       "skipExpressionEvaluation": false,
#       "source": "text",
#       "trafficManagement": {
#         "enabled": false,
#         "options": {
#           "enableTraffic": false,
#           "services": []
#         }
#       },
#       "type": "deployManifest"
#     },
#     {
#       "account": "spinnaker",
#       "cloudProvider": "kubernetes",
#       "manifests": [
#         {
#           "apiVersion": "v1",
#           "kind": "Service",
#           "metadata": {
#             "labels": {
#               "app": "hello-world"
#             },
#             "name": "hello-world"
#           },
#           "spec": {
#             "ports": [
#               {
#                 "name": "web",
#                 "port": 8080
#               }
#             ],
#             "selector": {
#               "app": "hello-world"
#             }
#           }
#         },
#         {
#           "apiVersion": "monitoring.coreos.com/v1",
#           "kind": "ServiceMonitor",
#           "metadata": {
#             "name": "hello-world"
#           },
#           "spec": {
#             "endpoints": [
#               {
#                 "port": "web"
#               }
#             ],
#             "namespaceSelector": {
#               "any": true
#             },
#             "podTargetLabels": [
#               "group",
#               "app_version"
#             ],
#             "selector": {
#               "matchLabels": {
#                 "app": "hello-world"
#               }
#             }
#           }
#         }
#       ],
#       "moniker": {
#         "app": "democanary"
#       },
#       "name": "Deploy Service and ServiceMonitor",
#       "namespaceOverride": "prod",
#       "refId": "5",
#       "requisiteStageRefIds": [],
#       "skipExpressionEvaluation": false,
#       "source": "text",
#       "trafficManagement": {
#         "enabled": false,
#         "options": {
#           "enableTraffic": false
#         }
#       },
#       "type": "deployManifest"
#     },
#     {
#       "account": "spinnaker",
#       "cloudProvider": "kubernetes",
#       "manifests": [
#         {
#           "apiVersion": "apps/v1",
#           "kind": "Deployment",
#           "metadata": {
#             "annotations": {
#               "strategy.spinnaker.io/max-version-history": "2"
#             },
#             "name": "hello-world-canary"
#           },
#           "spec": {
#             "replicas": 1,
#             "selector": {
#               "matchLabels": {
#                 "app": "hello-world",
#                 "group": "canary"
#               }
#             },
#             "template": {
#               "metadata": {
#                 "annotations": {
#                   "prometheus.io/path": "/metrics",
#                   "prometheus.io/port": "8080",
#                   "prometheus.io/scrape": "true"
#                 },
#                 "labels": {
#                   "app": "hello-world",
#                   "group": "canary"
#                 }
#               },
#               "spec": {
#                 "containers": [
#                   {
#                     "image": "${new_image}",
#                     "imagePullPolicy": "Always",
#                     "name": "hello-world",
#                     "ports": [
#                       {
#                         "containerPort": 8080
#                       }
#                     ]
#                   }
#                 ]
#               }
#             }
#           }
#         }
#       ],
#       "moniker": {
#         "app": "democanary"
#       },
#       "name": "Deploy Canary",
#       "namespaceOverride": "prod",
#       "refId": "6",
#       "requisiteStageRefIds": [
#         "3"
#       ],
#       "skipExpressionEvaluation": false,
#       "source": "text",
#       "trafficManagement": {
#         "enabled": false,
#         "options": {
#           "enableTraffic": false,
#           "services": []
#         }
#       },
#       "type": "deployManifest"
#     },
#     {
#       "name": "Wait",
#       "refId": "7",
#       "requisiteStageRefIds": [
#         "4",
#         "6"
#       ],
#       "type": "wait",
#       "waitTime": 1
#     },
#     {
#       "name": "Wait",
#       "refId": "8",
#       "requisiteStageRefIds": [
#         "7"
#       ],
#       "type": "wait",
#       "waitTime": 2
#     },
#     {
#       "completeOtherBranchesThenFail": false,
#       "continuePipeline": true,
#       "failPipeline": false,
#       "instructions": "Click \"Continue\" to promote and \"Stop\" to not promote.",
#       "judgmentInputs": [],
#       "name": "Manual Judgment",
#       "notifications": [],
#       "refId": "9",
#       "requisiteStageRefIds": [
#         "8",
#         "13"
#       ],
#       "stageEnabled": {
#         "expression": "${#stage(\"Canary Analysis\").status == \"NOSUCCEEDED\"}",
#         "type": "expression"
#       },
#       "type": "manualJudgment"
#     },
#     {
#       "account": "spinnaker",
#       "app": "democanary",
#       "cloudProvider": "kubernetes",
#       "location": "prod",
#       "manifestName": "deployment hello-world-canary",
#       "mode": "static",
#       "name": "Destroy Canary",
#       "options": {
#         "cascading": true
#       },
#       "refId": "10",
#       "requisiteStageRefIds": [
#         "9"
#       ],
#       "type": "deleteManifest"
#     },
#     {
#       "account": "spinnaker",
#       "app": "democanary",
#       "cloudProvider": "kubernetes",
#       "location": "prod",
#       "manifestName": "deployment hello-world-baseline",
#       "mode": "static",
#       "name": "Destroy Baseline",
#       "options": {
#         "cascading": true
#       },
#       "refId": "11",
#       "requisiteStageRefIds": [
#         "9"
#       ],
#       "type": "deleteManifest"
#     },
#     {
#       "account": "spinnaker",
#       "cloudProvider": "kubernetes",
#       "manifests": [
#         {
#           "apiVersion": "apps/v1",
#           "kind": "Deployment",
#           "metadata": {
#             "annotations": {
#               "strategy.spinnaker.io/max-version-history": "4"
#             },
#             "name": "hello-world-prod"
#           },
#           "spec": {
#             "replicas": "${current_instances.intValue()}",
#             "selector": {
#               "matchLabels": {
#                 "app": "hello-world",
#                 "group": "prod"
#               }
#             },
#             "template": {
#               "metadata": {
#                 "annotations": {
#                   "prometheus.io/path": "/metrics",
#                   "prometheus.io/port": "8080",
#                   "prometheus.io/scrape": "true"
#                 },
#                 "labels": {
#                   "app": "hello-world",
#                   "group": "prod"
#                 }
#               },
#               "spec": {
#                 "containers": [
#                   {
#                     "image": "${new_image}",
#                     "imagePullPolicy": "Always",
#                     "name": "hello-world",
#                     "ports": [
#                       {
#                         "containerPort": 8080
#                       }
#                     ]
#                   }
#                 ]
#               }
#             }
#           }
#         }
#       ],
#       "moniker": {
#         "app": "democanary"
#       },
#       "name": "Promote Prod",
#       "namespaceOverride": "prod",
#       "refId": "12",
#       "requisiteStageRefIds": [
#         "9"
#       ],
#       "skipExpressionEvaluation": false,
#       "source": "text",
#       "stageEnabled": {
#         "expression": "${#stage(\"Manual Judgment\").context.judgmentStatus != \"stop\"}",
#         "type": "expression"
#       },
#       "trafficManagement": {
#         "enabled": false,
#         "options": {
#           "enableTraffic": false,
#           "services": []
#         }
#       },
#       "type": "deployManifest"
#     },
#     {
#       "analysisType": "realTime",
#       "canaryConfig": {
#         "beginCanaryAnalysisAfterMins": "2",
#         "canaryAnalysisIntervalMins": "2",
#         "canaryConfigId": "__CANARY_CONFIG_UUID__",
#         "lifetimeDuration": "PT0H20M",
#         "metricsAccountName": "prometheus",
#         "scopes": [
#           {
#             "controlLocation": "prod",
#             "controlScope": "baseline",
#             "experimentLocation": "prod",
#             "experimentScope": "canary",
#             "extendedScopeParams": {},
#             "scopeName": "default",
#             "step": 5
#           }
#         ],
#         "scoreThresholds": {
#           "marginal": "0",
#           "pass": "70"
#         },
#         "storageAccountName": "minio"
#       },
#       "completeOtherBranchesThenFail": false,
#       "continuePipeline": true,
#       "failPipeline": false,
#       "name": "Canary Analysis",
#       "refId": "13",
#       "requisiteStageRefIds": [
#         "7"
#       ],
#       "type": "kayentaCanary"
#     }
#   ],
#   "triggers": [
#   ]
# }
# EOF

sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
    -e "s|__PIPELINE_UUID__|${PIPELINE_UUID}|g" \
    -e "s|__CANARY_CONFIG_UUID__|${CANARY_CONFIG_UUID}|g" \
    ${BASE_DIR}/templates/demo/democanary/pipelines/PIPELINE_UUID/pipeline-metadata.json.tmpl \
    > ${FRONT50_PATH}/pipelines/${PIPELINE_UUID}/pipeline-metadata.json

sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
    ${BASE_DIR}/templates/demo/democanary/pipelines/last-modified.json.tmpl \
    > ${FRONT50_PATH}/pipelines/last-modified.json

# tee ${FRONT50_PATH}/pipelines/last-modified.json <<-EOF
# {"lastModified":$(date +%s000)}
# EOF

mkdir -p ${KAYENTA_PATH}/{canary_config,canary_archive,metric_pairs,metrics}
mkdir -p ${KAYENTA_PATH}/canary_config/${CANARY_CONFIG_UUID}

# Can't tee directly to file cause of mix of timestamps generated with bash, and filter containing bash 
# (could be done with tons of escaping, but this is easier)
# tee /tmp/canary_config_Latency.json  <<-'EOF'
# {
#   "createdTimestamp": __TIMESTAMP__,
#   "updatedTimestamp": __TIMESTAMP__,
#   "createdTimestampIso": "__ISO_TIMESTAMP__",
#   "updatedTimestampIso": "__ISO_TIMESTAMP__",
#   "name": "Latency",
#   "id": "${CANARY_CONFIG_UUID}",
#   "description": "Latency Canary Config",
#   "configVersion": "1",
#   "applications": [
#     "democanary"
#   ],
#   "judge": {
#     "name": "NetflixACAJudge-v1.0",
#     "judgeConfigurations": {}
#   },
#   "metrics": [
#     {
#       "name": "latency",
#       "query": {
#         "type": "prometheus",
#         "metricName": "custom_dummy_latency",
#         "labelBindings": [],
#         "groupByFields": [],
#         "customInlineTemplate": "",
#         "customFilterTemplate": "Filter",
#         "serviceType": "prometheus"
#       },
#       "groups": [
#         "Latency"
#       ],
#       "analysisConfigurations": {
#         "canary": {
#           "direction": "increase"
#         }
#       },
#       "scopeName": "default"
#     }
#   ],
#   "templates": {
#     "Filter": "group=\"${scope}\",namespace=\"${location}\""
#   },
#   "classifier": {
#     "groupWeights": {
#       "Latency": 100
#     }
#   }
# }
# EOF

# For some reason, the expected time is ISO, but not ISO:
# ISO outputs  2020-03-22T20:28:18+00:00
# This expects 2020-03-22T20:27:30.000Z
# To be fixed, but for now this works

sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
    -e "s|__ISO_TIMESTAMP__|${ISO_TIMESTAMP}|g" \
    ${BASE_DIR}/templates/demo/democanary/canary_config/Latency.json.tmpl \
    > ${KAYENTA_PATH}/canary_config/${CANARY_CONFIG_UUID}/Latency.json


# sed -e "s|__TIMESTAMP__|$(date +%s000)|g" \
#     -e "s|__ISO_TIMESTAMP__|$(date +"%Y-%m-%dT%T.000Z")|g" \
#     /tmp/canary_config_Latency.json \
#     > ${KAYENTA_PATH}/canary_config/${CANARY_CONFIG_UUID}/Latency.json

kubectl -n spinnaker rollout restart deployment/spin-kayenta
kubectl create ns prod