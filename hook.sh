#!/usr/bin/env bash

function has_propagated {
    while (( "$#" >= 2 )); do
        local RECORD_NAME="${1}"; shift
        local TOKEN_VALUE="${1}"; shift
        dig +short "${RECORD_NAME}" IN TXT | grep -q \"${TOKEN_VALUE}\" || return 1
    done
    return 0
}

function deploy_challenge {
    local RECORDS=()
    RECIPIENT=${RECIPIENT:-$(id -u -n)}
    local FIRSTDOMAIN="${1}"
    local SUBJECT="Let's Encrypt certificate renewal"
    while (( "$#" >= 3 )); do
        local DOMAIN="${1}"; shift
        local TOKEN_FILENAME="${1}"; shift
        local TOKEN_VALUE="${1}"; shift

        # This hook is called once for every domain that needs to be
        # validated, including any alternative names you may have listed.
        #
        # Parameters:
        # - DOMAIN
        #   The domain name (CN or subject alternative name) being
        #   validated.
        # - TOKEN_FILENAME
        #   The name of the file containing the token to be served for HTTP
        #   validation. Should be served by your web server as
        #   /.well-known/acme-challenge/${TOKEN_FILENAME}.
        # - TOKEN_VALUE
        #   The token value that needs to be served for validation. For DNS
        #   validation, this is what you want to put in the _acme-challenge
        #   TXT record. For HTTP validation it is the value that is expected
        #   be found in the $TOKEN_FILENAME file.

        RECORD_NAME="_acme-challenge.${DOMAIN}"
        RECORDS+=( ${RECORD_NAME} )
        RECORDS+=( ${TOKEN_VALUE} )
    done

    read -d '' MESSAGE <<EOF
The Let's Encrypt certificate for ${FIRSTDOMAIN} is about to expire.
Before it can be renewed, ownership of the domain must be proven by
responding to a challenge.

Please deploy the following record(s) to validate ownership of ${FIRSTDOMAIN}:

EOF
    for (( i=0; i < "${#RECORDS[@]}"; i+=2 )); do
        MESSAGE="$(printf '%s\n  %s IN TXT %s\n' "$MESSAGE" "${RECORDS[$i]}" "${RECORDS[$(($i + 1))]}")"
    done

    echo "$MESSAGE" | mail -s "$SUBJECT" "$RECIPIENT"

    echo " + Settling down for 10s..."
    sleep 10

    while ! has_propagated "${RECORDS[@]}"; do
         echo " + DNS not propagated. Waiting 30s for record creation and replication..."
         sleep 30
    done
}

function clean_challenge {
    local RECORDS=()
    RECIPIENT=${RECIPIENT:-$(id -u -n)}
    local FIRSTDOMAIN="${1}"
    local SUBJECT="Let's Encrypt certificate renewal"
    while (( "$#" >= 3 )); do
        local DOMAIN="${1}"; shift
        local TOKEN_FILENAME="${1}"; shift
        local TOKEN_VALUE="${1}"; shift

        # This hook is called after attempting to validate each domain,
        # whether or not validation was successful. Here you can delete
        # files or DNS records that are no longer needed.
        #
        # The parameters are the same as for deploy_challenge.

        RECORD_NAME="_acme-challenge.${DOMAIN}"
        RECORDS+=( ${RECORD_NAME} )
        RECORDS+=( ${TOKEN_VALUE} )
    done

    read -d '' MESSAGE <<EOF
Progagation has completed for ${FIRSTDOMAIN}. The following record(s) can now be deleted:

EOF

    while (( "${#RECORDS}" >= 2 )); do
        MESSAGE="$(printf '%s\n  %s IN TXT %s\n' "$MESSAGE" "${RECORDS[0]}" "${RECORDS[1]}")"
        RECORDS=( "${RECORDS[@]:2}" )
    done

    echo "$MESSAGE" | mail -s "$SUBJECT" "$RECIPIENT"

}

function deploy_cert {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"

    # This hook is called once for each certificate that has been
    # produced. Here you might, for instance, copy your new certificates
    # to service-specific locations and reload the service.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - KEYFILE
    #   The path of the file containing the private key.
    # - CERTFILE
    #   The path of the file containing the signed certificate.
    # - FULLCHAINFILE
    #   The path of the file containing the full certificate chain.
    # - CHAINFILE
    #   The path of the file containing the intermediate certificate(s).

    # Get oscp response and shove it into a file, used for OCSP stapling.
    #
    # You only need this for old versions of of nginx that can't do this itself.
    # It's also useful if you want to use OCSP staping, but can't connect directly
    # to the internet (nginx can't do OCSP via HTTP proxy).
    #
    # If you enable, this, you should also update the file regularly using cron.
    #
    if [ -n "${OCSP_RESPONSE_FILE}" ]; then

        if [ -z "${OCSP_HOST}" ]; then
            OCSP_HOST="${http_proxy}"
        fi

        if [ -n "${OCSP_HOST}" ]; then
            openssl ocsp -noverify -no_nonce -respout "${OCSP_RESPONSE_FILE}" -issuer "${CHAINFILE}" -cert "${CERTFILE}" -host "${OCSP_HOST}" -path "$(openssl x509 -noout -ocsp_uri -in "${CERTFILE}")" -CApath "/etc/ssl/certs"
        else
            openssl ocsp -noverify -no_nonce -respout "${OCSP_RESPONSE_FILE}" -issuer "${CHAINFILE}" -cert "${CERTFILE}" -path "$(openssl x509 -noout -ocsp_uri -in "${CERTFILE}")" -CApath "/etc/ssl/certs"
        fi
    fi
}

function unchanged_cert {
    # not yet implemented
    :;
}

HANDLER=$1; shift; $HANDLER $@
