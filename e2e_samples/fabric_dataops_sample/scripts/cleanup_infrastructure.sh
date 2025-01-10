#!/bin/bash
set -o errexit

#######################################################
# Deploys all necessary azure and Fabric resources
#
# Prerequisites:
# - User is logged in to the azure cli
# - Correct Azure subscription is selected
#######################################################

## Environment variables
environment_name="$ENVIRONMENT_NAME"
tenant_id="$TENANT_ID"
subscription_id="$SUBSCRIPTION_ID"
resource_group_name="$RESOURCE_GROUP_NAME"
base_name="$BASE_NAME"
## Service Principal details
client_id="$APP_CLIENT_ID"
client_secret="$APP_CLIENT_SECRET"
# GIT integration details
git_organization_name="$GIT_ORGANIZATION_NAME"
git_project_name="$GIT_PROJECT_NAME"
git_repository_name="$GIT_REPOSITORY_NAME"
git_branch_name="$GIT_BRANCH_NAME"
git_directory_name="$GIT_DIRECTORY_NAME"
# Workspace admin variables
fabric_workspace_admin_sg_name="$FABRIC_WORKSPACE_ADMIN_SG_NAME"
# Fabric Capacity variables
existing_fabric_capacity_name="$EXISTING_FABRIC_CAPACITY_NAME"
fabric_capacity_admins="$FABRIC_CAPACITY_ADMINS"

## KeyVault secret variables
appinsights_connection_string_name="appinsights-connection-string"

# Fabric bearer token variables, set globally
fabric_bearer_token=""
fabric_api_endpoint="https://api.fabric.microsoft.com/v1"

# Fabric related variables
adls_gen2_shortcut_name="sc-adls-main"
adls_gen2_shortcut_path="Files"

cleanup_terraform_resources() {
  local original_directory=$(pwd)
  cd "$1" || exit

  user_principal_type=$(az account show --query user.type -o tsv)
  if [[ $user_principal_type == "user" ]]; then
    use_cli="true"
    use_msi="false"
  else
    use_cli="false"
    msi=$(az account show --query user.assignedIdentityInfo -o tsv)
    if [[ -z ${msi} ]]; then
      use_msi=false
    else
      use_msi=true
    fi
  fi
  echo "[Info] use_cli is '${use_cli}'"
  echo "[Info] use_msi is '${use_msi}'"
  echo "[Info] client_id is '${client_id}'"

  if [[ -z ${existing_fabric_capacity_name} ]]; then
    create_fabric_capacity=true
    echo "[Info] Variable 'EXISTING_FABRIC_CAPACITY_NAME' is empty, a new Fabric capacity will be created."
  else
    create_fabric_capacity=false
    echo "[Info] Variable 'EXISTING_FABRIC_CAPACITY_NAME' is NOT empty, the provided Fabric capacity will be used."
  fi

  echo "[Info] Switching to terraform '$environment_name' workspace."
  terraform workspace select -or-create=true "$environment_name"

  terraform init
  terraform destroy \
    -auto-approve \
    -var "use_cli=$use_cli" \
    -var "use_msi=$use_msi" \
    -var "environment_name=$environment_name" \
    -var "tenant_id=$tenant_id" \
    -var "subscription_id=$subscription_id" \
    -var "resource_group_name=$resource_group_name" \
    -var "base_name=$base_name" \
    -var "client_id=$client_id" \
    -var "client_secret=$client_secret" \
    -var "fabric_workspace_admin_sg_name=$fabric_workspace_admin_sg_name" \
    -var "create_fabric_capacity=$create_fabric_capacity" \
    -var "fabric_capacity_name=$existing_fabric_capacity_name" \
    -var "fabric_capacity_admins=$fabric_capacity_admins" \
    -var "git_organization_name=$git_organization_name" \
    -var "git_project_name=$git_project_name" \
    -var "git_repository_name=$git_repository_name" \
    -var "git_branch_name=$git_branch_name" \
    -var "git_directory_name=$git_directory_name" \
    -var "kv_appinsights_connection_string_name=$appinsights_connection_string_name"

  cd "$original_directory"
}

set_bearer_token() {
  fabric_bearer_token=$(az account get-access-token \
    --resource "https://login.microsoftonline.com/${tenant_id}" \
    --query accessToken \
    --scope "https://analysis.windows.net/powerbi/api/.default" \
    -o tsv)
}

delete_connection() {
  # Function to delete a connection if it exists
  connection_id=$1
  delete_connection_url="$fabric_api_endpoint/connections/$connection_id"

  response=$(curl -s -X DELETE -H "Authorization: Bearer $fabric_bearer_token" "$delete_connection_url")

  if [[ -z $response ]]; then
    echo "[Info] Connection '$connection_id' deleted successfully."
  else
    echo "[Error] Failed to delete connection '$connection_id'."
    echo "[Error] $response"
  fi
}

cleanup_terraform_files() {
  # List and delete .terraform directories
  echo "[Info] Listing Terraform state directory that will be deleted:"
  find . -type d -name "${environment_name}" -path "*/terraform.tfstate.d/*"
  find . -type d -name "${environment_name}" -path "*/terraform.tfstate.d/*" -exec rm -rf {} + 2>/dev/null
  echo "[Info] Listing '.terraform' directory that will be deleted:"
  find . -type d -name ".terraform"
  find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null
  echo "[Info] Terraform directories deleted successfully."

  # List and delete specific Terraform files
  echo "[Info] Listing Terraform lock file that will be deleted:"
  find . -type f -name ".terraform.lock.hcl"
  find . -type f -name ".terraform.lock.hcl" -exec rm -f {} + 2>/dev/null
  echo "[Info] Terraform lock file deleted successfully."
}

get_connection_id_by_name() {
  connection_name=$1
  list_connection_url="$fabric_api_endpoint/connections"
  response=$(curl -s -X GET -H "Authorization: Bearer $fabric_bearer_token" -H "Content-Type: application/json" "$list_connection_url" )
  connection_id=$(echo "$response" | jq -r --arg name "$connection_name" '.value[] | select(.displayName == $name) | .id')
  echo "$connection_id"
}

echo "[Info] ############ STARTING CLEANUP STEPS############"

echo "[Info] ############ Destroy terraform resources ############"
cleanup_terraform_resources "./infrastructure/terraform"
echo "[Info] ############ Terraform resources destroyed############"

echo "[Info] Setting up fabric bearer token ############"
set_bearer_token

echo "[Info] ############ ADLS Gen2 connection deletion ############"
# Deriving ADLS Gen2 connection name instead of relying on Terraform output for idempotency
adls_gen2_connection_name="conn-adls-st${base_name//[-_]/}${environment_name}"

adls_gen2_connection_id=$(get_connection_id_by_name "$adls_gen2_connection_name")

if [[ -z $adls_gen2_connection_id ]]; then
  echo "[Warning] No Fabric connection with name '$adls_gen2_connection_name' found, skipping deletion."
else
  echo "[Info] Fabric Connection details: '$adls_gen2_connection_name' ($adls_gen2_connection_id)"
  delete_connection "$adls_gen2_connection_id"
fi

echo "[Info] ############ Cleanup Terraform Intermediate files (state, lock etc.,) ############"
cleanup_terraform_files

echo "[Info] ############ FINISHED INFRA CLEANUP ############"
