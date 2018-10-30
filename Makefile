#
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

.PHONY: ctags clean clobber

ctags: unittest/*.sh unittest/*.etest share/*.sh bin/*
	ctags -f .tags . $^

clean:
	git clean -fX
	bin/bashutils rm -fr --one-file-system .forge/work

clobber: clean
