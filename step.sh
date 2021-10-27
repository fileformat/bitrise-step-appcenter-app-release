#!/bin/bash
#
# upload an app from Bitrise to AppCenter
#
# API details: https://docs.microsoft.com/en-us/appcenter/distribution/uploading
#

set -o errexit
set -o pipefail
set -o nounset

RESTORE='\033[0m'
RED='\033[00;31m'
YELLOW='\033[00;33m'
BLUE='\033[00;34m'
GREEN='\033[00;32m'

function color_echo {
	color=$1
	msg=$2
	echo -e "${color}${msg}${RESTORE}"
}

function echo_fail {
	msg=$1
	echo
	color_echo "${RED}" "${msg}"
	exit 1
}

function echo_warn {
	msg=$1
	color_echo "${YELLOW}" "${msg}"
}

function echo_info {
	msg=$1
	echo
	color_echo "${BLUE}" "${msg}"
}

function echo_details {
	msg=$1
	echo "  ${msg}"
}

function echo_done {
	msg=$1
	color_echo "${GREEN}" "  ${msg}"
}

function validate_required_input {
	key=$1
	value=${2:-}
	if [ -z "${value}" ] ; then
		echo_fail "[!] Missing required input: ${key}"
	fi
}

echo_info "Starting AppCenter app upload at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

validate_required_input "appcenter_api_token" ${appcenter_api_token:-}
validate_required_input "appcenter_name" ${appcenter_name:-}
validate_required_input "appcenter_org" ${appcenter_org:-}
validate_required_input "artifact_path" ${artifact_path:-}

RELEASE_NOTES_ENCODED="$( jq --null-input --compact-output --arg str "${release_notes:-}" '$str' )"

if [ ! -f "${artifact_path}" ]; then
	echo_fail "[!] File ${artifact_path} does not exist"
fi

if [ "${appcenter_api_token}" == "TestApiToken" ]
then
	echo_done "Running in test mode: all the parameters look good!"
	exit 0
fi

echo_info "Getting a release upload url for ${appcenter_org}/${appcenter_name}"
TMPFILE=$(mktemp)
STATUSCODE=$(curl \
	-X POST \
	--header 'Content-Type: application/json' \
	--header "accept: application/json" \
	--header "X-API-Token: ${appcenter_api_token}" \
	--silent --show-error \
	--output /dev/stderr --write-out "%{http_code}" \
	"https://api.appcenter.ms/v0.1/apps/${appcenter_org}/${appcenter_name}/uploads/releases" \
	2> "${TMPFILE}")
if [ "${STATUSCODE}" -ne "201" ]
then
	echo_fail "API call failed with ${STATUSCODE}: $(cat ${TMPFILE})"
fi

UPLOAD_URL=$(cat "${TMPFILE}" | jq .upload_url --raw-output)
UPLOAD_ID=$(cat "${TMPFILE}" | jq .upload_id --raw-output)

echo_details "result is ${STATUSCODE}: $(cat ${TMPFILE})"
rm "${TMPFILE}"

echo_info "Uploading ${artifact_path} to ${UPLOAD_URL}"
TMPFILE=$(mktemp)
STATUSCODE=$(curl \
	-F "ipa=@${artifact_path}" \
	--silent --show-error \
	--output /dev/stderr --write-out "%{http_code}" \
	"${UPLOAD_URL}" \
	2> "${TMPFILE}")
if [ "${STATUSCODE}" -gt "299" ]
then
	echo_fail "API call failed with ${STATUSCODE}: $(cat ${TMPFILE})"
fi
echo_details "result is ${STATUSCODE}: $(cat ${TMPFILE})"
rm "${TMPFILE}"

echo_info "Committing the release"
TMPFILE=$(mktemp)
STATUSCODE=$(curl \
	-X PATCH \
	--header "accept: application/json" \
	--header "X-API-Token: ${appcenter_api_token}" \
	--header "Content-Type: application/json" \
	--silent --show-error \
	--output /dev/stderr --write-out "%{http_code}" \
	-d '{ "status": "committed"}' \
	"https://api.appcenter.ms/v0.1/apps/${appcenter_org}/${appcenter_name}/release_uploads/${UPLOAD_ID}" \
	2> "${TMPFILE}")
if [ "${STATUSCODE}" -ne "200" ]
then
	echo_fail "API call failed with ${STATUSCODE}: $(cat ${TMPFILE})"
fi
RELEASE_ID=$(cat "${TMPFILE}" | jq .release_id --raw-output)
echo_details "result is ${STATUSCODE}: $(cat ${TMPFILE})"
rm "${TMPFILE}"

IFS=', ' read -r -a DISTRIBUTION_GROUPS <<< ${distribution_groups:-}
if [ ${#DISTRIBUTION_GROUPS[@]} -eq 0 ]
then
echo_info "Retrieving distribution groups for ${appcenter_name}"
TMPFILE=$(mktemp)
STATUSCODE=$(curl \
	-X GET \
	-H "accept: application/json" \
	-H "X-API-Token: ${appcenter_api_token}" \
	--silent --show-error \
	--output /dev/stderr --write-out "%{http_code}" \
	"https://api.appcenter.ms/v0.1/apps/${appcenter_org}/${appcenter_name}/distribution_groups" \
	2> ${TMPFILE})
if [ "${STATUSCODE}" -ne "200" ]
then
	echo_fail "API call failed with ${STATUSCODE}: $(cat ${TMPFILE})"
fi
echo_details "result is ${STATUSCODE}: $(cat ${TMPFILE})"
SAVEIFS="${IFS}"
IFS=$'\n'
DISTRIBUTION_GROUPS=( $(cat "${TMPFILE}" | jq '.[].name' --raw-output) )
IFS="${SAVEIFS}"
rm "${TMPFILE}"
fi
echo_details "distribution groups are ${DISTRIBUTION_GROUPS[*]}"

for DISTRIBUTION_GROUP in "${DISTRIBUTION_GROUPS[@]}"
do
	DISTRIBUTION_GROUP_ENCODED="$( jq --null-input --compact-output --arg str "$DISTRIBUTION_GROUP" '$str' )"
	echo_info "Adding to distribution group ${DISTRIBUTION_GROUP}"
	TMPFILE=$(mktemp)
	STATUSCODE=$(curl -X PATCH \
		--header "Content-Type: application/json" \
		--header "Accept: application/json" \
		--header "X-API-Token: ${appcenter_api_token}" \
		--silent --show-error \
		--output /dev/stderr --write-out "%{http_code}" \
		-d "{ \"destination_name\": ${DISTRIBUTION_GROUP_ENCODED}, \"release_notes\": ${RELEASE_NOTES_ENCODED}, \"mandatory_update\": ${mandatory_update:-false}, \"notify_testers\": ${notify_testers:-true}}" \
		"https://api.appcenter.ms/v0.1/apps/${appcenter_org}/${appcenter_name}/releases/${RELEASE_ID}" \
		2> "${TMPFILE}")

	if [ "${STATUSCODE}" -ne "200" ]
	then
		echo_fail "API call failed with ${STATUSCODE}: $(cat ${TMPFILE})"
	fi
	echo_details "result is ${STATUSCODE}: $(cat ${TMPFILE})"
	rm "${TMPFILE}"
done

echo_info "Retrieving download url"
TMPFILE=$(mktemp)
STATUSCODE=$(curl -X GET \
	--header "Accept: application/json" \
	--header "X-API-Token: ${appcenter_api_token}" \
	--silent --show-error \
	--output /dev/stderr --write-out "%{http_code}" \
	"https://api.appcenter.ms/v0.1/apps/${appcenter_org}/${appcenter_name}/releases/${RELEASE_ID}" \
	2> "${TMPFILE}")

if [ "${STATUSCODE}" -ne "200" ]
then
	echo_fail "API call failed with ${STATUSCODE}: $(cat ${TMPFILE})"
fi
DOWNLOAD_URL=$(cat "${TMPFILE}" | jq .download_url --raw-output)

echo_details "result is ${STATUSCODE}: $(cat ${TMPFILE})"
echo_details "APPCENTER_DOWNLOAD_URL is ${DOWNLOAD_URL}"
envman add --key APPCENTER_DOWNLOAD_URL --value "${DOWNLOAD_URL}"

rm "${TMPFILE}"

echo_done "Completed AppCenter app upload at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
