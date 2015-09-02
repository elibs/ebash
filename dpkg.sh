#!/bin/bash
# 
# Copyright 2012-2013, SolidFire, Inc. All rights reserved.
#

#-----------------------------------------------------------------------------
# PULL IN DEPENDENT PACKAGES
#-----------------------------------------------------------------------------
source "${BASHUTILS}/efuncs.sh"   || { echo "Failed to find efuncs.sh" ; exit 1; }

dpkg_compare_versions()
{
    $(declare_args v1 op v2)

	[[ ${op} == "<<" ]] && op="lt"
	[[ ${op} == "<=" ]] && op="le"
	[[ ${op} == "==" ]] && op="eq"
	[[ ${op} == "="  ]] && op="eq"
	[[ ${op} == ">=" ]] && op="ge"
	[[ ${op} == ">>" ]] && op="gt"

	## Verify valid comparator ##
	[[ ${op} == "lt" || ${op} == "le" || ${op} == "eq" || ${op} == "ge" || ${op} == "gt" ]] \
		|| die "Invalid comparator [${op}]"

	dpkg --compare-versions ${v1} ${op} ${v2} 
}

dpkg_parsedeps()
{
    $(declare_args deb ?tag)
    : ${tag:="Depends"}

    dpkg -I "${deb}" | ( grep "^ ${tag}:" || true ) | sed -e "s| ${tag}:||" -e 's/ (\(>=\|<=\|<<\|>>\|\=\)\s*/\1/g' -e 's|)||g' -e 's|,||g'
}

dpkg_depends()
{
    $(declare_args input ?tag)
    : ${tag:="Depends"}

    [[ -f ${input} ]] || die "${input} does not exist"
    local deb dir
    deb=$(basename ${input}) || die "basename ${intput} failed"
    dir=$(dirname  ${input}) || die "dirname  ${intput} failed"
    [[ -f ${dir}/${deb} && -d ${dir} ]]   || die "${dir} not a directory or ${dir}/${deb} not a file"

    for p in $(dpkg_parsedeps ${dir}/${deb} ${tag}); do

		# Sensible defaults
		local pn="${p}"
		local op=">="
		local pv=0

		# Versioned?
		if [[ ${p} =~ ([^>=<>]*)(>=|<=|<<|>>|=)(.*) ]]; then
			pn=${BASH_REMATCH[1]}
			op=${BASH_REMATCH[2]}
			pv=${BASH_REMATCH[3]}
		fi

		local fname="${dir}/${pn}.deb"
	
		if [[ -e ${fname} ]]; then
		
			# Correct version?
			local apn apv
            apn=$(dpkg -I "${fname}" | grep "^ Package:"); apn=${apn#*: }
            apv=$(dpkg -I "${fname}" | grep "^ Version:"); apv=${apv#*: }
			
			[[ ${pn} == ${apn} ]] || die "Mismatched package name wanted=[${pn}] actual=[${apn}]"
			dpkg_compare_versions "${apv}" "==" "${pv}" || die "Version mismatch: wanted=[${pn}-${pv}] actual=[${apn}-${apv}] op=[${op}]"
	
			echo ${fname}
			for d in $(dpkg_depends ${dir}/${pn}.deb ${tag}); do
				echo $d
			done
		else
			echo ${p}
		fi
    done
}

dpkg_depends_deb()
{
    for p in $(dpkg_depends $@); do
        [[ ${p: -4} == ".deb" ]] && echo ${p} || true
    done
}

dpkg_depends_apt()
{
    for p in $(dpkg_depends $@); do
        [[ ${p: -4} != ".deb" ]] && echo ${p} || true
    done
}

#-----------------------------------------------------------------------------
# SOURCING
#-----------------------------------------------------------------------------
return 0
