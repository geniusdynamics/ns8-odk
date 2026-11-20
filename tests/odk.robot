*** Settings ***
Library    SSHLibrary

*** Variables ***
${TEST_HOST}    odk.ns8-ci.test

*** Test Cases ***
Install ODK Central
    ${output}=    Run On Node    add-module ${IMAGE_URL} 1
    ${module}=    Evaluate    ast.literal_eval($output)["module_id"]    modules=ast
    Set Suite Variable    ${module_id}    ${module}

Configure the HTTPS route and administrator contact
    Run On Node
    ...    api-cli run module/${module_id}/configure-module --data '{"host":"${TEST_HOST}","sysadmin_email":"admin@${TEST_HOST}","lets_encrypt":false}'
    ${output}=    Run On Node    api-cli run module/${module_id}/get-configuration --data '{}'
    ${config}=    Evaluate    json.loads($output)    modules=json
    Should Be Equal    ${config}[host]    ${TEST_HOST}
    Should Be Equal    ${config}[sysadmin_email]    admin@${TEST_HOST}

Serve both Central and its API through Traefik
    Wait Until Keyword Succeeds    3 min    5 sec    Run On Node
    ...    curl -kfsS --max-time 5 --resolve ${TEST_HOST}:443:127.0.0.1 https://${TEST_HOST}/v1/config/public
    ${headers}=    Run On Node    curl -sS --resolve ${TEST_HOST}:80:127.0.0.1 -o /dev/null -D - http://${TEST_HOST}/
    Should Match Regexp    ${headers}    (?im)^location: https://${TEST_HOST}/\\s*$
    ${version}=    Run On Node    curl -kfsS --resolve ${TEST_HOST}:443:127.0.0.1 https://${TEST_HOST}/version.txt
    Should Match Regexp    ${version}    v[0-9]{4}[.][0-9]+[.][0-9]+
    ${output}=    Run On Node    curl -kfsS --resolve ${TEST_HOST}:443:127.0.0.1 https://${TEST_HOST}/v1/config/public
    Evaluate    json.loads($output)    modules=json

Verify supporting services
    FOR    ${unit}    IN    postgresql    redis-main    redis-cache    pyxform    enketo    central    nginx
        Run On Node    runagent -m ${module_id} systemctl --user is-active ${unit}-app.service
    END
    ${pong}=    Run On Node    runagent -m ${module_id} podman exec redis-main-app redis-cli ping
    Should Be Equal    ${pong}    PONG
    ${pong}=    Run On Node    runagent -m ${module_id} podman exec redis-cache-app redis-cli -p 6380 ping
    Should Be Equal    ${pong}    PONG
    Run On Node    runagent -m ${module_id} podman exec pyxform-app python -c 'import socket; socket.create_connection(("127.0.0.1", 8081), 5).close()'
    Run On Node    runagent -m ${module_id} podman exec central-app nc -z 127.0.0.1 8005

Export a logical database backup
    Run On Node    runagent -m ${module_id} module-dump-state
    Run On Node    runagent -m ${module_id} sh -ec 'test -s odk.pg_dump; podman exec -i postgresql-app pg_restore --list < odk.pg_dump'
    Run On Node    runagent -m ${module_id} module-cleanup-state


OIDC can be enabled and disabled without exposing its secret
    Run On Node    api-cli run module/${module_id}/configure-module --data '{"host":"${TEST_HOST}","lets_encrypt":false,"sysadmin_email":"admin@${TEST_HOST}","oidc":{"issuer":"https://idp.example.test/oidc","client_id":"ns8-ci","client_secret":"ci-example-client-secret","enabled":true,"confirmed":true}}'
    ${output}=    Run On Node    api-cli run module/${module_id}/get-configuration
    ${config}=    Evaluate    json.loads($output)["oidc"]    modules=json
    Should Be True    ${config}[enabled]
    Should Be True    ${config}[secret_configured]
    Should Not Contain    ${output}    ci-example-client-secret
    ${page}=    Run On Node    curl -kfsS --resolve ${TEST_HOST}:443:127.0.0.1 https://${TEST_HOST}/client-config.json
    ${client}=    Evaluate    json.loads($page)["oidcEnabled"]    modules=json
    Should Be True    ${client}
    Run On Node    api-cli run module/${module_id}/configure-module --data '{"host":"${TEST_HOST}","lets_encrypt":false,"sysadmin_email":"admin@${TEST_HOST}","oidc":{"enabled":false}}'
    ${page}=    Run On Node    curl -kfsS --resolve ${TEST_HOST}:443:127.0.0.1 https://${TEST_HOST}/client-config.json
    ${client}=    Evaluate    json.loads($page)["oidcEnabled"]    modules=json
    Should Not Be True    ${client}

Remove the module
    Run On Node    remove-module --no-preserve ${module_id}

*** Keywords ***
Run On Node
    [Arguments]    ${command}
    ${output}    ${stderr}    ${rc}=    Execute Command    ${command}    return_stderr=True    return_rc=True
    Should Be Equal As Integers    ${rc}    0    msg=${command}\n${output}\n${stderr}
    RETURN    ${output}
