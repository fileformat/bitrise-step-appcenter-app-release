#!/bin/bash
#
# test various settings
#

set -o errexit
set -o pipefail
set -o nounset


#
# .env must have the following set to valid values:
# APPCENTER_API_TOKEN
# APPCENTER_ORG
# APPCENTER_NAME
# ARTIFACT_PATH
#
export $(cat .env)

echo "INFO: testing with defaults"
bitrise run test

echo "INFO: testing to 1 group, no notifications"
export DISTRIBUTION_GROUPS=x-test-group-1
export NOTIFY_TESTERS=false
bitrise run test

echo "INFO: testing to second group, w/notifications and release notes"
export DISTRIBUTION_GROUPS=x-test-group-2
export NOTIFY_TESTERS=true
export RELEASE_NOTES="Hey there, just testing at $(date)"
bitrise run test

echo "INFO: testing to two groups, w/notifications and release notes"
export DISTRIBUTION_GROUPS=x-test-group-1,x-test-group-2
export NOTIFY_TESTERS=true
export RELEASE_NOTES="Wow! Another test at $(date)!"
bitrise run test

echo "INFO: testing multi-line release notes"
export RELEASE_NOTES=$'a e""R<*&before newline\nafter newline 1
after newline 2\n\nafter two newlines\thello!&amp;after ampersand\''
export MANDATORY_UPDATE=true
bitrise run test
