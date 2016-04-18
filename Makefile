.PHONY: ctags clean

ctags: *.sh unittest/*.sh unittest/*.etest bashlint ebench etest ibu
	ctags -f .tags . $^

clean:
	git clean -fX
	rm -fr --one-file-system .forge/work
