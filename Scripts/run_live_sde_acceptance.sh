#!/bin/sh
set -eu

owner_contact=$(
  /usr/bin/security find-generic-password \
    -s de.newedennexus.tokens \
    -a sde.owner-contact \
    -w
)

if [ -z "$owner_contact" ]; then
  echo "live_acceptance_error=owner-contact-missing" >&2
  exit 2
fi

EVE_SDE_OWNER_CONTACT="$owner_contact" \
  /usr/bin/swift run EVENexusLiveAcceptance sde
