#!/usr/bin/env bash

# shellcheck source=/dev/null
source "./.github/workflows/scripts/e2e-verify.common.sh"

# Input variables
EXPECTED_ARTIFACT_OUTPUT=${EXPECTED_ARTIFACT_OUTPUT:-}
PROVENANCE_DIR=${PROVENANCE_DIR:-}
GITHUB_REF_NAME=${GITHUB_REF_NAME:-}
GITHUB_REF=${GITHUB_REF:-}
GITHUB_REF_TYPE=${GITHUB_REF_TYPE:-}
RUNNER_DEBUG=${RUNNER_DEBUG:-}
PROJECT_DIR=${PROJECT_DIR:-}
if [[ -n "${RUNNER_DEBUG}" ]]; then
    set -x
fi

cp -r  "slsa-attestations" "${PROJECT_DIR}/"
cp -r build "${PROJECT_DIR}/"
cd "${PROJECT_DIR}" || exit # exit to satisfy Shellcheck

# See https://stackoverflow.com/questions/17998978/removing-colors-from-output
# Laurent tried -Dmaven.color=false and --batch-mode tomvn, without success.
remove_colors() {
    local s="$1"
    echo "$s" | sed -r "s/[[:cntrl:]]\[[0-9]{1,3}m//g"
}

artifact_version=$(./gradlew properties -q | grep "version:" | awk '{print $2}')
artifact_version=$(remove_colors "$artifact_version")
artifact_id=$(./gradlew properties -q | grep "name:" | awk '{print $2}')
artifact_id=$(remove_colors "$artifact_id")
artifact_name="${artifact_id}-${artifact_version}.jar"
provenance="${PROVENANCE_DIR}/${artifact_name}.build.slsa"

go env -w GOFLAGS=-mod=mod

verify_provenance_content() {
    local attestation
    attestation=$(jq -r '.dsseEnvelope.payload' "${provenance}" | base64 -d)

    # Run the artifact and verify the output is correct
    artifact_output=$(java -jar build/libs/"${artifact_name}")
    expected_artifact_output="${EXPECTED_ARTIFACT_OUTPUT}"
    e2e_assert_eq "${artifact_output}" "${expected_artifact_output}" "The output from the artifact should be '${expected_artifact_output}' but was '${artifact_output}'"
    
    # Verify the content of the attestation
    e2e_verify_predicate_subject_name "${attestation}" "${artifact_name}"
    e2e_verify_predicate_v1_runDetails_builder_id "${attestation}" "https://github.com/slsa-framework/slsa-github-generator/.github/workflows/builder_gradle_slsa3.yml@refs/heads/main"
    e2e_verify_predicate_v1_buildDefinition_buildType "${attestation}" "https://github.com/slsa-framework/slsa-github-generator/delegator-generic@v0"
}

this_file=$(e2e_this_file)
branch=$(echo "$this_file" | cut -d '.' -f4)
echo "branch is $branch"
echo "GITHUB_REF_NAME: $GITHUB_REF_NAME"
echo "GITHUB_REF_TYPE: $GITHUB_REF_TYPE"
echo "GITHUB_REF: $GITHUB_REF"
echo "DEBUG: file is $this_file"
echo "PROVENANCE is: ${provenance}"

export SLSA_VERIFIER_TESTING="true"

# Verify provenance content.
verify_provenance_content

e2e_run_verifier_all_releases "HEAD"
