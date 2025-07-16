#!/bin/bash

set -e

load_all_pages() {
  # based on from https://gist.github.com/fj/6784d4e53d72dc4a33b678807fdd8589
  # modified to work with the v3 API

  URL="${1}"
  DATA=""
  until [ "${URL}" == "null" ]
  do
    RESP=$(cf curl "${URL}")
    DATA+=$(echo "${RESP}" | jq .resources)
    URL=$(echo "${RESP}" | jq -r .pagination.next.href)

    # strip off domain if next page set so cf curl can handle it
    if [ "${URL}" != "null" ]
    then
      URL="/$(echo "${URL}" | cut -d '/' -f4-)"
    fi
  done

  # dump the data
  echo "${DATA}" | jq .[] | jq -s
}

# get all orgs
ORGS="$(load_all_pages /v3/organizations | jq -r '.[] | .name')"

# initialize AIs/SIs
TOTAL_AIS=0
TOTAL_SIS=0

# loop through orgs
for ORG in ${ORGS}
do
  # skip the system org
  if [ "${ORG}" != "system" ]
  then
    # output org
    echo "Processing ${ORG}..."

    # list AIs in org
    ORG_GUID="$(load_all_pages /v3/organizations | jq -r '.[] | select(.name == "'"${ORG}"'") | .guid')"

    # get the summary
    SUMMARY="$(cf curl "/v3/organizations/${ORG_GUID}/usage_summary")"

    # get AIs and SIs
    AIS="$(echo "${SUMMARY}" | jq .usage_summary.started_instances)"
    SIS="$(echo "${SUMMARY}" | jq .usage_summary.service_instances)"

    # output AIs and SIs for this org
    echo "AIs: ${AIS}"
    echo "SIs: ${SIS}"
    echo

    # add the AIs and SIs to totals
    TOTAL_AIS=$((TOTAL_AIS + AIS))
    TOTAL_SIS=$((TOTAL_SIS + SIS))
  fi
done

# output final totals
echo "Total AIs: ${TOTAL_AIS}"
echo "Total SIs: ${TOTAL_SIS}"
