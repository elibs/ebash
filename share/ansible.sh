#!/bin/bash
#
# Copyright 2021, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

opt_usage ansible_status <<'END'
`ansible_status` is used to relay status back to Ansible in expected JSON format for completed tasks.
This prints status for Ansible in the following format -
{"failed": <true|false> "changed": <true|false> "msg": <user provided message>}
END
ansible_status()
{
    $(opt_parse \
        "+failed      f | Did this module fail."                \
        "+changed     c | Did this module change anything."     \
        "=message msg m | Message associated with this status." \
    )

    # Convert boolean values in failed and changed to string values
    failed=$(bool_to_string "${failed}")
    changed=$(bool_to_string "${changed}")

    # Note - Ansible is particular about it's status output. We need to escape
    #        any characters with special meaning in JSON.
    msg=$(json_escape "${msg}")
    printf '{"failed": %s, "changed": %s, "msg": %s}' "${failed}" "${changed}" "${msg}"
}
