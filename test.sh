#!/bin/bash

# set -euxo pipefail

#### COLORS
RED="\e[0;91m"
GREEN="\e[0;92m"
RESET="\e[0m"
#### COLORS

SSH_COMMAND="ssh -i /root/.ssh/id_rsa_test localhost"

#### SETUP FUNCTION
# Install packages, set initial variables and configure SSH access to testing
# ARGUMENTS:
#   Nothing
# OUTPUTS:
# 	Nothing
# RETURNS:
#   Nothing
#### SETUP FUNCTION
setup() {
    if [[ -f "/root/setup-executed" ]]; then
        cleanup
        setup
    else
        PASSED_TESTS=()
        FAILED_TESTS=()

        # Verify and install necessary packages
        PACKAGES_REQUISITES=("openssh-server" "crypto-policies" "curl")
        INSTALLED_PACKAGES=()
        for pkg in ${PACKAGES_REQUISITES[@]}; do
            IS_INSTALLED=$(
                yum list installed ${pkg} >/dev/null 2>&1
                echo $?
            )
            if [ ${IS_INSTALLED} == 1 ]; then
                yum install -y ${pkg}
                INSTALLED_PACKAGES+=("${pkg}")
            fi
        done

        # Make backup and configure SSH key
        mkdir -p /root/.ssh/
        ssh-keygen -f /root/.ssh/id_rsa_test -N ''
        [[ -f /root/.ssh/authorized_keys ]] && cp /root/.ssh/authorized_keys /root/.ssh/authorized_keys.bkp
        cat /root/.ssh/id_rsa_test.pub >>/root/.ssh/authorized_keys

        # Define START_POLICY
        START_POLICY=$(update-crypto-policies --show)

        echo "START_POLICY=${START_POLICY}" >/root/setup-executed
    fi
}

#### CLEANUP FUNCTION
# Remove packages and configurations made for testing
# ARGUMENTS:
#   GLOBAL:
#       INSTALLED_PACKAGES - array - packages installed in setup function
#       START_POLICY - string - policy before setup function
# OUTPUTS:
# 	Nothing
# RETURNS:
#   Nothing
#### CLEANUP FUNCTION
cleanup() {
    # Remove installed packages
    for pkg in ${INSTALLED_PACKAGES[@]}; do
        yum remove ${pkg} -y
    done

    # Reset policy to start policy and remove setup-executed flag
    if [[ -f "/root/setup-executed" ]]; then
        set -o allexport
        source /root/setup-executed
        set +o allexport
        rm /root/setup-executed
    fi
    change_policy ${START_POLICY}

    # Reset ssh settings
    rm /root/.ssh/{id_rsa_test,id_rsa_test.pub}
    [[ -f /root/.ssh/authorized_keys.bkp ]] && mv /root/.ssh/authorized_keys.bkp /root/.ssh/authorized_keys || rm /root/.ssh/authorized_keys

}

#### CHANGE POLICY FUNCTION
# Change crypto policy
# ARGUMENTS:
#   POLICY - string - DEFAULT or LEGACY
# OUTPUTS:
# 	Nothing
# RETURNS:
#   Nothing
#### CHANGE POLICY FUNCTION
change_policy() {
    update-crypto-policies --set $1 >/dev/null
    sleep 10
    restart_services
}

#### RESTART SERVICES FUNCTION
# Restart services to apply settings
# ARGUMENTS:
#   Nothing
# OUTPUTS:
# 	Nothing
# RETURNS:
#   Nothing
#### RESTART SERVICES FUNCTION
restart_services() {
    systemctl restart sshd >/dev/null
}

#### TEST LEGACY ALGORITHM FUNCTION
# Run test legacy algorithm with DEFAULT and LEGACY policies
# ARGUMENTS:
#   GLOBAL:
#       SSH_COMMAND - command
# OUTPUTS:
# 	Nothing
# RETURNS:
#   Nothing
#### TEST LEGACY ALGORITHM FUNCTION
test_legacy_algorithm() {
    if [[ ! -f "/root/setup-executed" ]]; then
        echo "####### You need to run the setup before."
        echo "####### Use: $0 setup"
    else
        echo "####### Running test_legacy_algorithm"

        set -x
        change_policy "DEFAULT"
        RESULT_DEFAULT=$(
            ${SSH_COMMAND} -o Ciphers=3des-cbc "echo 'CONNECTED'"
            echo $?
        )
        change_policy "LEGACY"
        RESULT_LEGACY=$(
            ${SSH_COMMAND} -o Ciphers=3des-cbc "echo 'CONNECTED'"
        )
        set +x

        if [[ ${RESULT_DEFAULT} == 255 ]] && [[ "${RESULT_LEGACY}" == "CONNECTED" ]]; then
            PASSED_TESTS+=("test_legacy_algorithm")
            echo -e "${GREEN}TEST PASSED${RESET}"
        else
            FAILED_TESTS+=("test_legacy_algorithm")
            echo -e "${RED}TEST FAILED${RESET}"
        fi

        echo "####### Finished test_legacy_algorithm"
    fi
}

#### TEST SHA1 ALGORITHM FUNCTION
# Run test SHA1 algorithm with DEFAULT and LEGACY policies
# ARGUMENTS:
#   GLOBAL:
#       SSH_COMMAND - command
# OUTPUTS:
# 	Nothing
# RETURNS:
#   Nothing
#### TEST SHA1 ALGORITHM FUNCTION
test_sha1_algorithm() {
    if [[ ! -f "/root/setup-executed" ]]; then
        echo "####### You need to run the setup before."
        echo "####### Use: $0 setup"
    else
        echo "####### Running test_sha1_algorithm"

        set -x
        change_policy "DEFAULT"
        RESULT_DEFAULT=$(
            ${SSH_COMMAND} -o KexAlgorithms=diffie-hellman-group-exchange-sha1 "echo 'CONNECTED'"
            echo $?
        )
        change_policy "LEGACY"
        RESULT_LEGACY=$(
            ${SSH_COMMAND} -o KexAlgorithms=diffie-hellman-group-exchange-sha1 "echo 'CONNECTED'"
        )
        set +x

        if [[ ${RESULT_DEFAULT} == 255 ]] && [[ "${RESULT_LEGACY}" == "CONNECTED" ]]; then
            PASSED_TESTS+=("test_sha1_algorithm")
            echo -e "${GREEN}TEST PASSED${RESET}"
        else
            FAILED_TESTS+=("test_sha1_algorithm")
            echo -e "${RED}TEST FAILED${RESET}"
        fi

        echo "####### Finished test_sha1_algorithm"
    fi
}

#### PRINT RESULTS FUNCTION
# Run test SHA1 algorithm with DEFAULT and LEGACY policies
# ARGUMENTS:
#   GLOBAL:
#       SSH_COMMAND - command
#       FAILED_TESTS - array
#       PASSED_TESTS - array
# OUTPUTS:
# 	Nothing
# RETURNS:
#   Nothing
#### PRINT RESULTS FUNCTION
print_results() {
    echo ""
    echo "####### RESULTS"
    echo ""
    echo "TOTAL TESTS: $((${#FAILED_TESTS[@]} + ${#PASSED_TESTS[@]}))"
    echo ""
    echo -e "${GREEN}PASSED TESTS: ${RESET}${#PASSED_TESTS[@]}"
    for passed_test in ${PASSED_TESTS[@]}; do
        echo ${passed_test}
    done
    echo ""
    echo -e "${RED}FAILED TESTS: ${RESET}${#FAILED_TESTS[@]}"
    for failed_test in ${FAILED_TESTS[@]}; do
        echo ${failed_test}
    done
}

main() {
    setup
    test_legacy_algorithm
    test_sha1_algorithm
    cleanup
    print_results
}

if [ $# == 0 ]; then
    main
elif [ "$1" == "-l" ]; then
    echo "####### TESTS AVALIABLE"
    echo "test_legacy_algorithm"
    echo "test_sha1_algorithm"
else
    "$@"
fi
