.PHONY: ctags clean

ctags: unittest/*.sh unittest/*.etest share/*.sh bin/*
	ctags -f .tags . $^

clean:
	git clean -fX
	rm -fr --one-file-system .forge/work
