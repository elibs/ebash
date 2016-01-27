#!/bin/bash
# 
# Copyright 2012-2014, SolidFire, Inc. All rights reserved.
#

#
# Echo the URL to use to connect to a specified JENKINS instance. If JENKINS_URL
# has already been defined it will use this. Otherwise it will expect JENKINS
# and JENKINS_PORT to be defined.
#
jenkins_url()
{
    if [[ -n ${JENKINS_URL:-} ]] ; then
        # Take JENKINS_URL, removing a trailing slash if there is one (because
        # callers of jenkins_url assume it will not return a final slash, as
        # that's how it works with JENKINS/JENKINS_PORT)
        echo "${JENKINS_URL%/}"

    else
        argcheck JENKINS JENKINS_PORT
        echo -n "http://${JENKINS}:${JENKINS_PORT}"
    fi
}

################################################################################
# Execute a jenkins-cli command, with automatic timeouts and retries.  For more
# information on jenkins-cli commands, see the jenkins documentation or run
# "jenkins help"
#
# Note that calls through this function may also be enhanced via hooks.  See
# documentation on jenkins_internal for more information on how to use them and
# what they do.
#
# Options supported:
#   -f=<file>:  The specified file will be presented to jenkins-cli on stdin.
#               Useful for commands like create-job and update-node.
#
# Environment variables honored:
#     JENKINS_RETRIES:
#       Number of times to retry the command.  Defaults to 20.
#
#     JENKINS_TIMEOUT:
#       How long to wait for the command to succeed.  Note that some commands
#       legitimately take longer than others. Default is 7s.
#
#     JENKINS_WARN_EVERY:
#       How many attempts to make before spewing a warning that things aren't
#       working as spected.  Defaults to every 3 attempts, which means warnings
#       will come out approximately every 21 seconds given the default for
#       JENKINS_TIMEOUT
#
jenkins()
{
    jenkins_prep_jar
    local nonRetryExitCodes=$(echo 0 {50..59})
    eretry -e="${nonRetryExitCodes}" -r=${JENKINS_RETRIES:-20} -t=${JENKINS_TIMEOUT:-10s} -w=${JENKINS_WARN_EVERY:-3} \
        jenkins_internal "${@}"
}

jenkins_prep_jar()
{
    if [[ -z ${JENKINS_CLI_JAR:=} || ! -r ${JENKINS_CLI_JAR} ]] ; then
        local tempDir
        tempDir=$(mktemp -d /tmp/jenkins.sh.tmp-XXXXXXXX)
        efetch "$(jenkins_url)/jnlpJars/jenkins-cli.jar" "${tempDir}" |& edebug
        export JENKINS_CLI_JAR="${tempDir}/jenkins-cli.jar"
        trap_add "edebug \"Deleting ${JENKINS_CLI_JAR}.\" ; rm --recursive --force --one-file-system \"${tempDir}\""
    fi
}

#
# Creates an item of the specified type on jenkins, or updates it if it exists
# and is different than what you would create.
#
# item_type:
#    node, view, or job
#
# template:
#    The filename (basename with extension only) of one of the templates stored
#    in scripts/jenkins_templates.
#
# You must also specify any parameters needed by that template as environment
# variables.  Look in the individual template files to determine what
# parameters are needed.
#
jenkins_update()
{
    $(declare_args itemType template name)

    # Old versions of jenkins_update expected the template name to contain
    # .xml.  Drop the .xml if old clients provide it.
    template=${template%%.xml}

    [[ -d "scripts" ]] || die "jenkins_update must be run from repository root directory."
    [[ -d "scripts/jenkins_templates/${itemType}" ]] || die "jenkins_update cannot create ${itemType} items."

    local xmlTemplate="scripts/jenkins_templates/${itemType}/${template}.xml"
    [[ -r "${xmlTemplate}" ]] || die "No ${itemType} template named ${template} found."

    # Look for the optional script template
    local scriptFile="" scriptTemplate=""
    scriptTemplate="scripts/jenkins_templates/${itemType}/${template}.sh"

    [[ -r "${scriptTemplate}" ]] || scriptTemplate=""
    [[ -z ${scriptTemplate} ]] || scriptFile=$(mktemp "/tmp/jenkins_update_${itemType}_${template}_script_XXXX")
    local newConfig oldConfig
    newConfig=$(mktemp "/tmp/jenkins_update_${itemType}_${template}_XXXX")
    oldConfig=$(mktemp "/tmp/jenkins_update_${itemType}_${template}_old_XXXX")

    trap_add "rm --recursive --force --one-file-system ${scriptFile} ${newConfig} ${oldConfig}"

    # Expand parameters in the script (if one was found), and place its
    # contents into a variable so that it can be plunked into the XML file
    if [[ -n ${scriptTemplate} ]] ; then
        cp -arL "${scriptTemplate}" "${scriptFile}"
        setvars "${scriptFile}"
        export JENKINS_UPDATE_SCRIPT=$(cat "${scriptFile}")
    fi

    cp -arL "${xmlTemplate}" "${newConfig}"
    setvars "${newConfig}" setvars_escape_xml


    # Try to create the job.
    #
    # Note: jenkins doesn't have an operation that is idempotent for this -- we
    # must try to create it and then update it if we determine that it already
    # existed.  We have in the past tried to update first and create if the
    # update failed, but it didn't work well with our automatic retries.
    # Specifically, this would occasionally happen.
    #
    #   1) Tried update.  It fails because the job does not exist.
    #   2) Try create.  Locally, it times out because jenkins is slow, but this
    #      operation eventually succeeded on the server.
    #   3) Now when create runs, it sees that the job already exists on the
    #      server and knows better than to keep retrying.  But the create call
    #      has no way of determining if it's current, so it fails.
    #
    # When the order is reversed, this is less of a problem.  If create fails
    # because the job already exists for any reason, we'll update it just to be
    # sure.
    #
    $(tryrc -o=stdout -e=stderr jenkins -f="${newConfig}" create-${itemType} "${name}")

    # If the job was already there, then we need to update it.
    if [[ ${rc} -eq 50 ]] ; then
        jenkins -f="${newConfig}" update-${itemType} "${name}" |& edebug

    # If the create passed, we're good!
    elif [[ ${rc} -eq 0 ]] ; then
        return 0

    # If it failed for another reason, jenkins is hosed.  Spew the errors from
    # the create call in case they're useful.
    else
        echo -n "${stdout}"
        echo -n "${stderr}" >&2
        die "Unable to update item because jenkins is not responding $(lval name itemType JENKINS)"
    fi
}

# This is a setvars callback method that properly escapes raw data so that it
# can be inserted into an xml file
setvars_escape_xml()
{
    $(declare_args _ ?val)
    echo "${val}" | xmlstarlet esc
}

#
# Start a build on jenkins.
#
#     JENKINS: Jenkins server hostname or IP.
#     JENKINS_JOB: Name of a job on that jenkins.
#     BUILD_ARGS: Associative array containing names and values of the parameters that your jenkins job requires.
#
# This function echos the URL returned by jenkins, which points to the queue entry created for your job.  You might want
# to pass this as QUEUE_URL to jenkins_get_build_number.
#
# If unable to start the job, this function produces no output on stdout.
#
jenkins_start_build()
{
    argcheck JENKINS JENKINS_JOB

    # Skip jenkins' "quiet period"
    local args="-d delay=0sec "

    edebug "Starting build $(lval JENKINS_JOB)"

    for arg in ${!BUILD_ARGS[@]} ; do
        args+="-d ${arg}=${BUILD_ARGS[$arg]} "
    done

    local rc=0
    local url="$(jenkins_url)/job/${JENKINS_JOB}/buildWithParameters"

    local response=$(curl --silent --data-urlencode -H ${args} ${url} --include) || rc=$?
    local queueUrl=$(echo "${response}" | awk '$1 == "Location:" {print $2}' | tr -d '\r') || rc=$? 

    edebug "$(lval rc url response queueUrl)"

    [[ ${rc} == 0 ]] && echo "${queueUrl}api/json" || return ${rc}
}

#
# Given the JSON api URL for an item in the jenkins queue, this function will echo the build number for that item if it
# has started.  If it has not started yet, this function will produce no output.
#
#     QUEUE_URL: The URL of your build of interest in the queue.  (What was returned when you called
#                jenkins_start_build)
#
jenkins_get_build_number()
{
    $(declare_args queueUrl)
    local number rc

    number=$(curl --fail --silent ${queueUrl} | jq -M ".executable.number") && rc=0 || rc=$?

    [[ ${rc} == 0 && ${number} != "null" ]] && echo "${number}" || return ${rc}
}

#
# Get the URL that provides information about a particular jenkins build.
#   JENKINS_JOB:   must be set to the name of your jenkins job (e.g. dtest_modell)
#   $1:            the build number within that job
#   $2 (optional): json or xml if you'd like the URL for data in that format
#
jenkins_build_url()
{
    $(declare_args buildNum ?format)
    echo -n "$(jenkins_url)/job/${JENKINS_JOB}/${buildNum}/"

    [[ ${format} == "json" ]] && echo -n "api/json"
    [[ ${format} == "xml"  ]] && echo -n "api/xml"
    echo ""
}

#
# Retrieve the json data for a particular build, given its job and build number.
#    JENKINS_JOB:   should be set to the name of your jenkins job (e.g. dtest_modell)
#    $1:            the build number within that job (e.g. 12048)
#    $2 (optional): value of the jenkins tree parameter which can limit the json data returned from the server.
#
# See <jenkins>/api's information under "Controlling the amount of data you fetch" for how to use the tree
# parameter.  Basically, it allows you to select smaller portions of the tree of json data that jenkins would
# typically return.  For example, to get just the results field and the duration, you would use a tree value
# of
#     result,duration
# or to get all of the parameters you might say
#     actions.parameters
# 
# Sure, you can do this stuff with jq.  But this requires the jenkins server to collect and send back less data.
#
jenkins_build_json()
{
    $(declare_args buildNum ?tree)
    local url treeparm="" json rc

    url=$(jenkins_build_url ${buildNum} json)
    [[ -n ${tree} ]] && treeparm="-d tree=$tree"

    json=$(curl --fail --silent ${treeparm} ${url}) && rc=0 || rc=$?
    
    if [[ ${rc} -ne 0 ]] ; then
        edebug "Error reading json on build for ${JENKINS_JOB} #${BUILD_NUMBER}" 
        return ${rc} 

    else 
        echo "${json}"
        return 0

    fi
}

#
# Writes one of the jenkins build status words to stdout once that status is
# known.  Note that this does NOT necessarily mean that the test is completed.
# Once a build status is known to jenkins, it can be retrieved here.
#
# The set of possible return values is determined by jenkins as these values
# come directly from it.  Here are the ones I have seen:
#
#   ABORTED
#   FAILURE
#   SUCCESS
#
jenkins_build_result()
{
    $(declare_args buildNum)

    try
    {
        local json status rc
        json=$(jenkins_build_json ${buildNum} result)
        status=$(echo "${json}" | jq --raw-output .result)

        if [[ ${status} == "null" ]] ; then
            echo ""
            return 1
        else
            echo "${status}"
            return 0
        fi
    }
    catch
    {
        return 2
    }
}

#
# Returns success if the specified build is still actively being processed by
# jenkins.  This is different than whether it was successful, or even it has
# been declared as aborted or failed.  Even in those states, it may still spend
# a while processing artifacts.
#
# Once this returns false, all processing is complete
#
jenkins_build_is_running()
{
    $(declare_args buildNum)
    argcheck JENKINS_JOB

    try
    {
        local json=$(jenkins_build_json ${buildNum} building)
        local result=$(echo "${json}" | jq --raw-output '.building')

        [[ ${result} == "true" ]] 
        return 0
    }
    catch
    {
        return $?
    }
}
#
# Retrieves a list of artifacts associated with a particular jenkins build.
#
jenkins_list_artifacts()
{
    $(declare_args buildNum)
    argcheck JENKINS_JOB

    local json rc url
    try
    {
        json=$(jenkins_build_json ${buildNum} 'artifacts[relativePath]')
        url=$(jenkins_build_url ${buildNum})
        echo ${json} | jq --raw-output '.artifacts[].relativePath'
    }
    catch
    {
        return $?
    }
}

jenkins_get_artifact()
{
    $(declare_args buildNum artifact)
    argcheck JENKINS_JOB

    curl --fail --silent "$(jenkins_build_url ${buildNum})artifact/${artifact}"
}

#
# Cancel queued builds whose DTEST_TITLE is equal to the one specified
#
jenkins_cancel_queue_jobs()
{
    $(declare_args dtest_title)

    # NOTE: I'm ignoring a jq error here -- the select I'm using ignores the
    # fact that not all items in the .actions array have .parameters[] in them.
    # But I only care about the ones that do and I can't figure out how to
    # nicely tell jq to skip them.
    local ids
    ids=$(curl --fail --silent $(jenkins_url)/queue/api/json \
        | jq '.items[] | select( .actions[].parameters[].value == "'${dtest_title}'" and .actions[].parameters[].name == "DTEST_TITLE")' 2> /dev/null \
        | jq .id \
        | sed 's/"//g' || true)

    edebug "Killing jenkins queued items $(lval ids)"
    for id in ${ids} ; do
        curl --fail --silent --data "id=${id}" $(jenkins_url)/queue/cancelItem |& edebug || true
    done
}

jenkins_stop_build()
{
    $(declare_args buildNum ?job)
    : ${job:=${JENKINS_JOB}}

    edebug "Stopping jenkins build ${job}/${buildNum} on ${JENKINS}."
    curl --fail -X POST --silent "$(jenkins_url)/job/${job}/${buildNum}/stop"
}

#
# Stop a build given its default URL (e.g. http://bdr-distbox:8080/job/dtest_modell/3)
#
# NOTE: The job will be marked as "ABORTED" as soon as the POST is complete,
# but it may not be finished "building" yet, because jenkins still collects
# artifacts for aborted jobs.
#
jenkins_stop_build_by_url()
{
    $(declare_args buildUrl)

    edebug $(lval buildUrl)

    curl --fail -X POST --silent "${buildUrl}/stop"
}

#
# Cancel _running_ builds whose DTEST_TITLE is equal to the one specified
#
jenkins_cancel_running_jobs()
{
    local DTEST_TITLE=${1}
    local JENKINS_JOB=${2:-${JENKINS_JOB}}

    argcheck DTEST_TITLE JENKINS_JOB

    curl --fail --silent $(jenkins_url)/job/${JENKINS_JOB}/api/json
}

################################################################################
# Print out information about available slaves in comma-separated format.  The
# fields on each line are:
#
#    1: Jenkins slave name (e.g. distbox_odell-dev)
#    2: Hostname or IP where that slave can be reached
#    3: Port of available SSH service on that host
#    4: true = the slave is online, false = the slave is offline
#    5: Space-separated list of labels that jenkins has associated with that
#       slave.
#
jenkins_list_slaves()
{
    # Create a temporary file to hold the groovy script.
    local groovy_script
    groovy_script=$(mktemp /tmp/jenkins_list_slaves-XXXXXXXX.groovy)
    trap_add "edebug \"Deleting ${groovy_script}.\" ; rm --recursive --force --one-file-system \"${groovy_script}\""
   
    cat > ${groovy_script} <<-ENDGROOVY
	for (slave in jenkins.model.Jenkins.instance.slaves) {
		println (slave.name + "," 
					+ slave.launcher.host + ","
					+ slave.launcher.port + ","
					+ slave.computer.isOnline() + ","
					+ slave.getLabelString())
    }
	ENDGROOVY

    jenkins -f="${groovy_script}" groovy =
}

#
# Writes the current status of the slave on jenkins (either online or offline)
# to stdout.  If the slave does not exist or the status cannot be retrieved, it
# will be assumed to be offline.
#
#  $1: The name of the slave you're interested in, according to jenkins (e.g.
#      bdr-ds24.eng.solidfire.net).
#
jenkins_slave_status()
{
    $(declare_args slaveName)

    try
    {
        local response=$(curl --fail --silent -d tree=offline $(jenkins_url)/computer/${slaveName}/api/json)
        local slave_offline=$(echo "${response}" | jq --raw-output .offline 2>/dev/null)

        if [[ ${slave_offline} == false ]] ; then
            echo "online"
        else
            echo "offline"
        fi
    }
    catch
    {
        # Assume offline if we were unable to get the slave's status
        echo "offline"
    }

    return 0
}

ssh_jenkins()
{
    argcheck JENKINS

    # Hide the "host key permanently added" warnings unless EDEBUG is set
    local hideWarnings=""
    edebug_enabled && hideWarnings="-o LogLevel=quiet"

    : ${JENKINS_USER:=root}

    # Use sshpass to send the password if it was given to us
    if [[ -n ${JENKINS_PASSWORD:-} && -n ${JENKINS_USER:-} ]] ; then
        edebug "Connecting to jenkins via pre-set JENKINS_PASSWORD and JENKINS_USER"
        sshpass -p ${JENKINS_PASSWORD} \
            ssh -o PreferredAuthentications=password \
                -o UserKnownHostsFile=/dev/null \
                -o StrictHostKeyChecking=no \
                -x \
                ${hideWarnings} \
                ${JENKINS_USER}@${JENKINS} \
                "${@}"
    else
        edebug "Connecting to jenkins assuming that keys are set up, because password was not given"
        # Otherwise, assume that keys are set up properly
        ssh -o BatchMode=yes \
            -o UserKnownHostsFile=/dev/null \
            -o StrictHostKeyChecking=no \
            -x \
            ${hideWarnings} \
            ${JENKINS_USER}@${JENKINS} \
            "${@}"
    fi
}

################################################################################
# Files stored on jenkins via jenkins_put_file do not use a standard jenkins
# service.  Rather, at SolidFire we add a web service on the same machine _AT A
# DIFFERENT PORT_ that hosts files in /tmp, and then we can copy the files to
# that location via ssh.
#
# This function returns the url of a file stored in this way.
#
jenkins_file_url()
{
    $(declare_args file)
    argcheck JENKINS

    echo "http://${JENKINS}/tmp/${file}"
}

################################################################################
# Takes a specified file (or - for stdin) and writes it to jenkins where it may
# be retrieved by other processes.
#
#    $1   Name of the local file
#    $2   (optional) target filename on jenkins
#
jenkins_put_file()
{
    $(declare_args file ?outputFile)
    argcheck JENKINS
    : ${outputFile:=$(basename $file)}

    cat ${file} | ssh_jenkins 'cat > /tmp/'${outputFile}
}

################################################################################
# Retrieves a file from jenkins that was placed there via jenkins_put_file, and
# places it on stdin.
#
#     $1    Name of the file on jenkins
#
jenkins_read_file()
{
    $(declare_args file)

    curl --fail --silent $(jenkins_file_url ${file})
}

################################################################################
# Retrieves a file from jenkins that was placed there with jenkins_put_file.
#
#    $1     Name of the file on jenkins
#    $2     (optional) target output file.
#
jenkins_get_file()
{
    $(declare_args file ?outputFile)
    : ${outputFile:=$(basename $file)}

    jenkins_read_file ${file} > ${outputFile} 
}

################################################################################
# Delete any number of files from jenkins that were placed there via
# jenkins_put_file
#
#    ${@}    File name on jenkins
#
jenkins_delete_files()
{
    local allFiles=()
    for file in ${@} ; do
        allFiles+=("/tmp/${file}")
    done

    [[ ${#allFiles[@]} -gt 0 ]] && ssh_jenkins "rm --force ${allFiles[@]}" || true
}

################################################################################
# This function is used internally by "jenkins" to execute jenkins-cli
# commands.  While "jenkins" is called once and performs retries,
# jenkins_internal is run once per attempt.  It's primary function is related
# to "hooks".
#
# Jenkins cli API does a lot of ridiculous things that it would be nice for it
# not to do.  So we tweak it to work differently.  If a function named
# "jenkins_<jenkins API command name>_hook"  exists, I'll run it to allow it
# take care of processing the results.  (NOTE: bash functions names can't have
# hyphens in them, but jenkins api commands do, so I replace those with
# underscores)
#
# Command hooks should accept three parameters.  Its responsibility is to do
# what it wants done with these.  Whatever it returns will actually be returned
# as the result of this command, and whatever it outputs will be output (i.e.
# the original streams are hidden to this point so that it can decide what to
# do with them)
#    $1: Return code of the jenkins command itself
#    $2: The stdout stream provided by the jenkins cli
#    $3: The stderr stream provided by the jenkins cli
#
# If you'd like to create special return codes (i.e. ones that jenkins wouldn't
# typically return that perhaps mean something), please choose them from these
# ranges:
#
#   40-49: A specific error occurred which should be retried (document what
#          near your hook function)
#   50-59: A specific error occured that should NOT be retried because a
#          retry won't help the situation.  Again, document what near your
#          hook function.
#
# If you want to do the "default" thing with those three items, call
# jenkins_internal_end like this:
#
#   jenkins_internal_end "${rc}" "${stdout}" "${stderr}"
#
jenkins_internal()
{
    $(declare_opts ":filename file f | Name of file to send to specified jenkins command as its input.")

    local cmd=( "${@}" )
    local rc=0

    [[ $(array_size cmd) -eq 0 ]] && cmd=("")

    edebug "$(lval cmd filename)"

    # Execute jenkins API command
    if [[ -n ${filename:-} ]] ; then
        $(tryrc -o=stdout -e=stderr \
            java -jar "${JENKINS_CLI_JAR}" -s $(jenkins_url) "${cmd[@]}" < "${filename}")
    else
        $(tryrc -o=stdout -e=stderr \
            java -jar "${JENKINS_CLI_JAR}" -s $(jenkins_url) "${cmd[@]}")
    fi

    local hookName="jenkins_${cmd[0]:-}_hook"
    hookName=${hookName//[- ]/_}

    if declare -f ${hookName} &>/dev/null ; then
        edebug "Calling hook for ${cmd[0]} $(lval hookName rc)"
        ${hookName} "${rc}" "${stdout}" "${stderr}"
    else
        jenkins_internal_end "${rc}" "${stdout}" "${stderr}"
    fi
    # NOTE: No statements after if block because we rely on the return code
    # from the final statement executed in each branch of it.
}

# Used by jenkins_internal and its hook mechanism.  See comments inside
# jenkins_internal
jenkins_internal_end()
{
    $(declare_args rc ?stdout ?stderr)

    edebug "Returning ${rc} as result of jenkins command"
    echo "${stdout}"
    echo "${stderr}" >&2
    return ${rc}
}

################################################################################
# jenkins-cli hooks

# Called by hooks for create-view, create-job, and create-node in order to make
# them more idempotent.  We hit problems when we try to create a job but then
# percieve it locally to time out and the server perceives it to complete.
#
# This causes create-view, create-job, and create-node to return 50 when they
# try to create one but it already exists.
#
jenkins_create_star_hook()
{
    $(declare_args rc ?stdout ?stderr itemType)

    local alreadyExists=0
    echo "${stderr}" | grep -Piq "${itemType} .* already exists" || alreadyExists=$?

    if [[ ${rc} -ne 0 && ${alreadyExists} -eq 0 ]] ; then
        stderr="Cannot create ${itemType} as it already exists."
        stdout=""
        rc=50
    fi

    edebug "$(lval rc itemType alreadyExists)"
    jenkins_internal_end "${rc}" "${stdout}" "${stderr}"
}

# see jenkins_create_star_hook
jenkins_create_job_hook()
{
    $(declare_args rc ?stdout ?stderr)
    jenkins_create_star_hook ${rc} "${stdout}" "${stderr}" "job"
}
# see jenkins_create_star_hook
jenkins_create_node_hook()
{
    $(declare_args rc ?stdout ?stderr)
    jenkins_create_star_hook ${rc} "${stdout}" "${stderr}" "node"
}
# see jenkins_create_star_hook
jenkins_create_view_hook()
{
    $(declare_args rc ?stdout ?stderr)
    jenkins_create_star_hook ${rc} "${stdout}" "${stderr}" "view"
}


# Called by hooks for update-view, update-job, and update-node to give a
# specific exit code (50) when the job doesn't exist yet.
#
jenkins_update_star_hook()
{
    $(declare_args rc ?stdout ?stderr itemType)
    local foundNoSuchItem=0

    local regex
    case ${itemType} in
        job)
            regex="No such job.*; perhaps you meant" ;;
        view)
            regex="No view named .* inside view Jenkins" ;;
        node)
            regex="No such node" ;;
        *)
            die "Unsupported item type ${itemType}"
    esac

    echo "${stderr}" | grep -Piq "${regex}" || foundNoSuchItem=$?

    if [[ ${rc} -eq 255 && ${foundNoSuchItem} -eq 0 ]] ; then
        stderr="Cannot update ${itemType} as it does not exist."
        stdout=""
        rc=50
    fi

    edebug "$(lval rc itemType foundNoSuchItem)"
    jenkins_internal_end "${rc}" "${stdout}" "${stderr}"
}

# see jenkins_update_star_hook
jenkins_update_job_hook()
{
    $(declare_args rc ?stdout ?stderr)
    jenkins_update_star_hook ${rc} "${stdout}" "${stderr}" "job"
}

# see jenkins_update_star_hook
jenkins_update_node_hook()
{
    $(declare_args rc ?stdout ?stderr)
    jenkins_update_star_hook ${rc} "${stdout}" "${stderr}" "node"
}

# see jenkins_update_star_hook
jenkins_update_view_hook()
{
    $(declare_args rc ?stdout ?stderr)
    jenkins_update_star_hook ${rc} "${stdout}" "${stderr}" "view"
}


# Called by hooks for delete-view, delete-job, and delete-node.  Jenkins
# typical behavior for these calls is to _FAIL_ if the job exists.  It would be
# much easier to deal with if it was more idempotent.  So this hook makes it so.
#
# The original design makes life difficult with our automatic timeout and
# reties.  Sometimes we'll time out a request and fail it, but jenkins will
# still honor it because it got far enough to tell the server what to do.  But
# that request is marked as a local failure because of the time out.  Then all
# of the subsequent retries fail because the job doesn't exist.  BAH.
#
# This hook makes the call appear successful if the job doesn't exist.
#
jenkins_delete_star_hook()
{
    $(declare_args rc ?stdout ?stderr itemType)

    local regex
    case ${itemType} in
        job)
            regex="No such job.* exists. Perhaps you meant" ;;
        view)
            regex="No view named .* inside view Jenkins" ;;
        node)
            regex="No such slave .* exists. Did you mean" ;;
        *)
            die "Unsupported item type ${itemType}"
    esac

    local foundNoSuchItem=0
    echo "${stderr}" | grep -Piq "${regex}" || foundNoSuchItem=$?

    if [[ ${rc} -ne 0 && ${foundNoSuchItem} -eq 0 ]] ; then
        edebug "Detected that item is already gone.  Marking jenkins get-${itemType} request as successful."
        stderr=""
        stdout=""
        rc=0
    fi

    edebug "$(lval rc itemType foundNoSuchItem)"
    jenkins_internal_end "${rc}" "${stdout}" "${stderr}"
}

jenkins_delete_job_hook()
{
    $(declare_args rc ?stdout ?stderr)
    jenkins_delete_star_hook ${rc} "${stdout}" "${stderr}" "job"
}
jenkins_delete_node_hook()
{
    $(declare_args rc ?stdout ?stderr)
    jenkins_delete_star_hook ${rc} "${stdout}" "${stderr}" "node"
}
jenkins_delete_view_hook()
{
    $(declare_args rc ?stdout ?stderr)
    jenkins_delete_star_hook ${rc} "${stdout}" "${stderr}" "view"
}

jenkins_no_such_slave_common_hook()
{
    $(declare_args rc ?stdout ?stderr)

    local foundNoSuchNode=0
    echo "${stderr}" | grep -Piq "No such slave .* exists. Did you mean" || foundNoSuchNode=$?

    if [[ ${rc} -eq 1 && ${foundNoSuchNode} -eq 0 ]] ; then
        rc=50
    fi

    jenkins_internal_end "${rc}" "${stdout}" "${stderr}"
}

jenkins_offline_node_hook()
{
    $(declare_args rc ?stdout ?stderr)
    jenkins_no_such_slave_common_hook ${rc} "${stdout}" "${stderr}" "view"
}

jenkins_online_node_hook()
{
    $(declare_args rc ?stdout ?stderr)
    jenkins_no_such_slave_common_hook ${rc} "${stdout}" "${stderr}" "view"
}

jenkins_wait_node_offline_hook()
{
    $(declare_args rc ?stdout ?stderr)
    jenkins_no_such_slave_common_hook ${rc} "${stdout}" "${stderr}" "view"
}

return 0
