#!/bin/bash

SSH_COMMAND="ssh -i /root/.ssh/id_rsa_test localhost"

configure_prerequisites() {
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

    mkdir -p /root/.ssh/
    ssh-keygen -f /root/.ssh/id_rsa_test -N ''
    [[ -f /root/.ssh/authorized_keys ]] && cp /root/.ssh/authorized_keys /root/.ssh/authorized_keys.bkp 
    cat /root/.ssh/id_rsa_test.pub >> /root/.ssh/authorized_keys

}

setup() {
    PASSED_TESTS=()
    FAILED_TESTS=()
    configure_prerequisites
    START_POLICY=$(update-crypto-policies --show)
}

cleanup() {
    for pkg in ${INSTALLED_PACKAGES[@]}; do
        yum remove ${pkg} -y
    done

    change_policy ${START_POLICY}
    rm /root/.ssh/{id_rsa_test,id_rsa_test.pub}
    [[ -f /root/.ssh/authorized_keys.bkp ]] && mv /root/.ssh/authorized_keys.bkp /root/.ssh/authorized_keys || rm /root/.ssh/authorized_keys
}

change_policy() {
    update-crypto-policies --set $1 >/dev/null
    sleep 10
    restart_services
}

restart_services() {
    systemctl restart sshd >/dev/null
}

test_legacy_algorithm() {
    echo "####### Running test_legacy_algorithm"

    change_policy "DEFAULT"
    RESULT_DEFAULT=$(
        ${SSH_COMMAND} -oCiphers=3des-cbc "echo 'CONNECTED'" 2>&-
        echo $?
    )
    change_policy "LEGACY"
    RESULT_LEGACY=$(
        ${SSH_COMMAND} -oCiphers=3des-cbc "echo 'CONNECTED'"
    )
    if [[ ${RESULT_DEFAULT} == 255 ]] && [[ "${RESULT_LEGACY}" == "CONNECTED" ]]; then
        PASSED_TESTS+=("test_legacy_algorithm")
        echo "TEST PASSED"
    else
        FAILED_TESTS+=("test_legacy_algorithm")
        echo "TEST FAILED"
    fi

    echo "####### Finished test_legacy_algorithm"
}

test_sha1_algorithm() {
    echo "####### Running test_sha1_algorithm"

    change_policy "DEFAULT"
    RESULT_DEFAULT=$(
        ${SSH_COMMAND} -o KexAlgorithms=diffie-hellman-group-exchange-sha1 "echo 'CONNECTED'" 2>&-
        echo $?
    )
    change_policy "LEGACY"
    RESULT_LEGACY=$(
        ${SSH_COMMAND} -o KexAlgorithms=diffie-hellman-group-exchange-sha1 "echo 'CONNECTED'"
    )

    if [[ ${RESULT_DEFAULT} == 255 ]] && [[ "${RESULT_LEGACY}" == "CONNECTED" ]]; then
        PASSED_TESTS+=("test_sha1_algorithm")
        echo "TEST PASSED"
    else
        FAILED_TESTS+=("test_sha1_algorithm")
        echo "TEST FAILED"
    fi

    echo "####### Finished test_sha1_algorithm"
}

print_results() {
    echo ""
    echo "####### RESULTS"
    echo ""
    echo "TOTAL TESTS: $((${#FAILED_TESTS[@]} + ${#PASSED_TESTS[@]}))"
    echo ""
    echo "PASSED TESTS: ${#PASSED_TESTS[@]}"
    for passed_test in ${PASSED_TESTS[@]}; do
        echo ${passed_test}
    done
    echo ""
    echo "FAILED TESTS: ${#FAILED_TESTS[@]}"
    for failed_test in ${FAILED_TESTS[@]}; do
        echo "(${failed_test}"
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
