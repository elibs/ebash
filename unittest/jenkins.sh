#!/usr/bin/env bash

DEMO_JOB_NAME=z_etest_${HOSTNAME}_$$
setup()
{
    JENKINS=bdr-distbox.eng.solidfire.net
    JENKINS_PORT=8080

    TEMPLATE_DIR=${ETEST_TOPDIR}/unittest/jenkins_templates/
}

ETEST_jenkins_url()
{
    assert [[ "http://bdr-distbox.eng.solidfire.net:8080" == $(jenkins_url) ]] 
}

ETEST_jenkins_cli_basic()
{
    # Will display help and should return a good exit code
    local help=$(jenkins help 2>&1)
    echo "${help}" | assert grep Jenkins        >/dev/null
    echo "${help}" | assert grep update-node 	>/dev/null
    echo "${help}" | assert grep update-job     >/dev/null
}

ETEST_jenkins_build_url()
{
    JENKINS="other-machine" JENKINS_PORT=7575 JENKINS_JOB=nojob

    # Force jenkins.sh to build this up from JENKINS/JENKINS_PORT rather than
    # honoring a JENKINS_URL set in its environment
    unset JENKINS_URL

    local output=$(jenkins_build_url 30)
    assert [[ "http://other-machine:7575/job/${JENKINS_JOB}/30/" == "${output}" ]] 
}

create_demo_job()
{
    etestmsg "Creating jenkins job ${DEMO_JOB_NAME}"
    pushd ${TEMPLATE_DIR}
    jenkins_update job etest_demo_job ${DEMO_JOB_NAME}
    popd

    # Wait for jenkins to get its act together and realize that it _has_ created the job
    etestmsg "Waiting for jenkins to reflect the created job in its API"
    eretry jenkins get-job ${DEMO_JOB_NAME} &>/dev/null
    edebug "Jenkins acknowledged existence of ${DEMO_JOB_NAME}"

}

delete_demo_job()
{
    etestmsg "Deleting ${DEMO_JOB_NAME}..."
    jenkins delete-job ${DEMO_JOB_NAME}
}

ETEST_jenkins_create_and_update()
{
    etestmsg "Creating job."
    create_demo_job
    trap_add "delete_demo_job "
    etestmsg "Done creating job.  Retrieving it and checking the description"

    validate_demo_job()
    {
        etestmsg "Validating job contents"
        local jobXml=$(jenkins get-job ${DEMO_JOB_NAME})
        einfo "Job xml:"
        echo "${jobXml}"
        einfo "End job xml"
        echo "${jobXml}" | assert xmlstarlet val - >/dev/null
        echo "${jobXml}" | assert grep ${DEMO_JOB_NAME} >/dev/null
        echo "${jobXml}" | assert grep PARAM >/dev/null
    }

    validate_demo_job

    etestmsg "Updating job."
    create_demo_job
    validate_demo_job

    # Also verify that the create-job hook correctly identifies when it's
    # trying to create a job that already exists with a specific error code of
    # 50
    etestmsg "Verifing that jenkins-cli create-job returns code 50 when attempting to create a job that already exists."
    $(tryrc jenkins create-job ${DEMO_JOB_NAME})
    assert_eq 50 ${rc} "create-job return code"
}

ETEST_jenkins_delete_idempotent()
{
    create_demo_job
    delete_demo_job
    delete_demo_job
}

ETEST_jenkins_delete_missing()
{
    for type in job node view ; do
        etestmsg "Trying to delete a non-existent ${type}"
        jenkins delete-${type} this-${type}-doesnt-exist-$$
    done
}

ETEST_jenkins_update_missing()
{
    for type in job node view ; do
        etestmsg "Trying to update a non-existent job, expecting return code 50"
        $(tryrc jenkins update-${type} this-${type}-doesnt-exist-$$)
        assert_eq 50 ${rc} "update-${type} return code"
    done
}

ETEST_jenkins_create_preexisting_job()
{
    etestmsg "Making sure ${DEMO_JOB_NAME} exists on jenkins"
    create_demo_job
    etestmsg "Calling jenkins-cli create-job with same job name"
    $(tryrc jenkins create-job ${DEMO_JOB_NAME})
    assert_eq 50 ${rc} "create-job return code"
}

ETEST_jenkins_run_a_build()
{
    etestmsg "Creating job to run $(lval DEMO_JOB_NAME)"
    create_demo_job
    trap_add "delete_demo_job "
    JENKINS_JOB=${DEMO_JOB_NAME}

    declare -A BUILD_ARGS
    BUILD_ARGS[PARAM]=passed_from_${FUNCNAME}

    eprogress "Starting job $(lval queueUrl BUILD_ARGS)"
    local queueUrl=$(jenkins_start_build)

    while true ; do
        $(tryrc -o=buildNumber jenkins_get_build_number ${queueUrl})
        if [[ ${rc} -eq 0 && -n ${buildNumber} ]] ; then
            break;
        fi
    done
    eprogress_kill

    #  Wait until the job has a build result (not quite the same as "complete"
    #  for complicated jobs, but pretty darn close for the test one)
    etestmsg "Waiting for job to run."
    eretry -r=30 -t=2 -d=1 jenkins_build_result ${buildNumber}

    etestmsg "Gathering results from job."
    local buildJson=$(jenkins_build_json ${buildNumber})
    edebug "$(lval buildJson buildNumber)"

    echo "${buildJson}" | jq . &>$(edebug_out)
    
    # Check that the parameter made it in to the job
    $(json_import -q=".actions[0].parameters[0]" <<< ${buildJson} )
    assert [[ ${name} == "PARAM" ]]
    assert [[ ${value} == "${BUILD_ARGS[PARAM]}" ]]


    # That it was successful
    $(json_import result url <<< ${buildJson} )
    assert_eq "SUCCESS" "${result}" "build result extracted from json"

    assert_eq "SUCCESS" "$(jenkins_build_result ${buildNumber})" "jenkins_build_result output"

    # And that our build_url jenkins_function works
    assert [[ "${url}"    == "$(jenkins_build_url ${buildNumber})" ]]

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

ETEST_jenkins_slave_status()
{
    local slaveName=$(jenkins_list_slaves | tail -n 1 | awk -F, '{print $1}')
    local slaveStatus=$(jenkins_slave_status ${slaveName})

    etestmsg "Found slave status $(lval slaveName slaveStatus)"
    assert [[ "${slaveStatus}" == "online" \|\| "${slaveStatus}" == "offline" ]]
}

ETEST_jenkins_nonexistent_slave_is_offline()
{
    JENKINS=noserver $(tryrc -o=status jenkins_slave_status this-slave-does-not-really-exist)

    assert_eq "0" ${rc}
    assert_eq offline "${status}"
}

    
