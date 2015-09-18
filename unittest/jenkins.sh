#!/usr/bin/env bash

$(esource $(dirname $0)/jenkins.sh)

DEMO_JOB_NAME=z_etest_${HOSTNAME}_$$
setup()
{
    JENKINS=bdr-distbox.eng.solidfire.net
    JENKINS_PORT=8080
    JENKINS_RETRIES=5

    TEMPLATE_DIR=${TOPDIR}/unittest/jenkins_templates/
}

ETEST_jenkins_url()
{
    assert [[ "http://bdr-distbox.eng.solidfire.net:8080" == $(jenkins_url) ]] 
}

ETEST_jenkins_cli_basic()
{
    # Will display help and should return a good exit code
    local help=$(jenkins 2>&1)
    echo "${help}" | assert grep Jenkins        >/dev/null
    echo "${help}" | assert grep update-node 	>/dev/null
    echo "${help}" | assert grep update-job     >/dev/null
}

ETEST_jenkins_build_url()
{
    JENKINS="other-machine" JENKINS_PORT=7575 JENKINS_JOB=nojob
    local output=$(jenkins_build_url 30)
    assert [[ "http://other-machine:7575/job/${JENKINS_JOB}/30/" == "${output}" ]] 
}

create_demo_job()
{
    pushd ${TEMPLATE_DIR}
    jenkins_update job etest_demo_job ${DEMO_JOB_NAME}
    popd
}

delete_demo_job()
{
    einfo "Deleting temporary job..."
    jenkins delete-job ${DEMO_JOB_NAME}
}

ETEST_jenkins_create_and_update()
{
    einfo "Creating job."
    create_demo_job
    einfo "Done creating job.  Retrieving it and checking the description"

    validate_demo_job()
    {
        einfo "Validating job contents"
        local jobXml=$(jenkins get-job ${DEMO_JOB_NAME})
        edebug "Retrieved job as XML:"
        edebug "${jobXml}"
        edebug "End job description"
        echo "${jobXml}" | assert xmlstarlet val - >/dev/null
        echo "${jobXml}" | assert grep ${DEMO_JOB_NAME} >/dev/null
    }

    validate_demo_job

    einfo "Updating job."
    create_demo_job
    validate_demo_job

    delete_demo_job
}

ETEST_jenkins_run_a_build()
{
    einfo "Creating job to run $(lval DEMO_JOB_NAME)"
    create_demo_job
    JENKINS_JOB=${DEMO_JOB_NAME}

    sleep 5

    declare -A BUILD_ARGS
    BUILD_ARGS[PARAM]=passed_from_${FUNCNAME}

    eprogress "Starting job $(lval queueUrl BUILD_ARGS)"
    local queueUrl=$(jenkins_start_build)

    while true ; do
        $(tryrc -o=buildNumber jenkins_get_build_number ${queueUrl})
        if [[ ${rc} -eq 0 || -n ${buildNumber} ]] ; then
            break;
        fi
    done
    eprogress_kill

    local buildJson=$(jenkins_build_json ${buildNumber})
    edebug "$(lval buildJson buildNumber)"

    echo "${buildJson}" | jq . &>$(edebug_out)
    
    # Check that the parameter made it in to the job
    $(json_import -q=".actions[0].parameters[0]" <<< ${buildJson} )
    assert [[ ${name} == "PARAM" ]]
    assert [[ ${value} == "${BUILD_ARGS[PARAM]}" ]]

    # That it was successful
    $(json_import result url <<< ${buildJson} )
    assert [[ "${result}" == "SUCCESS" ]]

    # And that our build_url jenkins_function works
    assert [[ "${url}"    == "$(jenkins_build_url ${buildNumber})" ]]

    delete_demo_job
}

ETEST_jenkins_put_file()
{
    local fileContents=$'a   b c\nd e    f'

    echo "${fileContents}" > testFile
    jenkins_put_file testFile

    local readContents=$(jenkins_read_file testFile)

    [[ "${fileContents}" == "${readContents}" ]] || die "read_file contents didn't match $(lval fileContents readContents)"

    jenkins_get_file testFile getFile

    local getContents=$(cat getFile)
    [[ "${fileContents}" == "${getContents}" ]] || die "get_file's contents didn't match $(lval fileContents getContents)"

    edebug "$(lval fileContents getContents readContents)"
}

    
